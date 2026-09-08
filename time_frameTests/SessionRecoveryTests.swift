//
//  SessionRecoveryTests.swift
//  time_frameTests
//
//  App-relaunch and sleep/wake recovery (ADR-014). A "relaunch" is modelled as a
//  second coordinator restoring from the same store the first one persisted to.
//  Fully deterministic via the mock clock — no real time elapses.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Session recovery")
struct SessionRecoveryTests {

    /// Recovery 1 — a running session is restored and continues running.
    @Test("A running session is restored across relaunch")
    func restoreRunning() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container) // focus 10
        let clockA = MockTimeSource()
        let coordA = makeCoordinator(container, clock: clockA)

        let started = try #require(try coordA.startSession(configuration: config))
        clockA.advance(by: 3)

        // Relaunch at the same wall-clock instant.
        let clockB = MockTimeSource()
        clockB.set(to: clockA.now())
        let coordB = makeCoordinator(container, clock: clockB)

        let restored = try coordB.recover()

        #expect(restored)
        #expect(coordB.engine.state == .running)
        #expect(coordB.engine.currentIndex == 0)
        expectClose(coordB.engine.remaining, 7) // 10 − 3
        #expect(coordB.activeSession?.id == started.id)
        #expect(coordB.activeSession?.status == .running)
        #expect(try makeSessionRepository(container).allSessions().count == 1) // no duplicate session
    }

    /// Recovery 2 — a session whose whole plan elapsed while away is reconciled
    /// to completed.
    @Test("A session that fully elapsed while away is reconciled to completed")
    func reconcileToCompleted() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, total: 1) // [focus 10, short 5]
        let clockA = MockTimeSource()
        let coordA = makeCoordinator(container, clock: clockA)
        _ = try coordA.startSession(configuration: config)

        let clockB = MockTimeSource()
        clockB.set(to: clockA.now().addingTimeInterval(100)) // long absence
        let coordB = makeCoordinator(container, clock: clockB)

        let restored = try coordB.recover()

        #expect(restored == false) // completed is not active
        #expect(coordB.engine.state == .completed)
        #expect(coordB.activeSession?.status == .completed)
        let ordered = try #require(coordB.activeSession?.orderedIntervals)
        #expect(ordered.count == 2)
        #expect(ordered.allSatisfy { $0.status == .completed })
    }

    /// Recovery 3 / sleep-wake — many intervals elapse during a single gap and
    /// all advance correctly, without duplicate intervals.
    @Test("Multiple intervals elapsed while away all transition correctly")
    func multipleIntervalsElapsed() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container) // 8 intervals: F10,S5,F10,S5,F10,S5,F10,L15
        let clockA = MockTimeSource()
        let coordA = makeCoordinator(container, clock: clockA)
        _ = try coordA.startSession(configuration: config)

        // Boundaries: F10[0-10] S5[10-15] F10[15-25] S5[25-30] F10[30-40]...
        let clockB = MockTimeSource()
        clockB.set(to: clockA.now().addingTimeInterval(32)) // 2s into interval index 4
        let coordB = makeCoordinator(container, clock: clockB)

        let restored = try coordB.recover()

        #expect(restored)
        #expect(coordB.engine.currentIndex == 4)
        #expect(coordB.engine.state == .running)
        expectClose(coordB.engine.remaining, 8) // 10 − 2
        let ordered = try #require(coordB.activeSession?.orderedIntervals)
        #expect(ordered.count == 8) // no duplicates
        #expect(ordered.prefix(4).allSatisfy { $0.status == .completed })
        #expect(ordered[4].status == .running)
    }

    /// Recovery 4 — a paused session stays paused and does not lose time.
    @Test("A paused session is restored paused with its remaining intact")
    func restorePaused() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container) // focus 10
        let clockA = MockTimeSource()
        let coordA = makeCoordinator(container, clock: clockA)
        _ = try coordA.startSession(configuration: config)
        clockA.advance(by: 4)
        try coordA.pause() // remaining 6, frozen

        let clockB = MockTimeSource()
        clockB.set(to: clockA.now().addingTimeInterval(1000)) // long absence must not matter
        let coordB = makeCoordinator(container, clock: clockB)

        let restored = try coordB.recover()

        #expect(restored) // paused is active
        #expect(coordB.engine.state == .paused)
        expectClose(coordB.engine.remaining, 6)
        clockB.advance(by: 500)
        expectClose(coordB.engine.remaining, 6) // still frozen
        #expect(coordB.activeSession?.status == .paused)
    }

    /// A running session with inconsistent anchors cannot be trusted and is
    /// marked interrupted rather than restored.
    @Test("An inconsistent running session is marked interrupted, not restored")
    func inconsistentBecomesInterrupted() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let context = container.mainContext

        // Craft a "running" session whose current interval has no target end.
        let now = Date(timeIntervalSince1970: 2_000_000)
        let session = FocusSession(taskName: "broken", configuration: config, status: .running, startedAt: now)
        session.currentIntervalIndex = 0
        let interval = SessionInterval(phase: .focus, plannedDuration: 10, order: 0)
        interval.status = .running
        interval.startedAt = now
        interval.targetEndAt = nil // corruption
        session.intervals.append(interval)
        context.insert(session)
        try context.save()

        let coordB = makeCoordinator(container, clock: MockTimeSource())
        let restored = try coordB.recover()

        #expect(restored == false)
        #expect(session.status == .interrupted)
        #expect(session.endedAt != nil)
    }

    /// With nothing recoverable in the store, recovery is a no-op.
    @Test("Recovery is a no-op when there is no active session")
    func nothingToRecover() throws {
        let container = try makeInMemoryContainer()
        _ = try insertConfiguration(container)
        let coordB = makeCoordinator(container, clock: MockTimeSource())
        #expect(try coordB.recover() == false)
        #expect(coordB.activeSession == nil)
        #expect(coordB.engine.state == .idle)
    }

    /// Only one session can ever be restored: extra "active" sessions are
    /// defensively marked interrupted.
    @Test("Multiple stale active sessions collapse to a single recovery")
    func onlyOneRecovered() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let context = container.mainContext

        let older = FocusSession(taskName: "older", configuration: config, status: .running,
                                 startedAt: Date(timeIntervalSince1970: 1_000))
        let newer = FocusSession(taskName: "newer", configuration: config, status: .running,
                                 startedAt: Date(timeIntervalSince1970: 2_000))
        for session in [older, newer] {
            session.currentIntervalIndex = 0
            let interval = SessionInterval(phase: .focus, plannedDuration: 10, order: 0)
            interval.status = .running
            interval.startedAt = session.startedAt
            interval.targetEndAt = session.startedAt?.addingTimeInterval(10)
            session.intervals.append(interval)
            context.insert(session)
        }
        try context.save()

        let clock = MockTimeSource()
        clock.set(to: Date(timeIntervalSince1970: 2_003)) // 3s into the newer session
        let coordB = makeCoordinator(container, clock: clock)
        let restored = try coordB.recover()

        #expect(restored)
        #expect(coordB.activeSession?.taskName == "newer")
        #expect(older.status == .interrupted)
    }
}
