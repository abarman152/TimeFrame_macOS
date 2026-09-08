//
//  StatisticsRepositoryTests.swift
//  time_frameTests
//
//  Tests for `StatisticsRepository` — the read-only bridge from persisted history to
//  pure aggregation inputs. Sessions are produced through the real coordinator (so the
//  intervals, statuses and frozen names are exactly what the app writes), then mapped
//  and aggregated. Verifies empty/one/many mapping, and that historical statistics
//  survive a configuration being renamed or deleted (frozen names, ADR-019).
//
//  IMPORTANT: each test keeps its `ModelContainer` alive for the whole body.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Statistics repository")
struct StatisticsRepositoryTests {

    /// Runs one single-focus session to completion on a fixed day, returning it.
    @discardableResult
    private func runCompletedSession(
        _ container: ModelContainer,
        config: PomodoroConfiguration,
        on day: Date,
        task: String = "Focus"
    ) throws -> FocusSession {
        let clock = MockTimeSource(start: day)
        let coordinator = makeCoordinator(container, clock: clock)
        let session = try #require(try coordinator.startSession(
            configuration: config, taskName: task, totalSessions: 1))
        clock.advance(by: config.focusDuration); try coordinator.tick() // focus completes → break
        clock.advance(by: config.shortBreakDuration); try coordinator.tick() // break completes → done
        #expect(session.status == .completed)
        return session
    }

    /// A one-day range around a fixed day, so aggregation is bounded and deterministic.
    private func dayRange(_ day: Date, calendar: Calendar = statCalendar()) -> StatisticsDateRange {
        StatisticsPeriod.custom(start: day, end: day).range(calendar: calendar)
    }

    @Test("An empty store yields no inputs and an empty snapshot")
    func emptyStore() throws {
        let container = try makeInMemoryContainer()
        let repo = StatisticsRepository(context: container.mainContext)
        let inputs = try repo.sessionInputs()
        #expect(inputs.isEmpty)
        let snapshot = StatisticsAggregator.aggregate(sessions: inputs, range: allTimeRange, calendar: statCalendar())
        #expect(snapshot.isEmpty)
    }

    @Test("One completed session maps to one focus interval of the right duration")
    func oneSession() throws {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, 10, 0, calendar: cal)
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, name: "Deep Work", focus: 10, short: 5, total: 1)
        try runCompletedSession(container, config: config, on: day)

        let repo = StatisticsRepository(context: container.mainContext)
        let inputs = try repo.sessionInputs()
        #expect(inputs.count == 1)

        let snapshot = StatisticsAggregator.aggregate(sessions: inputs, range: dayRange(day, calendar: cal), calendar: cal)
        #expect(snapshot.completedSessions == 1)
        #expect(snapshot.completedFocusIntervals == 1)
        #expect(snapshot.focusDuration == 10)
        #expect(snapshot.breakDuration == 5)
        #expect(snapshot.configurations.first?.configurationName == "Deep Work")
    }

    @Test("Multiple sessions across configurations aggregate and group correctly")
    func multipleSessions() throws {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, 10, 0, calendar: cal)
        let container = try makeInMemoryContainer()
        let deep = try insertConfiguration(container, name: "Deep Work", focus: 10, short: 5, total: 1, isDefault: true)
        let research = try insertConfiguration(container, name: "Research", focus: 20, short: 5, total: 1, isDefault: false)
        try runCompletedSession(container, config: deep, on: day)
        try runCompletedSession(container, config: deep, on: day)
        try runCompletedSession(container, config: research, on: day)

        let repo = StatisticsRepository(context: container.mainContext)
        let snapshot = StatisticsAggregator.aggregate(
            sessions: try repo.sessionInputs(), range: dayRange(day, calendar: cal), calendar: cal)
        #expect(snapshot.completedSessions == 3)
        #expect(snapshot.completedFocusIntervals == 3)
        #expect(snapshot.focusDuration == 10 + 10 + 20)
        let byName = Dictionary(uniqueKeysWithValues: snapshot.configurations.map { ($0.configurationName, $0.focusDuration) })
        #expect(byName["Deep Work"] == 20)
        #expect(byName["Research"] == 20)
    }

    @Test("Renaming a configuration does not change historical statistics (frozen name)")
    func renamedConfigurationKeepsFrozenName() throws {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, 10, 0, calendar: cal)
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, name: "Original", focus: 10, short: 5, total: 1)
        try runCompletedSession(container, config: config, on: day)

        // Rename after the session was recorded.
        config.name = "Renamed"
        try container.mainContext.save()

        let repo = StatisticsRepository(context: container.mainContext)
        let snapshot = StatisticsAggregator.aggregate(
            sessions: try repo.sessionInputs(), range: dayRange(day, calendar: cal), calendar: cal)
        #expect(snapshot.configurations.first?.configurationName == "Original") // history unchanged
    }

    @Test("Deleting a configuration leaves its sessions' statistics intact")
    func deletedConfigurationKeepsStatistics() throws {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, 10, 0, calendar: cal)
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, name: "Original", focus: 10, short: 5, total: 1)
        try runCompletedSession(container, config: config, on: day)

        // Delete the configuration; the session (nullified reference) survives with its frozen name.
        let coordinator = makeCoordinator(container, clock: MockTimeSource(start: day))
        try coordinator.configurations.delete(config)

        let repo = StatisticsRepository(context: container.mainContext)
        let snapshot = StatisticsAggregator.aggregate(
            sessions: try repo.sessionInputs(), range: dayRange(day, calendar: cal), calendar: cal)
        #expect(snapshot.completedSessions == 1)
        #expect(snapshot.focusDuration == 10)
        #expect(snapshot.configurations.first?.configurationName == "Original")
    }

    @Test("Aggregation is read-only: it never mutates the persisted sessions")
    func aggregationIsReadOnly() throws {
        let cal = statCalendar()
        let day = statDate(2026, 8, 14, 10, 0, calendar: cal)
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, name: "Deep Work", focus: 10, short: 5, total: 1)
        let session = try runCompletedSession(container, config: config, on: day)
        let statusBefore = session.status
        let intervalStatusesBefore = session.orderedIntervals.map(\.status)

        let repo = StatisticsRepository(context: container.mainContext)
        _ = StatisticsAggregator.aggregate(
            sessions: try repo.sessionInputs(), range: dayRange(day, calendar: cal), calendar: cal)

        #expect(session.status == statusBefore)
        #expect(session.orderedIntervals.map(\.status) == intervalStatusesBefore)
        #expect(!container.mainContext.hasChanges) // no pending writes from reading statistics
    }
}
