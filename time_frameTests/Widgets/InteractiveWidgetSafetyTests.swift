//
//  InteractiveWidgetSafetyTests.swift
//  time_frameTests (Milestone 15)
//
//  Failure isolation, concurrency, and recovery for the interactive widget. Every path proves
//  the coordinator stays authoritative: an unavailable router, a stale/absent session, an
//  invalid transition, or a burst of repeated taps can never crash, corrupt the timer, or
//  resurrect an old session.
//

import Foundation
import Testing
@testable import time_frame

// MARK: - Failure isolation

@MainActor
@Suite("Interactive widget failure isolation")
struct InteractiveWidgetFailureTests {

    @Test("An unregistered router fails safely with a friendly 'unavailable' error")
    func unavailableRouter() throws {
        // The `.unavailable` default is what a widget-run intent resolves if the app router was
        // never registered in its process — it must fail safely, never trap.
        let router = WidgetControlActions.unavailable
        for action in WidgetControlAction.allCases {
            #expect(throws: WidgetControlError.unavailable) { try router.perform(action) }
        }
    }

    @Test("Controls on no active session report noActiveSession and create nothing")
    func controlsWhenIdle() throws {
        let rig = try makeInteractiveWidgetRig()
        for action in [WidgetControlAction.pause, .resume, .skip, .restart, .stop] {
            #expect(throws: TimeFrameIntentError.noActiveSession) { try rig.perform(action) }
        }
        #expect(rig.coordinator.activeSession == nil)
        #expect(rig.coordinator.engine.state == .idle)
        #expect(rig.projection?.state == .idle)
    }

    @Test("Start while already running reports sessionAlreadyRunning and does not restart")
    func doubleStart() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        let session = rig.coordinator.activeSession
        #expect(throws: TimeFrameIntentError.sessionAlreadyRunning) { try rig.perform(.start) }
        #expect(rig.coordinator.activeSession === session) // same session, not a second one
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("A stale action never resurrects a session that isn't there")
    func staleActionDoesNotResurrect() throws {
        let rig = try makeInteractiveWidgetRig()
        // Simulate a lagging widget whose last projection said 'running' while the app is idle.
        let stale = WidgetProjection(
            generatedAt: Date(), state: .running, phase: .focus,
            title: "Ghost", intervalStartedAt: Date(), intervalPlannedEndAt: Date().addingTimeInterval(600)
        )
        rig.store.write(stale)
        #expect(rig.projection?.state == .running)

        // Tapping Pause from that stale surface must fail safely, not invent a session.
        #expect(throws: TimeFrameIntentError.noActiveSession) { try rig.perform(.pause) }
        #expect(rig.coordinator.activeSession == nil)
        #expect(rig.coordinator.engine.state == .idle)
    }

    @Test("An invalid transition (resume while running) is a safe no-op, not corruption")
    func invalidTransitionIsNoOp() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        rig.clock.advance(by: 100)
        _ = try rig.perform(.resume) // already running — coordinator guards this as a no-op
        #expect(rig.coordinator.engine.state == .running)
        expectClose(rig.coordinator.engine.remaining, 500, tolerance: 1)
    }
}

// MARK: - Concurrency (rapid / repeated taps)

@MainActor
@Suite("Interactive widget concurrency")
struct InteractiveWidgetConcurrencyTests {

    @Test("Repeated Pause keeps the session paused exactly once")
    func repeatedPause() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        _ = try rig.perform(.pause)
        _ = try rig.perform(.pause) // second pause is a safe no-op
        _ = try rig.perform(.pause)
        #expect(rig.coordinator.engine.state == .paused)
        #expect(rig.projection?.state == .paused)
    }

    @Test("Repeated Resume keeps the session running")
    func repeatedResume() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        _ = try rig.perform(.pause)
        _ = try rig.perform(.resume)
        _ = try rig.perform(.resume) // no-op
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("Repeated Stop: the second is a safe noActiveSession, state stays cancelled")
    func repeatedStop() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        _ = try rig.perform(.stop)
        #expect(rig.coordinator.engine.state == .cancelled)
        #expect(throws: TimeFrameIntentError.noActiveSession) { try rig.perform(.stop) }
        #expect(rig.coordinator.engine.state == .cancelled)
    }

    @Test("Pause then Stop stops cleanly")
    func pauseThenStop() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        _ = try rig.perform(.pause)
        _ = try rig.perform(.stop)
        #expect(rig.coordinator.engine.state == .cancelled)
        #expect(rig.projection?.state == .idle)
    }

    @Test("Resume then Skip advances the interval")
    func resumeThenSkip() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600, short: 300, total: 4)
        try rig.perform(.start)
        _ = try rig.perform(.pause)
        _ = try rig.perform(.resume)
        _ = try rig.perform(.skip)
        #expect(rig.coordinator.engine.currentPhase == .shortBreak)
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("Skip then Stop leaves a cancelled run with preserved history")
    func skipThenStop() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600, short: 300, total: 4)
        try rig.perform(.start)
        let session = rig.coordinator.activeSession
        _ = try rig.perform(.skip)
        _ = try rig.perform(.stop)
        #expect(rig.coordinator.engine.state == .cancelled)
        #expect((session?.intervals.count ?? 0) >= 1)
    }
}

// MARK: - Recovery

@MainActor
@Suite("Interactive widget recovery")
struct InteractiveWidgetRecoveryTests {

    @Test("After completion, Start begins a genuinely new session")
    func startAfterCompletion() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600, short: 300, total: 1)
        try rig.perform(.start)
        let first = rig.coordinator.activeSession
        _ = try rig.perform(.skip); _ = try rig.perform(.skip) // complete
        #expect(rig.coordinator.engine.state == .completed)

        try rig.perform(.start)
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.coordinator.activeSession !== first) // a new session, not the old one
        #expect(rig.projection?.state == .running)
    }

    @Test("After Stop, Start begins a fresh session and the projection is running")
    func startAfterStop() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        _ = try rig.perform(.stop)
        #expect(rig.projection?.state == .idle)

        try rig.perform(.start)
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.projection?.state == .running)
    }

    @Test("A running session recovered from the store reflects into a running projection")
    func runningRecoveryProjection() throws {
        // Drive a running session, then rebuild the projection straight from the mapper (the
        // exact path a post-recovery `writer.update()` takes) and confirm it is coherent.
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        rig.clock.advance(by: 120)
        let projection = WidgetProjectionMapper.projection(from: rig.coordinator, now: rig.clock.now())
        #expect(projection.state == .running)
        #expect(projection.phase == .focus)
        #expect(projection.intervalPlannedEndAt != nil)
        #expect(WidgetControlSet.controls(for: projection.state, phase: projection.phase, compact: false) == [.pause, .skip, .stop])
    }

    @Test("A paused session maps to a paused projection with frozen remaining and paused controls")
    func pausedRecoveryProjection() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        rig.clock.advance(by: 150)
        _ = try rig.perform(.pause)
        let projection = WidgetProjectionMapper.projection(from: rig.coordinator, now: rig.clock.now())
        #expect(projection.state == .paused)
        #expect(projection.pausedRemainingSeconds != nil)
        #expect(WidgetControlSet.controls(for: .paused, phase: projection.phase, compact: false) == [.resume, .restart, .stop])
    }
}
