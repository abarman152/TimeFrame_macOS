//
//  StatisticsAggregationTests.swift
//  time_frameTests
//
//  Deterministic tests for the pure `StatisticsAggregator`: focus/break totals,
//  session counts, completion rate, averages, longest session, and the daily and
//  configuration breakdowns. All fixtures use fixed dates and an injected calendar.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Statistics aggregation — focus and break totals")
struct StatisticsFocusTotalsTests {

    @Test("Focus duration sums only completed focus intervals")
    func focusDurationSumsCompletedFocus() {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, calendar: cal)
        let session = statSession(startedAt: day, intervals: [
            statFocus(25 * 60, endedAt: day),
            statFocus(25 * 60, endedAt: day),
            statFocus(25 * 60, status: .skipped, endedAt: day),   // excluded
            statBreak(5 * 60, endedAt: day)                        // not focus
        ])
        let snapshot = StatisticsAggregator.aggregate(sessions: [session], range: allTimeRange, calendar: cal)
        #expect(snapshot.focusDuration == 50 * 60)
        #expect(snapshot.completedFocusIntervals == 2)
    }

    @Test("Break duration sums only completed break intervals, kept separate from focus")
    func breakDurationSeparate() {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, calendar: cal)
        let session = statSession(startedAt: day, intervals: [
            statFocus(25 * 60, endedAt: day),
            statBreak(5 * 60, phase: .shortBreak, endedAt: day),
            statBreak(15 * 60, phase: .longBreak, endedAt: day),
            statBreak(5 * 60, phase: .shortBreak, status: .cancelled, endedAt: day) // excluded
        ])
        let snapshot = StatisticsAggregator.aggregate(sessions: [session], range: allTimeRange, calendar: cal)
        #expect(snapshot.focusDuration == 25 * 60)
        #expect(snapshot.breakDuration == 20 * 60)
    }

    @Test("Pending, running, skipped and cancelled intervals never count as focus")
    func onlyCompletedCounts() {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, calendar: cal)
        let session = statSession(status: .cancelled, startedAt: day, intervals: [
            statFocus(25 * 60, status: .completed, endedAt: day),
            statFocus(25 * 60, status: .pending, endedAt: nil, startedAt: nil),
            statFocus(25 * 60, status: .running, endedAt: nil, startedAt: day),
            statFocus(25 * 60, status: .skipped, endedAt: day),
            statFocus(25 * 60, status: .cancelled, endedAt: day)
        ])
        let snapshot = StatisticsAggregator.aggregate(sessions: [session], range: allTimeRange, calendar: cal)
        #expect(snapshot.completedFocusIntervals == 1)
        #expect(snapshot.focusDuration == 25 * 60)
    }
}

@Suite("Statistics aggregation — session counts and rates")
struct StatisticsSessionCountsTests {

    private func mixedSessions(_ cal: Calendar) -> [SessionStatInput] {
        let day = statDate(2026, 8, 14, calendar: cal)
        return [
            statSession(status: .completed, startedAt: day, intervals: [statFocus(endedAt: day)]),
            statSession(status: .completed, startedAt: day, intervals: [statFocus(endedAt: day)]),
            statSession(status: .cancelled, startedAt: day, intervals: [statFocus(status: .cancelled, endedAt: day)]),
            statSession(status: .interrupted, startedAt: day, intervals: []),
            statSession(status: .planned, startedAt: nil, intervals: [])   // never started
        ]
    }

    @Test("Started sessions exclude planned (never-started) sessions")
    func startedExcludesPlanned() {
        let cal = statCalendar()
        let snapshot = StatisticsAggregator.aggregate(sessions: mixedSessions(cal), range: allTimeRange, calendar: cal)
        #expect(snapshot.startedSessions == 4)
    }

    @Test("Completed, stopped and interrupted counts are distinct")
    func distinctCounts() {
        let cal = statCalendar()
        let snapshot = StatisticsAggregator.aggregate(sessions: mixedSessions(cal), range: allTimeRange, calendar: cal)
        #expect(snapshot.completedSessions == 2)
        #expect(snapshot.stoppedSessions == 1)
        #expect(snapshot.interruptedSessions == 1)
    }

    @Test("Completion rate is completed over started")
    func completionRate() {
        let cal = statCalendar()
        let snapshot = StatisticsAggregator.aggregate(sessions: mixedSessions(cal), range: allTimeRange, calendar: cal)
        let rate = try! #require(snapshot.completionRate)
        #expect(abs(rate - 0.5) < 0.0001) // 2 of 4
    }

    @Test("Completion rate is nil when nothing started (no divide by zero)")
    func completionRateNilWhenEmpty() {
        let cal = statCalendar()
        let snapshot = StatisticsAggregator.aggregate(sessions: [], range: allTimeRange, calendar: cal)
        #expect(snapshot.completionRate == nil)
        #expect(snapshot.isEmpty)
    }
}

@Suite("Statistics aggregation — averages and longest session")
struct StatisticsAveragesTests {

    @Test("Average focus interval is total focus over completed focus count")
    func averageFocus() {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, calendar: cal)
        let session = statSession(startedAt: day, intervals: [
            statFocus(20 * 60, endedAt: day),
            statFocus(30 * 60, endedAt: day)
        ])
        let snapshot = StatisticsAggregator.aggregate(sessions: [session], range: allTimeRange, calendar: cal)
        let avg = try! #require(snapshot.averageFocusInterval)
        #expect(avg == 25 * 60)
    }

    @Test("Average focus interval is nil with no completed focus intervals")
    func averageFocusNil() {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, calendar: cal)
        let session = statSession(status: .cancelled, startedAt: day, intervals: [
            statFocus(status: .skipped, endedAt: day)
        ])
        let snapshot = StatisticsAggregator.aggregate(sessions: [session], range: allTimeRange, calendar: cal)
        #expect(snapshot.averageFocusInterval == nil)
    }

    @Test("Longest focus session is the largest single-session total focus")
    func longestSession() {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, calendar: cal)
        let small = statSession(startedAt: day, intervals: [statFocus(25 * 60, endedAt: day)])
        let big = statSession(startedAt: day, intervals: [
            statFocus(25 * 60, endedAt: day),
            statFocus(25 * 60, endedAt: day),
            statFocus(25 * 60, endedAt: day)
        ])
        let snapshot = StatisticsAggregator.aggregate(sessions: [small, big], range: allTimeRange, calendar: cal)
        #expect(snapshot.longestFocusSession == 75 * 60)
    }
}

@Suite("Statistics aggregation — daily and configuration breakdowns")
struct StatisticsBreakdownTests {

    @Test("Daily breakdown attributes focus to the interval's own day")
    func dailyBreakdown() {
        let cal = statCalendar()
        let mon = statDate(2026, 8, 10, 10, calendar: cal)
        let tue = statDate(2026, 8, 11, 10, calendar: cal)
        let sessions = [
            statSession(startedAt: mon, intervals: [statFocus(100 * 60, endedAt: mon)]),
            statSession(startedAt: tue, intervals: [statFocus(140 * 60, endedAt: tue)])
        ]
        let range = StatisticsPeriod.custom(start: mon, end: tue).range(calendar: cal)
        let snapshot = StatisticsAggregator.aggregate(sessions: sessions, range: range, calendar: cal)
        #expect(snapshot.daily.count == 2)
        #expect(snapshot.daily[0].focusDuration == 100 * 60)
        #expect(snapshot.daily[1].focusDuration == 140 * 60)
    }

    @Test("Daily breakdown includes zero days for a continuous axis")
    func dailyIncludesZeroDays() {
        let cal = statCalendar()
        let mon = statDate(2026, 8, 10, 10, calendar: cal)
        let wed = statDate(2026, 8, 12, 10, calendar: cal)
        let sessions = [
            statSession(startedAt: mon, intervals: [statFocus(60 * 60, endedAt: mon)]),
            statSession(startedAt: wed, intervals: [statFocus(60 * 60, endedAt: wed)])
        ]
        let range = StatisticsPeriod.custom(start: mon, end: wed).range(calendar: cal)
        let snapshot = StatisticsAggregator.aggregate(sessions: sessions, range: range, calendar: cal)
        #expect(snapshot.daily.count == 3)          // Mon, Tue, Wed
        #expect(snapshot.daily[1].focusDuration == 0) // Tue empty but present
    }

    @Test("Most productive day is the day with the most focus")
    func mostProductiveDay() {
        let cal = statCalendar()
        let mon = statDate(2026, 8, 10, 10, calendar: cal)
        let tue = statDate(2026, 8, 11, 10, calendar: cal)
        let sessions = [
            statSession(startedAt: mon, intervals: [statFocus(60 * 60, endedAt: mon)]),
            statSession(startedAt: tue, intervals: [statFocus(180 * 60, endedAt: tue)])
        ]
        let range = StatisticsPeriod.custom(start: mon, end: tue).range(calendar: cal)
        let snapshot = StatisticsAggregator.aggregate(sessions: sessions, range: range, calendar: cal)
        let best = try! #require(snapshot.mostProductiveDay)
        #expect(cal.isDate(best.date, inSameDayAs: tue))
        #expect(best.focusDuration == 180 * 60)
    }

    @Test("Most productive day is nil when no focus was recorded")
    func mostProductiveDayNil() {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, calendar: cal)
        let session = statSession(status: .cancelled, startedAt: day, intervals: [statFocus(status: .skipped, endedAt: day)])
        let snapshot = StatisticsAggregator.aggregate(
            sessions: [session], range: StatisticsPeriod.custom(start: day, end: day).range(calendar: cal), calendar: cal)
        #expect(snapshot.mostProductiveDay == nil)
    }

    @Test("Configuration breakdown groups by frozen name, interval name winning over session name")
    func configurationBreakdown() {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, calendar: cal)
        let sessions = [
            // Single-config session: intervals carry no name, so the session name is used.
            statSession(startedAt: day, config: "Deep Work", intervals: [
                statFocus(50 * 60, endedAt: day),
                statFocus(50 * 60, endedAt: day)
            ]),
            // Plan session: each focus carries its own frozen configuration name.
            statSession(startedAt: day, config: "Multiple configurations", intervals: [
                statFocus(25 * 60, endedAt: day, config: "Research"),
                statFocus(25 * 60, endedAt: day, config: "Deep Work")
            ])
        ]
        let snapshot = StatisticsAggregator.aggregate(sessions: sessions, range: allTimeRange, calendar: cal)
        let byName = Dictionary(uniqueKeysWithValues: snapshot.configurations.map { ($0.configurationName, $0.focusDuration) })
        let deepWork = try! #require(byName["Deep Work"])
        let research = try! #require(byName["Research"])
        #expect(deepWork == 125 * 60) // 100 (single) + 25 (plan)
        #expect(research == 25 * 60)
        // Descending by focus time.
        #expect(snapshot.configurations.first?.configurationName == "Deep Work")
    }
}
