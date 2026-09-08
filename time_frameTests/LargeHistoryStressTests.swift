//
//  LargeHistoryStressTests.swift
//  time_frameTests (Milestone 17)
//
//  Deterministic large-history stress coverage. Two paths are exercised at realistic
//  scale: the pure `StatisticsAggregator` over thousands of sessions/intervals (exact,
//  reproducible totals — no clock, no store), and the real fetch+map+aggregate path
//  through `StatisticsRepository` over an in-memory store of 1,000 sessions.
//
//  Timing ceilings are deliberately generous and only guard against a pathological
//  regression (accidental O(n²), per-item I/O). Absolute times are machine-dependent, so
//  the thresholds are loose enough to never flake on a busy CI box; the value of these
//  tests is the exact correctness assertions, not the wall-clock number.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("Large-history stress — aggregator")
struct LargeHistoryAggregatorStressTests {

    /// A fixed reference instant so every generated timestamp is deterministic.
    private static let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
    private static let focusDuration: TimeInterval = 1_500   // 25 min
    private static let breakDuration: TimeInterval = 300     // 5 min
    private static let configNames = ["Deep Work", "Study", "Coding"]

    /// Builds `sessionCount` completed sessions, each with `focusPerSession` completed
    /// focus intervals and `breakPerSession` completed short breaks, all timestamped
    /// inside a 60-day window from `base` so a wide custom range captures every one.
    private func makeSessions(
        sessionCount: Int, focusPerSession: Int, breakPerSession: Int
    ) -> [SessionStatInput] {
        (0..<sessionCount).map { i in
            let day = Self.base.addingTimeInterval(TimeInterval(i % 30) * 86_400)
            let start = day.addingTimeInterval(9 * 3_600)     // 09:00 that day
            let configName = Self.configNames[i % Self.configNames.count]

            var intervals: [IntervalStatInput] = []
            var cursor = start
            for _ in 0..<focusPerSession {
                let end = cursor.addingTimeInterval(Self.focusDuration)
                intervals.append(IntervalStatInput(
                    phase: .focus, status: .completed, plannedDuration: Self.focusDuration,
                    startedAt: cursor, endedAt: end, configurationName: configName
                ))
                cursor = end
            }
            for _ in 0..<breakPerSession {
                let end = cursor.addingTimeInterval(Self.breakDuration)
                intervals.append(IntervalStatInput(
                    phase: .shortBreak, status: .completed, plannedDuration: Self.breakDuration,
                    startedAt: cursor, endedAt: end, configurationName: configName
                ))
                cursor = end
            }
            return SessionStatInput(
                id: UUID(), taskName: "Task \(i)", configurationName: configName,
                status: .completed, startedAt: start, endedAt: cursor, intervals: intervals
            )
        }
    }

    /// A custom range wide enough to contain every generated timestamp.
    private var wideRange: StatisticsDateRange {
        StatisticsDateRange(start: Self.base.addingTimeInterval(-86_400),
                            end: Self.base.addingTimeInterval(60 * 86_400))
    }

    @Test("1,000 sessions × 5 intervals (5,000 intervals) aggregate exactly and quickly")
    func fiveThousandIntervalsExact() {
        let sessions = makeSessions(sessionCount: 1_000, focusPerSession: 3, breakPerSession: 2)
        #expect(sessions.reduce(0) { $0 + $1.intervals.count } == 5_000)

        let start = Date()
        let snapshot = StatisticsAggregator.aggregate(sessions: sessions, range: wideRange)
        let elapsed = Date().timeIntervalSince(start)

        #expect(snapshot.startedSessions == 1_000)
        #expect(snapshot.completedSessions == 1_000)
        #expect(snapshot.stoppedSessions == 0)
        #expect(snapshot.completedFocusIntervals == 3_000)               // 1000 × 3
        #expect(snapshot.focusDuration == 3_000 * Self.focusDuration)     // 4,500,000 s
        #expect(snapshot.breakDuration == 2_000 * Self.breakDuration)     // 600,000 s
        // The daily breakdown fills every calendar day in the range; activity spans
        // 30 distinct days, so at least that many buckets exist.
        #expect(snapshot.daily.count >= 30)
        // Three configuration names, grouped.
        #expect(snapshot.configurations.count == 3)
        #expect(snapshot.configurations.reduce(0) { $0 + $1.completedFocusIntervals } == 3_000)

        #expect(elapsed < 2.0, "aggregating 5k intervals took \(elapsed)s")
    }

    @Test("2,000 sessions × 6 intervals (12,000 intervals) aggregate exactly and quickly")
    func twelveThousandIntervals() {
        let sessions = makeSessions(sessionCount: 2_000, focusPerSession: 4, breakPerSession: 2)
        #expect(sessions.reduce(0) { $0 + $1.intervals.count } == 12_000)

        let start = Date()
        let snapshot = StatisticsAggregator.aggregate(sessions: sessions, range: wideRange)
        let elapsed = Date().timeIntervalSince(start)

        #expect(snapshot.completedSessions == 2_000)
        #expect(snapshot.completedFocusIntervals == 8_000)               // 2000 × 4
        #expect(snapshot.focusDuration == 8_000 * Self.focusDuration)
        #expect(elapsed < 3.0, "aggregating 12k intervals took \(elapsed)s")
    }

    @Test("A narrow range over a large history selects only the in-range sessions")
    func narrowRangeOverLargeHistory() {
        // 1,000 sessions spaced one hour apart, each 3 completed focus intervals inside
        // that hour. Selecting the first 100 hours by instant is calendar-independent.
        let sessions: [SessionStatInput] = (0..<1_000).map { i in
            let start = Self.base.addingTimeInterval(TimeInterval(i) * 3_600)
            let intervals = (0..<3).map { k -> IntervalStatInput in
                let s = start.addingTimeInterval(TimeInterval(k) * 300)
                return IntervalStatInput(phase: .focus, status: .completed, plannedDuration: 300,
                                         startedAt: s, endedAt: s.addingTimeInterval(300),
                                         configurationName: "Deep Work")
            }
            return SessionStatInput(id: UUID(), taskName: "T\(i)", configurationName: "Deep Work",
                                    status: .completed, startedAt: start,
                                    endedAt: start.addingTimeInterval(900), intervals: intervals)
        }
        // A window covering exactly the first 100 sessions' start instants.
        let range = StatisticsDateRange(start: Self.base.addingTimeInterval(-1),
                                        end: Self.base.addingTimeInterval(100 * 3_600))
        let snapshot = StatisticsAggregator.aggregate(sessions: sessions, range: range)

        #expect(snapshot.startedSessions == 100)
        #expect(snapshot.completedFocusIntervals == 300)   // 100 × 3
    }
}

@MainActor
@Suite("Large-history stress — repository fetch")
struct LargeHistoryRepositoryStressTests {

    @Test("StatisticsRepository maps + aggregates 1,000 persisted sessions within budget")
    func thousandSessionsThroughRepository() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let ctx = container.mainContext

        let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let config = PomodoroConfiguration.classic()
        ctx.insert(config)

        // 1,000 completed sessions, each 3 focus + 1 break = 4,000 intervals.
        for i in 0..<1_000 {
            let start = base.addingTimeInterval(TimeInterval(i) * 3_600)
            let session = FocusSession(taskName: "Task \(i)", configuration: config,
                                       status: .completed, startedAt: start)
            session.configurationName = config.name
            ctx.insert(session)
            var order = 0
            var cursor = start
            for _ in 0..<3 {
                let iv = SessionInterval(phase: .focus, plannedDuration: 1_500, order: order)
                iv.startedAt = cursor
                iv.endedAt = cursor.addingTimeInterval(1_500)
                iv.status = .completed
                iv.configurationName = config.name
                iv.session = session
                ctx.insert(iv)
                cursor = iv.endedAt!
                order += 1
            }
            let brk = SessionInterval(phase: .shortBreak, plannedDuration: 300, order: order)
            brk.startedAt = cursor
            brk.endedAt = cursor.addingTimeInterval(300)
            brk.status = .completed
            brk.session = session
            ctx.insert(brk)
        }
        try ctx.save()

        let start = Date()
        let inputs = try StatisticsRepository(context: ctx).sessionInputs()
        let range = StatisticsDateRange(start: base.addingTimeInterval(-3_600),
                                        end: base.addingTimeInterval(1_001 * 3_600))
        let snapshot = StatisticsAggregator.aggregate(sessions: inputs, range: range)
        let elapsed = Date().timeIntervalSince(start)

        #expect(inputs.count == 1_000)
        #expect(snapshot.completedSessions == 1_000)
        #expect(snapshot.completedFocusIntervals == 3_000)
        #expect(snapshot.focusDuration == 3_000 * 1_500)
        // Generous ceiling: fetch + map + aggregate of 1k sessions / 4k intervals.
        #expect(elapsed < 10.0, "repository fetch + aggregate took \(elapsed)s")

        // Keep the container alive to the end of the test (a context does not retain it).
        _ = container
    }
}
