//
//  StatisticsApplicationTests.swift
//  time_frameTests
//
//  Application-level checks for Milestone 10: Statistics is present in navigation,
//  Today draws from the *same* statistics engine (no duplicate aggregation), the
//  period selector changes results, the empty-state condition is correct, and reading
//  statistics never disturbs the timer or History.
//
//  IMPORTANT: each SwiftData test keeps its `ModelContainer` alive for the whole body.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("Statistics navigation")
struct StatisticsNavigationTests {

    @Test("Statistics is a sidebar section between History and Settings")
    func statisticsInSidebar() {
        #expect(AppSection.allCases.contains(.statistics))
        let order = AppSection.allCases
        let history = try! #require(order.firstIndex(of: .history))
        let stats = try! #require(order.firstIndex(of: .statistics))
        let settings = try! #require(order.firstIndex(of: .settings))
        #expect(history < stats)
        #expect(stats < settings)
    }

    @Test("Statistics has a title and an SF Symbol")
    func statisticsPresentation() {
        #expect(AppSection.statistics.title == "Statistics")
        #expect(!AppSection.statistics.symbol.isEmpty)
    }
}

@MainActor
@Suite("Today shares the statistics engine")
struct TodaySharedEngineTests {

    /// Runs one single-focus session to completion with its dates anchored at `at`.
    @discardableResult
    private func runSession(_ container: ModelContainer, config: PomodoroConfiguration, at: Date) throws -> FocusSession {
        let clock = MockTimeSource(start: at)
        let coordinator = makeCoordinator(container, clock: clock)
        let session = try #require(try coordinator.startSession(configuration: config, taskName: "Focus", totalSessions: 1))
        clock.advance(by: config.focusDuration); try coordinator.tick()
        clock.advance(by: config.shortBreakDuration); try coordinator.tick()
        return session
    }

    @Test("Today's figures equal the shared aggregator over the .today period")
    func todayMatchesAggregator() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, name: "Deep Work", focus: 10, short: 5, total: 1)
        let calendar = Calendar.current

        // Two sessions today, one yesterday — all completed.
        try runSession(container, config: config, at: .now)
        try runSession(container, config: config, at: .now)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) {
            try runSession(container, config: config, at: yesterday)
        }

        let sessions = try makeSessionRepository(container).allSessions()

        // The OLD TodayView logic, reproduced here as the reference.
        let todays = sessions.filter { $0.startedAt.map { calendar.isDateInToday($0) } ?? false }
        let manualCount = todays.reduce(0) { $0 + $1.completedFocusCount }
        let manualFocus = todays.reduce(0) { $0 + $1.completedFocusDuration }

        // The NEW shared engine, exactly as TodayView now calls it.
        let snapshot = StatisticsAggregator.aggregate(
            sessions: sessions.map { SessionStatInput($0) },
            range: StatisticsPeriod.today.range(calendar: calendar),
            calendar: calendar)

        #expect(snapshot.completedFocusIntervals == manualCount)
        #expect(snapshot.focusDuration == manualFocus)
        #expect(manualCount == 2) // sanity: only today's two sessions
    }
}

@Suite("Statistics period selection and empty state")
struct StatisticsPeriodSelectionTests {

    @Test("Selecting a wider period changes the aggregated result")
    func periodSelectionChangesResults() {
        let cal = statCalendar()
        let ref = statDate(2026, 8, 14, 12, 0, calendar: cal)          // a Friday
        let today = statDate(2026, 8, 14, 10, 0, calendar: cal)
        let earlierThisWeek = statDate(2026, 8, 11, 10, 0, calendar: cal) // Tuesday, same week
        let sessions = [
            statSession(startedAt: today, intervals: [statFocus(60 * 60, endedAt: today)]),
            statSession(startedAt: earlierThisWeek, intervals: [statFocus(60 * 60, endedAt: earlierThisWeek)])
        ]

        let todaySnapshot = StatisticsAggregator.aggregate(
            sessions: sessions, range: StatisticsPeriod.today.range(reference: ref, calendar: cal), calendar: cal)
        let weekSnapshot = StatisticsAggregator.aggregate(
            sessions: sessions, range: StatisticsPeriod.thisWeek.range(reference: ref, calendar: cal), calendar: cal)

        #expect(todaySnapshot.focusDuration == 60 * 60)   // only today
        #expect(weekSnapshot.focusDuration == 120 * 60)   // both days this week
        #expect(weekSnapshot.focusDuration != todaySnapshot.focusDuration)
    }

    @Test("The new-user empty-state condition holds only when nothing has started")
    func emptyStateCondition() {
        let cal = statCalendar()
        let noHistory: [SessionStatInput] = [statSession(status: .planned, startedAt: nil)]
        #expect(!noHistory.contains { $0.didStart })

        let day = statDate(2026, 8, 14, calendar: cal)
        let withHistory = [statSession(startedAt: day, intervals: [statFocus(endedAt: day)])]
        #expect(withHistory.contains { $0.didStart })
    }
}

@MainActor
@Suite("Statistics does not disturb the timer or History")
struct StatisticsIsolationTests {

    @Test("Reading statistics mid-session leaves the running timer untouched")
    func readingStatisticsDoesNotAffectTimer() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource(start: .now)
        let config = try insertConfiguration(container, name: "Deep Work", focus: 100, short: 20, total: 4)
        let coordinator = makeCoordinator(container, clock: clock)
        _ = try #require(try coordinator.startSession(configuration: config, taskName: "Focus", totalSessions: 4))
        clock.advance(by: 30); try coordinator.tick()
        let remainingBefore = coordinator.engine.remaining
        let indexBefore = coordinator.engine.currentIndex

        // Aggregate over history while the session is live.
        let repo = StatisticsRepository(context: container.mainContext)
        _ = StatisticsAggregator.aggregate(sessions: try repo.sessionInputs(), range: allTimeRange, calendar: statCalendar())

        #expect(coordinator.engine.state == .running)
        #expect(coordinator.engine.remaining == remainingBefore)
        #expect(coordinator.engine.currentIndex == indexBefore)
        // The timer still responds normally afterwards.
        try coordinator.pause()
        #expect(coordinator.engine.state == .paused)
        try coordinator.resume()
        #expect(coordinator.engine.state == .running)
        try coordinator.stop()
    }

    @Test("History's derived values are unchanged after statistics run")
    func historyUnaffected() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource(start: .now)
        let config = try insertConfiguration(container, name: "Deep Work", focus: 10, short: 5, total: 1)
        let coordinator = makeCoordinator(container, clock: clock)
        let session = try #require(try coordinator.startSession(configuration: config, taskName: "Focus", totalSessions: 1))
        clock.advance(by: 10); try coordinator.tick()
        clock.advance(by: 5); try coordinator.tick()

        let focusCountBefore = session.completedFocusCount
        let focusDurationBefore = session.completedFocusDuration

        let repo = StatisticsRepository(context: container.mainContext)
        _ = StatisticsAggregator.aggregate(sessions: try repo.sessionInputs(), range: allTimeRange, calendar: statCalendar())

        #expect(session.completedFocusCount == focusCountBefore)
        #expect(session.completedFocusDuration == focusDurationBefore)
        #expect(try makeSessionRepository(container).allSessions().count == 1)
    }
}
