//
//  ControlCenterRoutingTests.swift
//  time_frameTests (Milestone 22)
//
//  The Control Center controls are a command surface over the ONE timer. These tests drive the SAME
//  shared router the widget/Live-Activity controls use (`WidgetControlRouting.makeActions` →
//  `WidgetControlActions` → `AppIntentSessionActions` → `SessionCoordinator`) and prove:
//
//   • the adaptive primary control resolves and performs the contextually correct action on the one
//     authoritative coordinator (Parts 2–4);
//   • every control action refreshes the widget projection — including `restart`, which emits no
//     lifecycle event and relies on the router's explicit refresh (Part 10);
//   • actions fail safely when there is no session / no router, never crashing or corrupting the
//     timer (Parts 4 & 7);
//   • rapid repeated commands leave the timer in a valid state with no duplicate session (Part 8).
//
//  There is exactly ONE router and ONE mutation seam: the primary resolver reuses the same
//  `perform` path as the explicit-action handler (ADR-090). No second timer, no second store.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Control Center — mutation seam & primary resolution")
@MainActor
struct ControlCenterMutationSeamTests {

    private func router(_ rig: AppIntentRig, refreshed: @escaping @MainActor () -> Void = {}) -> WidgetControlActions {
        WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: refreshed)
    }

    @Test("Primary from idle starts a session on the one coordinator")
    func primaryStarts() throws {
        let rig = try makeAppIntentRig()
        let r = router(rig)
        #expect(rig.coordinator.engine.state == .idle)
        _ = try r.performPrimary()
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("Primary toggles pause ⇄ resume on a running focus interval")
    func primaryPauseResume() throws {
        let rig = try makeAppIntentRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let r = router(rig)

        _ = try r.performPrimary()               // focus running → pause
        #expect(rig.coordinator.engine.state == .paused)
        _ = try r.performPrimary()               // paused → resume
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("The primary resolver reuses the same seam as an explicit action (identical effect)")
    func primaryMatchesExplicit() throws {
        let rig = try makeAppIntentRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let r = router(rig)
        // Explicit pause and primary pause reach the same coordinator state.
        _ = try r.perform(.pause)
        #expect(rig.coordinator.engine.state == .paused)
        _ = try r.perform(.resume)
        _ = try r.performPrimary()               // running focus → pause again
        #expect(rig.coordinator.engine.state == .paused)
    }

    @Test("The router surfaces the app's confirmation vocabulary (no duplicated phrasing)")
    func reusesDialog() throws {
        let rig = try makeAppIntentRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let r = router(rig)
        #expect(try r.perform(.pause).confirmation == AppIntentDialogText.paused)
    }
}

@Suite("Control Center — projection freshness (Part 10)")
@MainActor
struct ControlCenterProjectionTests {

    /// A router wired to a REAL projection writer over a volatile store, so we can read back what a
    /// Control Center action would publish to the widget surface.
    private func wired(_ rig: AppIntentRig) -> (WidgetControlActions, WidgetProjectionStore) {
        let store = WidgetProjectionStore(defaults: UserDefaults(suiteName: "cc.tests.\(UUID().uuidString)")!)
        let writer = WidgetProjectionWriter(coordinator: rig.coordinator, store: store, reload: {})
        let router = WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: { writer.update() })
        return (router, store)
    }

    @Test("start / pause / resume / stop each refresh the projection")
    func lifecycleRefreshes() throws {
        let rig = try makeAppIntentRig()
        let (router, store) = wired(rig)

        _ = try router.perform(.start)
        #expect(store.read()?.state == .running)
        _ = try router.perform(.pause)
        #expect(store.read()?.state == .paused)
        _ = try router.perform(.resume)
        #expect(store.read()?.state == .running)
        _ = try router.perform(.stop)
        #expect(store.read()?.state == .idle)   // stopped → idle projection (history preserved)
    }

    @Test("restart refreshes the projection even though it emits no lifecycle event")
    func restartRefreshes() throws {
        let rig = try makeAppIntentRig()
        let (router, store) = wired(rig)
        _ = try router.perform(.start)
        // Clear the store, then restart: only the router's explicit refresh can repopulate it.
        store.clear()
        #expect(store.read() == nil)
        _ = try router.perform(.restart)
        #expect(store.read()?.state == .running)
    }

    @Test("The adaptive primary action also refreshes the projection")
    func primaryRefreshes() throws {
        let rig = try makeAppIntentRig()
        let (router, store) = wired(rig)
        _ = try router.performPrimary()          // start
        #expect(store.read()?.state == .running)
        _ = try router.performPrimary()          // pause
        #expect(store.read()?.state == .paused)
    }
}

@Suite("Control Center — failure isolation (Part 7)")
@MainActor
struct ControlCenterFailureIsolationTests {

    @Test("The inert router fails safely — no handler, no crash")
    func unavailableRouterFailsSafely() {
        #expect(throws: WidgetControlError.unavailable) {
            _ = try WidgetControlActions.unavailable.perform(.pause)
        }
        #expect(throws: WidgetControlError.unavailable) {
            _ = try WidgetControlActions.unavailable.performPrimary()
        }
    }

    @Test("An action with no active session throws, and the timer is untouched")
    func noSessionFailsSafely() throws {
        let rig = try makeAppIntentRig()
        let router = WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: {})
        #expect(throws: TimeFrameIntentError.self) { _ = try router.perform(.pause) }
        #expect(throws: TimeFrameIntentError.self) { _ = try router.perform(.stop) }
        // The engine never left idle — a failed control can never corrupt the timer.
        #expect(rig.coordinator.engine.state == .idle)
    }

    @Test("A failing control action never resurrects or duplicates a session")
    func failedActionKeepsOneSession() throws {
        let rig = try makeAppIntentRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let id = rig.coordinator.activeSession?.id
        let router = WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: {})
        // Starting again must fail (already running) and leave the SAME session running.
        #expect(throws: TimeFrameIntentError.self) { _ = try router.perform(.start) }
        #expect(rig.coordinator.activeSession?.id == id)
        #expect(rig.coordinator.engine.state == .running)
    }
}

@Suite("Control Center — rapid repeated commands (Part 8)")
@MainActor
struct ControlCenterConcurrencyTests {

    private func router(_ rig: AppIntentRig) -> WidgetControlActions {
        WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: {})
    }

    @Test("Pause → Pause leaves a single paused session (idempotent)")
    func pausePause() throws {
        let rig = try makeAppIntentRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let r = router(rig)
        _ = try r.perform(.pause)
        _ = try r.perform(.pause)                // second pause is a safe no-op
        #expect(rig.coordinator.engine.state == .paused)
    }

    @Test("Resume → Resume leaves a single running session")
    func resumeResume() throws {
        let rig = try makeAppIntentRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let r = router(rig)
        _ = try r.perform(.pause)
        _ = try r.perform(.resume)
        _ = try r.perform(.resume)               // second resume is a safe no-op
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("Start → Start never creates a second session")
    func startStart() throws {
        let rig = try makeAppIntentRig()
        let r = router(rig)
        _ = try r.perform(.start)
        let id = rig.coordinator.activeSession?.id
        #expect(throws: TimeFrameIntentError.self) { _ = try r.perform(.start) }
        #expect(rig.coordinator.activeSession?.id == id)
    }

    @Test("Stop → Stop ends the session once; the second is a safe error")
    func stopStop() throws {
        let rig = try makeAppIntentRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let r = router(rig)
        _ = try r.perform(.stop)
        #expect(!rig.coordinator.engine.state.isActive)
        #expect(throws: TimeFrameIntentError.self) { _ = try r.perform(.stop) }
        #expect(!rig.coordinator.engine.state.isActive)
    }

    @Test("Many rapid primary taps keep the timer in a valid state")
    func rapidPrimary() throws {
        let rig = try makeAppIntentRig()
        let r = router(rig)
        // start, pause, resume, pause, resume, ... — always a valid transition, never a crash.
        for _ in 0..<12 { _ = try? r.performPrimary() }
        let valid: Set<TimerState> = [.idle, .running, .paused, .completed, .cancelled]
        #expect(valid.contains(rig.coordinator.engine.state))
    }
}

@Suite("Control Center — performance (Part 15)")
struct ControlCenterPerformanceTests {

    @Test("Deriving control availability for many states is cheap")
    func availabilityIsCheap() {
        let states = ControlCenterSessionState.allCases
        var sink = 0
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<20_000 {
                for state in states {
                    sink += ControlCenterControlSet.controls(for: state).count
                    sink += ControlCenterControlSet.primaryAction(for: state) == .start ? 1 : 0
                }
            }
        }
        #expect(sink > 0)
        // Generous, machine-independent ceiling — this is pure array/enum work.
        #expect(elapsed < .seconds(2))
    }
}
