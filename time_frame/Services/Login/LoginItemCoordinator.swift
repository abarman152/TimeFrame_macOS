//
//  LoginItemCoordinator.swift
//  time_frame (Milestone 32)
//
//  The observable adapter Settings binds to (ADR-112).
//
//  Its single rule: **the system is the source of truth**. `isEnabled` is derived from
//  `LoginItemStatus`, which is read back from macOS after every change, so a registration
//  that failed leaves the toggle off and a registration that needs approval does not read as
//  on. Nothing about the login item is stored in `UserDefaults` — there is no preference to
//  drift out of step with reality (§2/§4).
//
//  It owns no timer, no store, and no window. A login-item failure is reported and nothing
//  else happens: like Calendar and Notifications, this integration can never disturb a
//  running session.
//

import Foundation
import Observation

/// Observable state for the "Open at Login" setting.
@MainActor
@Observable
final class LoginItemCoordinator {

    @ObservationIgnored private let service: any LoginItemManaging

    /// What macOS currently reports. Refreshed at launch, when Settings appears, and after
    /// every change the user makes.
    private(set) var status: LoginItemStatus

    /// The last failure, or `nil`. Cleared when the user tries again.
    private(set) var lastError: LoginItemError?

    /// True while a registration change is in flight. The toggle disables itself, which is
    /// what keeps a fast double-click from turning into a retry loop (§3).
    private(set) var isChanging = false

    init(service: any LoginItemManaging) {
        self.service = service
        self.status = service.currentStatus()
    }

    /// Whether the toggle reads as on. Derived from the system status — never from a stored
    /// preference, and never optimistically set before the system agrees.
    var isEnabled: Bool { status.isEnabled }

    /// Whether the setting can be changed at all on this system/build.
    var isAvailable: Bool { status != .unavailable }

    /// Re-reads the system's answer. Cheap and side-effect free; safe to call on appear.
    func refresh() {
        status = service.currentStatus()
        if status == .requiresApproval, lastError == nil {
            lastError = .requiresApproval
        }
    }

    /// Registers or removes the login item, then refreshes from the system.
    ///
    /// One attempt per user action. On failure the error is recorded and the status is read
    /// back, so the UI shows what is actually true rather than what was asked for.
    func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        guard enabled != isEnabled else { return }
        isChanging = true
        lastError = nil
        defer { isChanging = false }

        do {
            if enabled {
                try await service.register()
            } else {
                try await service.unregister()
            }
        } catch let error as LoginItemError {
            lastError = error
        } catch {
            lastError = enabled ? .registrationFailed : .unregistrationFailed
        }

        // Whatever happened, the system's answer wins.
        status = service.currentStatus()
        if lastError == nil, status == .requiresApproval {
            lastError = .requiresApproval
        }
    }

    /// Opens System Settings at Login Items, for a registration awaiting approval.
    func openSystemSettings() {
        service.openSystemSettings()
    }

    /// Dismisses the current error without changing anything.
    func clearError() {
        lastError = nil
    }
}
