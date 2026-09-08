//
//  MainWindowPresentationTests.swift
//  time_frameTests (Milestone 32)
//
//  Time Frame has exactly ONE main window (ADR-111). These tests exercise the decision that
//  guarantees it, at the level where the decision is actually made.
//
//  `NSWindow` cannot be driven meaningfully in this test host, so the AppKit steps live behind
//  `MainWindowHosting` and the decision lives in the pure `MainWindowPolicy` (§26). The fake
//  host below models the four states a real window can be in — absent, on screen, minimized,
//  and hidden with the application — and records exactly which AppKit steps were asked for,
//  so "no duplicate window" is asserted as a fact about behaviour, not as a comment.
//
//  The last suite goes further and drives a REAL `SessionCoordinator`: focusing the window
//  repeatedly, from every entry point, must leave the running session bit-for-bit unchanged
//  (§18) — no restart, no second engine, no extra history.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

// MARK: - Fake host

/// Models the app's window states and records the AppKit steps the presenter asked for.
@MainActor
final class FakeMainWindowHost: MainWindowHosting {
    /// The window that currently exists, or `nil` when the user has closed it (or it has
    /// not been created yet).
    var window: MainWindowSnapshot?
    var applicationIsHidden = false
    /// Whether SwiftUI's opener has been captured, mirroring `AppKitMainWindowHost.hasOpener`.
    var hasOpener = true
    /// Whether a create lands immediately (SwiftUI presenting the window synchronously).
    var createLandsImmediately = false

    private(set) var unhideCount = 0
    private(set) var deminiaturizeCount = 0
    private(set) var focusCount = 0
    private(set) var createCount = 0

    func mainWindowSnapshot() -> MainWindowSnapshot? { window }

    func unhideApplication() {
        unhideCount += 1
        applicationIsHidden = false
        if window != nil { window?.isVisible = true }
    }

    func deminiaturizeMainWindow() {
        deminiaturizeCount += 1
        window?.isMiniaturized = false
        window?.isVisible = true
    }

    func focusMainWindow() {
        focusCount += 1
        window?.isVisible = true
    }

    @discardableResult
    func createMainWindow() -> Bool {
        createCount += 1
        if createLandsImmediately { window = .onScreen }
        return hasOpener
    }
}

@MainActor
private func makePresenter(_ host: FakeMainWindowHost) -> MainWindowPresenter {
    MainWindowPresenter(navigation: AppNavigation(), host: host)
}

// MARK: - The pure policy

@Suite("M32 — main window policy")
struct MainWindowPolicyTests {

    @Test("No window exists: the only branch that creates one")
    func createsWhenAbsent() {
        let action = MainWindowPolicy.action(for: nil, applicationIsHidden: false,
                                             creationIsPending: false)
        #expect(action == .createWindow)
        #expect(action.reusesExistingWindow == false)
    }

    @Test("An on-screen window is reused untouched")
    func reusesOnScreenWindow() {
        let action = MainWindowPolicy.action(for: .onScreen, applicationIsHidden: false,
                                             creationIsPending: false)
        #expect(action == .reuseExisting(unhideApplication: false, deminiaturize: false))
    }

    @Test("A minimized window is restored, never replaced")
    func restoresMiniaturizedWindow() {
        let action = MainWindowPolicy.action(for: .miniaturized, applicationIsHidden: false,
                                             creationIsPending: false)
        #expect(action == .reuseExisting(unhideApplication: false, deminiaturize: true))
    }

    @Test("A hidden application is unhidden, and its window still reused")
    func unhidesApplication() {
        let action = MainWindowPolicy.action(for: .offScreen, applicationIsHidden: true,
                                             creationIsPending: false)
        #expect(action == .reuseExisting(unhideApplication: true, deminiaturize: false))
    }

    @Test("An existing but off-screen window is shown rather than duplicated")
    func showsOffScreenWindow() {
        // The application does not report itself hidden, but the window is off screen. It
        // still exists, so it is still the window — a new one would be the duplicate.
        let action = MainWindowPolicy.action(for: .offScreen, applicationIsHidden: false,
                                             creationIsPending: false)
        #expect(action == .reuseExisting(unhideApplication: true, deminiaturize: false))
    }

    @Test("A minimized window while the app is hidden is both unhidden and restored")
    func hiddenAndMiniaturized() {
        let action = MainWindowPolicy.action(for: .miniaturized, applicationIsHidden: true,
                                             creationIsPending: false)
        #expect(action == .reuseExisting(unhideApplication: true, deminiaturize: true))
    }

    @Test("A second request while a creation is in flight creates nothing")
    func coalescesConcurrentCreation() {
        let action = MainWindowPolicy.action(for: nil, applicationIsHidden: false,
                                             creationIsPending: true)
        #expect(action == .coalesced)
    }

    @Test("A pending creation never suppresses reuse of a window that now exists")
    func pendingDoesNotBlockReuse() {
        let action = MainWindowPolicy.action(for: .onScreen, applicationIsHidden: false,
                                             creationIsPending: true)
        #expect(action.reusesExistingWindow)
    }
}

// MARK: - The presenter

@Suite("M32 — main window presenter")
@MainActor
struct MainWindowPresenterTests {

    @Test("1 — no window: open creates one")
    func createsWhenNoWindow() {
        let host = FakeMainWindowHost()
        host.window = nil
        let presenter = makePresenter(host)

        #expect(presenter.showMainWindow() == .createWindow)
        #expect(host.createCount == 1)
        #expect(host.focusCount == 0)
    }

    @Test("2/3 — an existing visible window is reused and focused, never recreated")
    func reusesAndFocuses() {
        let host = FakeMainWindowHost()
        host.window = .onScreen
        let presenter = makePresenter(host)

        #expect(presenter.showMainWindow().reusesExistingWindow)
        #expect(host.createCount == 0)
        #expect(host.focusCount == 1)
        #expect(host.deminiaturizeCount == 0)
        #expect(host.unhideCount == 0)
    }

    @Test("4 — a minimized window is unminimized and focused, with no second window")
    func restoresMiniaturized() {
        let host = FakeMainWindowHost()
        host.window = .miniaturized
        let presenter = makePresenter(host)

        presenter.showMainWindow()

        #expect(host.createCount == 0)
        #expect(host.deminiaturizeCount == 1)
        #expect(host.focusCount == 1)
        #expect(host.window == .onScreen)
    }

    @Test("5 — a hidden application is unhidden and its window shown")
    func showsHiddenWindow() {
        let host = FakeMainWindowHost()
        host.window = .offScreen
        host.applicationIsHidden = true
        let presenter = makePresenter(host)

        presenter.showMainWindow()

        #expect(host.createCount == 0)
        #expect(host.unhideCount == 1)
        #expect(host.focusCount == 1)
    }

    @Test("6 — a closed window is recreated on the next request")
    func recreatesAfterClose() {
        let host = FakeMainWindowHost()
        host.window = .onScreen
        let presenter = makePresenter(host)

        presenter.showMainWindow()
        #expect(host.createCount == 0)

        // The user closes the window: the host stops reporting one. Nothing stale is kept.
        host.window = nil
        presenter.mainWindowDidAppear()   // any pending create from before is long settled

        #expect(presenter.showMainWindow() == .createWindow)
        #expect(host.createCount == 1)
    }

    @Test("7 — repeated Open Time Frame never produces a second window")
    func repeatedOpenIsIdempotent() {
        let host = FakeMainWindowHost()
        host.window = .onScreen
        let presenter = makePresenter(host)

        for _ in 0..<8 { presenter.showMainWindow() }

        #expect(host.createCount == 0)
        #expect(host.focusCount == 8)
        #expect(host.window == .onScreen)
    }

    @Test("8 — repeated Dock reopen never produces a second window")
    func repeatedReopenIsIdempotent() {
        let host = FakeMainWindowHost()
        host.window = .miniaturized
        let presenter = makePresenter(host)

        // Four Dock clicks in a row on a minimized window.
        for _ in 0..<4 { presenter.showMainWindow() }

        #expect(host.createCount == 0)
        #expect(host.deminiaturizeCount == 1, "only the first click had anything to restore")
        #expect(host.focusCount == 4)
    }

    @Test("9 — menu bar open with no window creates exactly one, however many times it is asked")
    func stressedCreationCreatesOne() {
        let host = FakeMainWindowHost()
        host.window = nil
        let presenter = makePresenter(host)

        // The window-creation race (§28): four requests before the first create has landed.
        // Every request after the first must be coalesced, not a second window.
        #expect(presenter.showMainWindow() == .createWindow)
        #expect(presenter.showMainWindow() == .coalesced)
        #expect(presenter.showMainWindow() == .coalesced)
        #expect(presenter.showMainWindow() == .coalesced)

        #expect(host.createCount == 1)
    }

    @Test("A create that lands is reused by the next request rather than repeated")
    func creationThenReuse() {
        let host = FakeMainWindowHost()
        host.window = nil
        host.createLandsImmediately = true
        let presenter = makePresenter(host)

        #expect(presenter.showMainWindow() == .createWindow)
        #expect(presenter.showMainWindow().reusesExistingWindow)
        #expect(host.createCount == 1)
        #expect(host.focusCount == 1)
    }

    @Test("A window that registers clears the pending create, so later requests are not ignored")
    func registrationClearsPending() {
        let host = FakeMainWindowHost()
        host.window = nil
        let presenter = makePresenter(host)

        presenter.showMainWindow()          // create issued, pending
        host.window = .onScreen             // SwiftUI presented it
        presenter.mainWindowDidAppear()     // the accessor registered it

        #expect(presenter.showMainWindow().reusesExistingWindow)
        #expect(host.createCount == 1)
    }

    @Test("Opening a section routes through the shared navigation seam")
    func requestsSection() {
        let host = FakeMainWindowHost()
        host.window = .onScreen
        let presenter = makePresenter(host)

        presenter.showMainWindow(.settings)

        #expect(presenter.navigation.requestedSection == .settings)
        #expect(host.createCount == 0, "a section request must not open a second window")
    }

    @Test("Opening without a section leaves the user's current screen alone")
    func leavesNavigationAlone() {
        let host = FakeMainWindowHost()
        host.window = .onScreen
        let presenter = makePresenter(host)

        presenter.showMainWindow()

        #expect(presenter.navigation.requestedSection == nil,
                "\"Open Time Frame\" focuses the window; it does not reset the UI (§17)")
    }

    @Test("With no host attached the presenter reports create, so AppKit can handle the reopen")
    func unattachedFallsBack() {
        let presenter = MainWindowPresenter(navigation: AppNavigation())
        #expect(presenter.showMainWindow() == .createWindow)
    }
}

// MARK: - Focusing the window never touches the timer (§18)

@Suite("M32 — window focus is window behaviour only")
@MainActor
struct MainWindowTimerSafetyTests {

    @Test("Repeated Open Time Frame leaves a running session bit-for-bit unchanged")
    func runningSessionSurvivesRepeatedOpens() throws {
        let rig = try makeMenuBarRig(focus: 1500, short: 300)
        let session = try #require(try rig.coordinator.startSession(configuration: rig.config,
                                                                    taskName: "Deep work"))
        rig.clock.advance(by: 120)

        let sessionID = session.id
        let engineState = rig.coordinator.engine.state
        let phase = rig.coordinator.engine.currentPhase
        let remaining = rig.coordinator.engine.remaining
        let intervalCount = session.intervals.count

        let host = FakeMainWindowHost()
        host.window = .onScreen
        let presenter = makePresenter(host)

        // Dock click, menu bar open, gear menu, Quick Start empty state — all the same seam.
        presenter.showMainWindow()
        presenter.showMainWindow(.timer)
        presenter.showMainWindow(.history)
        presenter.showMainWindow()

        #expect(rig.coordinator.activeSession?.id == sessionID, "the session was replaced")
        #expect(rig.coordinator.engine.state == engineState)
        #expect(rig.coordinator.engine.currentPhase == phase)
        #expect(rig.coordinator.engine.remaining == remaining, "the countdown was disturbed")
        #expect(session.intervals.count == intervalCount, "history gained duplicate intervals")

        // And no second session was recorded.
        let sessions = try rig.container.mainContext.fetch(FetchDescriptor<FocusSession>())
        #expect(sessions.count == 1)
        _ = rig.container
    }

    @Test("Focusing the window while paused neither resumes nor restarts")
    func pausedSessionStaysPaused() throws {
        let rig = try makeMenuBarRig(focus: 1500, short: 300)
        _ = try rig.coordinator.startSession(configuration: rig.config, taskName: "Review")
        rig.clock.advance(by: 60)
        try rig.coordinator.pause()
        let remaining = rig.coordinator.engine.remaining

        let host = FakeMainWindowHost()
        host.window = .miniaturized
        let presenter = makePresenter(host)
        presenter.showMainWindow()
        rig.clock.advance(by: 300)

        #expect(rig.coordinator.engine.state == .paused)
        #expect(rig.coordinator.engine.remaining == remaining,
                "a paused session must not tick because a window was focused")
        _ = rig.container
    }
}
