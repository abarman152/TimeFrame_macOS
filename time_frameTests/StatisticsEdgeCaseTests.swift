//
//  StatisticsEdgeCaseTests.swift
//  time_frameTests
//
//  Boundary behaviour for the statistics engine: empty history, zero-duration and
//  incomplete intervals, sessions that cross midnight, and a large synthetic dataset
//  (correctness plus a coarse guard against accidental non-linear cost).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Statistics edge cases")
struct StatisticsEdgeCaseTests {

    @Test("Empty history produces an empty snapshot")
    func emptyHistory() {
        let cal = statCalendar()
        let snapshot = StatisticsAggregator.aggregate(sessions: [], range: allTimeRange, calendar: cal)
        #expect(snapshot.isEmpty)
        #expect(snapshot.startedSessions == 0)
        #expect(snapshot.focusDuration == 0)
        #expect(snapshot.completionRate == nil)
        #expect(snapshot.averageFocusInterval == nil)
        #expect(snapshot.mostProductiveDay == nil)
        #expect(snapshot.configurations.isEmpty)
    }

    @Test("A completed zero-duration focus interval counts as an interval with no time")
    func zeroDurationInterval() {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, calendar: cal)
        let session = statSession(startedAt: day, intervals: [statFocus(0, endedAt: day)])
        let snapshot = StatisticsAggregator.aggregate(sessions: [session], range: allTimeRange, calendar: cal)
        #expect(snapshot.completedFocusIntervals == 1)
        #expect(snapshot.focusDuration == 0)
        #expect(snapshot.averageFocusInterval == 0)
    }

    @Test("A session crossing midnight banks each interval on the day it ended")
    func crossingMidnight() {
        let cal = statCalendar()
        // Focus completes at 23:50 on the 13th; a later focus completes at 00:20 on the 14th.
        let beforeMidnight = statDate(2026, 8, 13, 23, 50, calendar: cal)
        let afterMidnight = statDate(2026, 8, 14, 0, 20, calendar: cal)
        let session = statSession(
            startedAt: statDate(2026, 8, 13, 23, 30, calendar: cal),
            endedAt: afterMidnight,
            intervals: [
                statFocus(20 * 60, endedAt: beforeMidnight),
                statFocus(20 * 60, endedAt: afterMidnight)
            ])
        let range = StatisticsPeriod.custom(
            start: statDate(2026, 8, 13, calendar: cal),
            end: statDate(2026, 8, 14, calendar: cal)).range(calendar: cal)
        let snapshot = StatisticsAggregator.aggregate(sessions: [session], range: range, calendar: cal)
        #expect(snapshot.daily.count == 2)
        #expect(snapshot.daily[0].focusDuration == 20 * 60) // the 13th
        #expect(snapshot.daily[1].focusDuration == 20 * 60) // the 14th
        // The session itself is attributed (for the "started" count) to its start day, the 13th.
        #expect(snapshot.startedSessions == 1)
    }

    @Test("A session started outside the range still contributes intervals that end inside it")
    func intervalInRangeFromSessionOutside() {
        let cal = statCalendar()
        let startedBefore = statDate(2026, 8, 13, 23, 40, calendar: cal)
        let endedInside = statDate(2026, 8, 14, 0, 10, calendar: cal)
        let session = statSession(startedAt: startedBefore, endedAt: endedInside,
                                  intervals: [statFocus(30 * 60, endedAt: endedInside)])
        let today = StatisticsPeriod.today.range(reference: statDate(2026, 8, 14, 12, calendar: cal), calendar: cal)
        let snapshot = StatisticsAggregator.aggregate(sessions: [session], range: today, calendar: cal)
        // Interval-level focus counts (ended today), even though the session started yesterday.
        #expect(snapshot.focusDuration == 30 * 60)
        // But the session's *start* was yesterday, so it is not a "started today" session.
        #expect(snapshot.startedSessions == 0)
    }

    @Test("A large synthetic dataset aggregates correctly and quickly")
    func largeDataset() {
        let cal = statCalendar()
        // 1,000 sessions across ~90 days, 5 completed focus intervals each (5,000 intervals).
        var sessions: [SessionStatInput] = []
        sessions.reserveCapacity(1_000)
        let base = statDate(2026, 6, 1, 9, 0, calendar: cal)
        for i in 0..<1_000 {
            let day = cal.date(byAdding: .day, value: i % 90, to: base)!
            let intervals = (0..<5).map { _ in statFocus(20 * 60, endedAt: day) }
            sessions.append(statSession(startedAt: day, intervals: intervals))
        }
        let range = StatisticsPeriod.custom(
            start: base, end: cal.date(byAdding: .day, value: 89, to: base)!).range(calendar: cal)

        let clock = ContinuousClock()
        let start = clock.now
        let snapshot = StatisticsAggregator.aggregate(sessions: sessions, range: range, calendar: cal)
        let elapsed = clock.now - start

        #expect(snapshot.completedFocusIntervals == 5_000)
        #expect(snapshot.focusDuration == 5_000 * 20 * 60)
        #expect(snapshot.completedSessions == 1_000)
        #expect(snapshot.daily.count == 90)
        // Generous ceiling — this is a guard against accidental O(n²)/repeated work, not a benchmark.
        #expect(elapsed < .seconds(1))
    }
}
