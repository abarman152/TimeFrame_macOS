//
//  LoginItemTests.swift
//  time_frameTests (Milestone 32)
//
//  "Open at Login" has one rule that matters: the toggle shows what macOS actually holds
//  (ADR-112). A setting that reads "on" while nothing is registered is worse than no setting,
//  because the user only finds out at the next login.
//
//  These tests drive `LoginItemCoordinator` over a fake `LoginItemManaging` — the suite never
//  touches the real login-item database, and the app's own launch injects
//  `UnavailableLoginItemService` under the test host for the same reason (ADR-077). What is
//  asserted here is the direction of truth: every path ends by re-reading the service, so a
//  refused registration leaves the switch off, and a registration awaiting approval does not
//  read as on.
//

import Foundation
import Testing
@testable import time_frame

// MARK: - Fake service

/// A scriptable login-item service. `status` is what "the system" reports; the failure flags
/// make a register/unregister refuse without changing it.
final class FakeLoginItemService: LoginItemManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: LoginItemStatus
    private var _registerFails = false
    private var _unregisterFails = false
    private var _registerCount = 0
    private var _unregisterCount = 0
    private var _settingsCount = 0
    /// What a successful `register()` leaves behind — `.enabled`, or `.requiresApproval` when
    /// macOS wants the user to confirm in System Settings.
    private var _statusAfterRegister: LoginItemStatus = .enabled

    init(status: LoginItemStatus = .disabled) { _status = status }

    var registerCount: Int { lock.withLock { _registerCount } }
    var unregisterCount: Int { lock.withLock { _unregisterCount } }
    var settingsCount: Int { lock.withLock { _settingsCount } }

    func setRegisterFails(_ value: Bool) { lock.withLock { _registerFails = value } }
    func setUnregisterFails(_ value: Bool) { lock.withLock { _unregisterFails = value } }
    func setStatusAfterRegister(_ value: LoginItemStatus) { lock.withLock { _statusAfterRegister = value } }
    func setStatus(_ value: LoginItemStatus) { lock.withLock { _status = value } }

    func currentStatus() -> LoginItemStatus { lock.withLock { _status } }

    func register() async throws {
        try lock.withLock {
            _registerCount += 1
            if _registerFails { throw LoginItemError.registrationFailed }
            _status = _statusAfterRegister
        }
    }

    func unregister() async throws {
        try lock.withLock {
            _unregisterCount += 1
            if _unregisterFails { throw LoginItemError.unregistrationFailed }
            _status = .disabled
        }
    }

    func openSystemSettings() { lock.withLock { _settingsCount += 1 } }
}

// MARK: - Tests

@Suite("M32 — Open at Login")
@MainActor
struct LoginItemCoordinatorTests {

    @Test("Initial status is read from the system, not assumed")
    func initialStatus() {
        let off = LoginItemCoordinator(service: FakeLoginItemService(status: .disabled))
        #expect(off.isEnabled == false)
        #expect(off.status == .disabled)

        let on = LoginItemCoordinator(service: FakeLoginItemService(status: .enabled))
        #expect(on.isEnabled)
        #expect(on.lastError == nil)
    }

    @Test("Enabling registers the login item and reflects the system's answer")
    func enable() async {
        let service = FakeLoginItemService(status: .disabled)
        let coordinator = LoginItemCoordinator(service: service)

        await coordinator.setEnabled(true)

        #expect(service.registerCount == 1)
        #expect(coordinator.status == .enabled)
        #expect(coordinator.isEnabled)
        #expect(coordinator.lastError == nil)
        #expect(coordinator.isChanging == false)
    }

    @Test("Disabling unregisters the login item")
    func disable() async {
        let service = FakeLoginItemService(status: .enabled)
        let coordinator = LoginItemCoordinator(service: service)

        await coordinator.setEnabled(false)

        #expect(service.unregisterCount == 1)
        #expect(coordinator.status == .disabled)
        #expect(coordinator.isEnabled == false)
        #expect(coordinator.lastError == nil)
    }

    @Test("A refused registration leaves the toggle OFF and states why")
    func registrationFailure() async {
        let service = FakeLoginItemService(status: .disabled)
        service.setRegisterFails(true)
        let coordinator = LoginItemCoordinator(service: service)

        await coordinator.setEnabled(true)

        #expect(coordinator.isEnabled == false, "a failed registration must never read as on")
        #expect(coordinator.lastError == .registrationFailed)
        #expect(coordinator.lastError?.errorDescription?.isEmpty == false)
        #expect(coordinator.lastError?.recoverySuggestion?.isEmpty == false)
    }

    @Test("A refused removal leaves the toggle ON and states why")
    func unregistrationFailure() async {
        let service = FakeLoginItemService(status: .enabled)
        service.setUnregisterFails(true)
        let coordinator = LoginItemCoordinator(service: service)

        await coordinator.setEnabled(false)

        #expect(coordinator.isEnabled, "the login item is still registered, so the switch stays on")
        #expect(coordinator.lastError == .unregistrationFailed)
    }

    @Test("A registration awaiting the user's approval does not read as enabled")
    func requiresApproval() async {
        let service = FakeLoginItemService(status: .disabled)
        service.setStatusAfterRegister(.requiresApproval)
        let coordinator = LoginItemCoordinator(service: service)

        await coordinator.setEnabled(true)

        #expect(coordinator.status == .requiresApproval)
        #expect(coordinator.isEnabled == false,
                "it will not launch until approved, so it must not claim success")
        #expect(coordinator.lastError == .requiresApproval)
        #expect(coordinator.lastError?.suggestsSystemSettings == true)
    }

    @Test("Refreshing re-reads the system, picking up a change made in System Settings")
    func refresh() {
        let service = FakeLoginItemService(status: .disabled)
        let coordinator = LoginItemCoordinator(service: service)
        #expect(coordinator.isEnabled == false)

        // The user turned it on in System Settings › Login Items while the app was running.
        service.setStatus(.enabled)
        coordinator.refresh()

        #expect(coordinator.isEnabled)
    }

    @Test("Setting the value it already has does nothing at all")
    func noRedundantWork() async {
        let service = FakeLoginItemService(status: .enabled)
        let coordinator = LoginItemCoordinator(service: service)

        await coordinator.setEnabled(true)

        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)
    }

    @Test("A failure is not retried in a loop — one attempt per user action")
    func noRetryLoop() async {
        let service = FakeLoginItemService(status: .disabled)
        service.setRegisterFails(true)
        let coordinator = LoginItemCoordinator(service: service)

        await coordinator.setEnabled(true)
        #expect(service.registerCount == 1)

        // The user tries again: exactly one more attempt, never an automatic retry.
        await coordinator.setEnabled(true)
        #expect(service.registerCount == 2)
    }

    @Test("Trying again clears the previous error before reporting a new outcome")
    func errorIsCleared() async {
        let service = FakeLoginItemService(status: .disabled)
        service.setRegisterFails(true)
        let coordinator = LoginItemCoordinator(service: service)
        await coordinator.setEnabled(true)
        #expect(coordinator.lastError == .registrationFailed)

        service.setRegisterFails(false)
        await coordinator.setEnabled(true)

        #expect(coordinator.lastError == nil)
        #expect(coordinator.isEnabled)
    }

    @Test("An unavailable service reports itself unavailable rather than pretending to work")
    func unavailableService() async {
        let coordinator = LoginItemCoordinator(service: UnavailableLoginItemService())

        #expect(coordinator.status == .unavailable)
        #expect(coordinator.isAvailable == false)
        #expect(coordinator.isEnabled == false)

        await coordinator.setEnabled(true)

        #expect(coordinator.isEnabled == false)
        #expect(coordinator.lastError == .unavailable)
        #expect(coordinator.lastError?.suggestsSystemSettings == false)
    }

    @Test("The approval remedy opens System Settings rather than retrying")
    func opensSystemSettings() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let coordinator = LoginItemCoordinator(service: service)
        coordinator.openSystemSettings()
        #expect(service.settingsCount == 1)
    }

    @Test("Every status maps to an unambiguous on/off answer")
    func statusMapping() {
        #expect(LoginItemStatus.enabled.isEnabled)
        #expect(LoginItemStatus.disabled.isEnabled == false)
        #expect(LoginItemStatus.requiresApproval.isEnabled == false)
        #expect(LoginItemStatus.unavailable.isEnabled == false)
    }

    @Test("Every failure states what happened and what to do about it")
    func errorsAreComplete() {
        for error in [LoginItemError.registrationFailed, .unregistrationFailed,
                      .requiresApproval, .unavailable] {
            #expect(error.errorDescription?.isEmpty == false, "\(error) has no description")
            #expect(error.recoverySuggestion?.isEmpty == false, "\(error) has no remedy")
        }
    }
}
