//
//  WidgetProjectionMappingTests.swift
//  time_frameTests (Milestone 11)
//
//  The widget projection is a pure read-only mirror of the one authoritative engine
//  (ADR-055). These tests build the REAL coordinator + engine (mock clock, heartbeat off)
//  and assert the projected `WidgetProjection` for every state: idle, focus running, short
//  break, long break, paused, completed, and interrupted (via relaunch recovery) — proving
//  the widget never becomes a second source of truth.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Widget projection mapping")
struct WidgetProjectionMappingTests {

    private func map(_ coordinator: SessionCoordinator, at now: Date, today: TodaySummary? = nil) -> WidgetProjection {
        WidgetProjectionMapper.projection(from: coordinator, now: now, today: today)
    }

    // MARK: Idle

    @Test("No active session projects idle")
    func idle() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)

        let p = map(coordinator, at: clock.now())
        #expect(p.state == .idle)
        #expect(p.phase == .none)
        #expect(p.title == nil)
        #expect(p.currentIntervalIndex == nil)
        #expect(p.intervalPlannedEndAt == nil)
        #expect(p.pausedRemainingSeconds == nil)
    }

    // MARK: Focus running

    @Test("A running focus session projects task, phase, interval anchors and progress")
    func focusRunning() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 1500, total: 4)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        try coordinator.startSession(configuration: config, taskName: "Write RFC")

        let p = map(coordinator, at: clock.now(), today: TodaySummary(focusSeconds: 3000, completedSessions: 2))
        #expect(p.state == .running)
        #expect(p.phase == .focus)
        #expect(p.title == "Write RFC")
        #expect(p.configurationName == "Test")
        #expect(p.currentIntervalIndex == 1)
        #expect(p.totalIntervals == 4)
        #expect(p.completedFocusCount == 0)
        #expect(p.intervalStartedAt != nil)
        #expect(p.intervalPlannedEndAt != nil)
        // The planned end is exactly one focus duration after the start anchor.
        if let start = p.intervalStartedAt, let end = p.intervalPlannedEndAt {
            expectClose(end.timeIntervalSince(start), 1500)
        }
        #expect(p.pausedRemainingSeconds == nil)
        #expect(p.focusSecondsToday == 3000)
        #expect(p.completedSessionsToday == 2)
    }

    // MARK: Short break

    @Test("A short break projects the shortBreak phase")
    func shortBreak() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 10, short: 300, before: 4, total: 4)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        try coordinator.startSession(configuration: config)
        clock.advance(by: 10) // finish focus 0
        try coordinator.tick()

        let p = map(coordinator, at: clock.now())
        #expect(p.state == .running)
        #expect(p.phase == .shortBreak)
        #expect(p.completedFocusCount == 1)
    }

    // MARK: Long break

    @Test("A long break projects the longBreak phase")
    func longBreak() throws {
        // before: 1 → the first break after focus 0 is the long break.
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 10, long: 900, before: 1, total: 2)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        try coordinator.startSession(configuration: config)
        clock.advance(by: 10)
        try coordinator.tick()

        let p = map(coordinator, at: clock.now())
        #expect(p.phase == .longBreak)
    }

    // MARK: Paused

    @Test("A paused session projects paused with frozen remaining and no live end anchor")
    func paused() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 100)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        try coordinator.startSession(configuration: config)
        clock.advance(by: 40)
        try coordinator.pause()

        let p = map(coordinator, at: clock.now())
        #expect(p.state == .paused)
        #expect(p.phase == .focus)
        #expect(p.intervalPlannedEndAt == nil) // never a live countdown while paused
        #expect(p.pausedRemainingSeconds != nil)
        expectClose(p.pausedRemainingSeconds ?? -1, 60) // 100 − 40, frozen

        // Frozen: time passing does not change the projected remaining.
        clock.advance(by: 500)
        let p2 = map(coordinator, at: clock.now())
        expectClose(p2.pausedRemainingSeconds ?? -1, 60)
    }

    // MARK: Completed

    @Test("A completed run projects completed with no active interval")
    func completed() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 10, short: 5, total: 1) // [F10, S5]
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        try coordinator.startSession(configuration: config)
        clock.advance(by: 1000)
        try coordinator.tick()

        let p = map(coordinator, at: clock.now())
        #expect(p.state == .completed)
        #expect(p.phase == .none)
        #expect(p.pausedRemainingSeconds == nil)
        #expect(p.intervalPlannedEndAt == nil)
        #expect(p.totalIntervals == 1)
    }

    // MARK: Interrupted (via relaunch recovery)

    @Test("A session recovery could not resume projects interrupted")
    func interrupted() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let context = container.mainContext

        // Craft a "running" session whose current interval has no target end (corruption).
        let now = Date(timeIntervalSince1970: 2_000_000)
        let session = FocusSession(taskName: "broken", configuration: config, status: .running, startedAt: now)
        session.currentIntervalIndex = 0
        let interval = SessionInterval(phase: .focus, plannedDuration: 10, order: 0)
        interval.status = .running
        interval.startedAt = now
        interval.targetEndAt = nil
        session.intervals.append(interval)
        context.insert(session)
        try context.save()

        let coordinator = makeCoordinator(container, clock: MockTimeSource())
        let restored = try coordinator.recover()
        #expect(restored == false)

        let p = map(coordinator, at: Date())
        #expect(p.state == .interrupted)
        #expect(p.phase == .none)
    }
}
