//
//  TimerBoundaryHardeningTests.swift
//  time_frameTests (Milestone 17)
//
//  Additional timer boundary & robustness coverage beyond `TimerEngineEdgeCaseTests`.
//  The engine is timestamp-authoritative, so these prove the properties that follow from
//  that: remaining is never negative (no NaN, no negative countdown) however far the clock
//  runs past an interval end; a backwards system-clock correction can never corrupt the
//  run; skip/stop right at a boundary behave; a very long interval computes correctly; and
//  a huge sleep/wake gap fast-forwards to completion without hanging.
//
//  No engine semantics are changed here — these lock in existing guarantees (§ADR-013/014).
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Timer boundary hardening")
struct TimerBoundaryHardeningTests {

    @Test("Remaining never goes negative, however far past the interval end the clock runs")
    func remainingNeverNegative() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, total: 1), clock: clock)
        engine.start()
        clock.advance(by: 9_999)          // far past the 10 s interval, no synchronize yet
        #expect(engine.remaining >= 0)
        #expect(engine.remaining == 0)
        #expect(engine.remaining.isNaN == false)
    }

    @Test("A backwards clock correction never corrupts the run and self-heals going forward")
    func backwardsClockDoesNotCorrupt() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 100, total: 1), clock: clock)
        let t0 = clock.now()
        engine.start()
        clock.advance(by: 40)
        expectClose(engine.remaining, 60)

        // System clock jumps backwards (e.g. an NTP correction) well before the start.
        clock.set(to: t0.addingTimeInterval(-30))
        #expect(engine.remaining >= 0)                 // never negative
        #expect(engine.state == .running)              // never corrupted

        // Moving forward past the (unchanged) target end still completes it.
        clock.set(to: t0.addingTimeInterval(1_000))
        engine.synchronize()
        #expect(engine.state == .completed)
    }

    @Test("Skip exactly at the boundary advances to the next interval")
    func skipAtBoundary() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, total: 2), clock: clock)
        engine.start()
        clock.advance(by: 10)              // right at the focus boundary
        engine.skip()
        // Skipping the focus records it and moves on; the run is not completed yet.
        #expect(engine.state == .running)
        #expect(engine.currentIndex == 1)
        #expect(engine.completedIntervals.last?.outcome == .skipped)
    }

    @Test("Stop exactly at the boundary cancels cleanly and preserves history")
    func stopAtBoundary() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, total: 1), clock: clock)
        engine.start()
        clock.advance(by: 10)
        engine.stop()
        #expect(engine.state == .cancelled)
        #expect(engine.completedIntervals.last?.outcome == .cancelled)
    }

    @Test("A very long (24h) interval computes remaining correctly and completes")
    func veryLongInterval() {
        let clock = MockTimeSource()
        let day: TimeInterval = 24 * 3_600
        let engine = makeEngine(makeConfig(focus: day, total: 1), clock: clock)
        engine.start()
        clock.advance(by: 3_600)           // one hour in
        expectClose(engine.remaining, day - 3_600)
        #expect(engine.remaining.isNaN == false)

        clock.advance(by: day)             // well past the end
        engine.synchronize()
        #expect(engine.state == .completed)
    }

    @Test("A huge sleep/wake gap fast-forwards through the whole plan without hanging")
    func hugeSleepGapCompletes() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, short: 5, long: 15, before: 4, total: 4), clock: clock)
        engine.start()
        // Ten years pass while asleep; a single synchronize must converge to completed.
        clock.advance(by: 10 * 365 * 24 * 3_600)
        engine.synchronize()
        #expect(engine.state == .completed)
        #expect(engine.remaining == 0)
    }
}

@Suite("Empty & safe state robustness")
struct EmptyStateRobustnessTests {

    @Test("Aggregating an empty history yields zeros and no NaN-prone ratios")
    func emptyHistoryIsSafe() {
        let range = StatisticsDateRange(start: .distantPast, end: .distantFuture)
        let snapshot = StatisticsAggregator.aggregate(sessions: [], range: range)

        #expect(snapshot.startedSessions == 0)
        #expect(snapshot.completedSessions == 0)
        #expect(snapshot.focusDuration == 0)
        #expect(snapshot.completedFocusIntervals == 0)
        #expect(snapshot.configurations.isEmpty)
        // Ratios divide by zero counts, so they must be nil, never NaN (§stats UI shows "—").
        #expect(snapshot.completionRate == nil)
        #expect(snapshot.averageFocusInterval == nil)
    }

    @Test("A session whose configuration was deleted still shows a safe, non-empty label")
    func deletedConfigurationHasSafeLabel() {
        // No frozen name and no live configuration (deleted): the label falls back, never
        // crashes or shows an empty string.
        let session = FocusSession(taskName: "Orphan")   // configuration nil, configurationName ""
        #expect(session.displayConfigurationName.isEmpty == false)
    }
}
