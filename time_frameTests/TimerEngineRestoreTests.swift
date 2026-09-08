//
//  TimerEngineRestoreTests.swift
//  time_frameTests
//
//  The pure-value restoration seam on TimerEngine (ADR-012/014). No SwiftData.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Timer engine restoration")
struct TimerEngineRestoreTests {

    @Test("Restoring a running snapshot rebuilds the running interval")
    func restoreRunning() {
        let clock = MockTimeSource()
        let now = clock.now()
        let engine = makeEngine(makeConfig(focus: 100, short: 50, long: 150), clock: clock)

        engine.restore(from: TimerEngineSnapshot(
            state: .running,
            currentIndex: 0,
            completedIntervals: [],
            intervalStartDate: now,
            intervalEndDate: now.addingTimeInterval(60),
            remainingWhenPaused: nil
        ))

        #expect(engine.state == .running)
        #expect(engine.currentIndex == 0)
        expectClose(engine.remaining, 60)
    }

    @Test("Restoring a paused snapshot freezes the remaining time")
    func restorePaused() {
        let clock = MockTimeSource()
        let now = clock.now()
        let engine = makeEngine(makeConfig(focus: 100), clock: clock)

        engine.restore(from: TimerEngineSnapshot(
            state: .paused,
            currentIndex: 0,
            completedIntervals: [],
            intervalStartDate: now,
            intervalEndDate: nil,
            remainingWhenPaused: 42
        ))

        #expect(engine.state == .paused)
        expectClose(engine.remaining, 42)
        clock.advance(by: 500) // paused time must not elapse
        expectClose(engine.remaining, 42)
    }

    @Test("Restore is ignored unless the engine is idle")
    func restoreIgnoredWhenActive() {
        let clock = MockTimeSource()
        let now = clock.now()
        let engine = makeEngine(makeConfig(focus: 100), clock: clock)
        engine.start()

        engine.restore(from: TimerEngineSnapshot(
            state: .paused,
            currentIndex: 0,
            completedIntervals: [],
            intervalStartDate: now,
            intervalEndDate: nil,
            remainingWhenPaused: 5
        ))

        #expect(engine.state == .running) // unchanged
    }

    @Test("Restoring then synchronizing fast-forwards through elapsed intervals")
    func restoreThenSynchronize() {
        let clock = MockTimeSource()
        let now = clock.now()
        let engine = makeEngine(makeConfig(focus: 100, short: 50, long: 150), clock: clock)

        engine.restore(from: TimerEngineSnapshot(
            state: .running,
            currentIndex: 0,
            completedIntervals: [],
            intervalStartDate: now,
            intervalEndDate: now.addingTimeInterval(10),
            remainingWhenPaused: nil
        ))
        clock.advance(by: 20) // past the current interval's end
        engine.synchronize()

        #expect(engine.currentIndex == 1)
        #expect(engine.state == .running)
        #expect(engine.completedIntervals.count == 1)
        #expect(engine.completedIntervals.first?.outcome == .completed)
    }

    @Test("Restore preserves completed-interval history")
    func restorePreservesHistory() {
        let clock = MockTimeSource()
        let now = clock.now()
        let engine = makeEngine(makeConfig(focus: 100, short: 50, long: 150), clock: clock)
        let record = IntervalRecord(
            index: 0,
            phase: .focus,
            plannedDuration: 100,
            startedAt: now,
            endedAt: now.addingTimeInterval(100),
            outcome: .completed
        )

        engine.restore(from: TimerEngineSnapshot(
            state: .running,
            currentIndex: 1,
            completedIntervals: [record],
            intervalStartDate: now.addingTimeInterval(100),
            intervalEndDate: now.addingTimeInterval(150),
            remainingWhenPaused: nil
        ))

        #expect(engine.currentIndex == 1)
        #expect(engine.completedIntervals == [record])
    }
}
