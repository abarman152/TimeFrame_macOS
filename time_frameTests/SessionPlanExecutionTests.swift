//
//  SessionPlanExecutionTests.swift
//  time_frameTests
//
//  Starting a plan through the existing engine: the FocusSession and its intervals
//  are built correctly (order, phase, duration, per-focus configuration name),
//  multiple configurations execute correctly, and — crucially — the running session
//  is independent of the saved plan and its configurations (edit/delete of either
//  must not change the running session). Plus relaunch recovery of a plan session.
//  Deterministic: mock clock, in-memory store held alive per test.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Session plan execution")
struct SessionPlanExecutionTests {

    /// A plan of focus(3000) / short(300) / focus(3000) — long intervals so nothing
    /// auto-completes unless the clock is advanced.
    private func makeStartedPlan(
        _ container: ModelContainer,
        clock: MockTimeSource
    ) throws -> (SessionCoordinator, SessionPlan, FocusSession) {
        let config = try insertConfiguration(container, name: "Research", focus: 3000, short: 300)
        let repo = makePlanRepository(container)
        let plan = try repo.create(simplePlanDraft(config))
        let coordinator = makeCoordinator(container, clock: clock)
        let session = try #require(try coordinator.startPlan(plan.executionSnapshot))
        return (coordinator, plan, session)
    }

    @Test("Starting a plan builds a running FocusSession with correct intervals")
    func startBuildsSession() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let (coordinator, _, session) = try makeStartedPlan(container, clock: clock)

        #expect(session.taskName == "Research Quantum IDS")
        #expect(coordinator.engine.state == .running)
        #expect(coordinator.engine.currentIndex == 0)
        #expect(coordinator.activeSession?.id == session.id)

        let intervals = session.orderedIntervals
        #expect(intervals.map(\.order) == [0, 1, 2])
        #expect(intervals.map(\.phase) == [.focus, .shortBreak, .focus])
        #expect(intervals.map(\.plannedDuration) == [3000, 300, 3000])
        // Focus intervals freeze their configuration name; the break has none.
        #expect(intervals[0].configurationName == "Research")
        #expect(intervals[1].configurationName == "")
        #expect(intervals[2].configurationName == "Research")
    }

    @Test("A single session and no duplicate intervals are created")
    func noDuplicates() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let (_, _, session) = try makeStartedPlan(container, clock: clock)
        let sessions = makeSessionRepository(container)

        #expect(try sessions.allSessions().count == 1)
        #expect(session.intervals.count == 3)
        #expect(Set(session.intervals.map(\.order)).count == 3) // no duplicate orders
    }

    @Test("A multi-configuration plan executes with per-focus configuration names")
    func multiConfigurationExecution() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let research = try insertConfiguration(container, name: "Research", focus: 3000, short: 300, isDefault: true)
        let writing = try insertConfiguration(container, name: "Writing", focus: 2700, short: 300, isDefault: false)
        let repo = makePlanRepository(container)
        let draft = SessionPlanDraft(name: "Mixed", taskName: "Deep work", items: [
            focusItem(research, order: 0),
            breakItem(.shortBreak, duration: 300, order: 1),
            focusItem(writing, order: 2)
        ])
        let plan = try repo.create(draft)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startPlan(plan.executionSnapshot))
        let intervals = session.orderedIntervals
        #expect(intervals[0].configurationName == "Research")
        #expect(intervals[2].configurationName == "Writing")
        #expect(intervals[0].plannedDuration == 3000)
        #expect(intervals[2].plannedDuration == 2700)
        // The session-level summary reflects that more than one configuration is used.
        #expect(session.configurationName == "Multiple configurations")
        #expect(session.displayConfigurationName == "Multiple configurations")
    }

    // MARK: Independence (mandatory — section 64)

    @Test("Editing the saved plan does not change a running session")
    func editPlanDoesNotChangeSession() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let (coordinator, plan, session) = try makeStartedPlan(container, clock: clock)
        let repo = makePlanRepository(container)

        // Change the first focus duration on the saved plan after starting.
        var draft = plan.draft
        draft.items[0].duration = 6000
        try repo.update(plan, with: draft)

        #expect(plan.orderedItems[0].duration == 6000)                 // plan changed
        #expect(session.orderedIntervals[0].plannedDuration == 3000)   // session unchanged
        #expect(coordinator.engine.currentPlannedDuration == 3000)     // engine unchanged
    }

    @Test("Deleting the saved plan does not stop a running session")
    func deletePlanKeepsSession() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let (coordinator, plan, session) = try makeStartedPlan(container, clock: clock)
        let repo = makePlanRepository(container)
        let sessions = makeSessionRepository(container)

        try repo.delete(plan)

        #expect(try repo.count() == 0)                    // plan gone
        #expect(coordinator.engine.state == .running)     // session still running
        #expect(coordinator.activeSession?.id == session.id)
        #expect(try sessions.allSessions().count == 1)    // session preserved
        #expect(session.orderedIntervals.count == 3)      // intervals intact
    }

    @Test("Editing a referenced configuration does not change a running session")
    func editConfigDoesNotChangeSession() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, name: "Research", focus: 3000, short: 300)
        let repo = makePlanRepository(container)
        let plan = try repo.create(simplePlanDraft(config))
        let coordinator = makeCoordinator(container, clock: clock)
        let session = try #require(try coordinator.startPlan(plan.executionSnapshot))

        try coordinator.configurations.update(config, with: ConfigurationDraft(
            name: "Research", focusDuration: 6000,
            shortBreakDuration: config.shortBreakDuration,
            longBreakDuration: config.longBreakDuration,
            sessionsBeforeLongBreak: config.sessionsBeforeLongBreak,
            totalSessions: config.defaultTotalSessions))

        #expect(config.focusDuration == 6000)                          // config updated
        #expect(session.orderedIntervals[0].plannedDuration == 3000)   // run unchanged
        #expect(coordinator.engine.currentPlannedDuration == 3000)
    }

    @Test("Deleting a referenced configuration leaves a running session valid")
    func deleteConfigKeepsSessionValid() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, name: "Research", focus: 3000, short: 300)
        let repo = makePlanRepository(container)
        let plan = try repo.create(simplePlanDraft(config))
        let coordinator = makeCoordinator(container, clock: clock)
        let session = try #require(try coordinator.startPlan(plan.executionSnapshot))

        try coordinator.configurations.delete(config)

        #expect(coordinator.engine.state == .running)                  // still valid
        #expect(session.orderedIntervals.map(\.plannedDuration) == [3000, 300, 3000])
        #expect(session.orderedIntervals[0].configurationName == "Research") // frozen name intact
    }

    // MARK: Lifecycle

    @Test("A plan session runs to completion through the existing engine")
    func runsToCompletion() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, name: "Research", focus: 10, short: 5)
        let repo = makePlanRepository(container)
        // One focus, no trailing break (plan ends on focus).
        let draft = SessionPlanDraft(name: "Quick", taskName: "Focus", items: [focusItem(config, order: 0)])
        let plan = try repo.create(draft)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startPlan(plan.executionSnapshot))
        clock.advance(by: 10); try coordinator.tick() // the sole focus completes → session done

        #expect(coordinator.engine.state == .completed)
        #expect(session.status == .completed)
        #expect(session.completedFocusCount == 1)
    }

    @Test("A plan session can pause and resume")
    func pauseResume() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let (coordinator, _, _) = try makeStartedPlan(container, clock: clock)

        clock.advance(by: 5)
        try coordinator.pause()
        #expect(coordinator.engine.state == .paused)
        try coordinator.resume()
        #expect(coordinator.engine.state == .running)
    }

    @Test("Starting a plan is ignored while a session is already active")
    func noSecondActiveSession() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let (coordinator, plan, _) = try makeStartedPlan(container, clock: clock)

        let second = try coordinator.startPlan(plan.executionSnapshot)
        #expect(second == nil)
    }

    // MARK: Recovery (existing Milestone 2 mechanism, unchanged)

    @Test("A running plan session is recovered after a simulated relaunch")
    func recoveryAfterRelaunch() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, name: "Research", focus: 3000, short: 300)
        let repo = makePlanRepository(container)
        let plan = try repo.create(simplePlanDraft(config))

        // Start on one coordinator…
        let first = makeCoordinator(container, clock: clock)
        let started = try #require(try first.startPlan(plan.executionSnapshot))
        clock.advance(by: 30)
        try first.tick()

        // …then "relaunch" with a fresh coordinator over the same store and recover.
        let second = makeCoordinator(container, clock: clock)
        let recovered = try second.recover()

        #expect(recovered)
        #expect(second.engine.state == .running)
        #expect(second.activeSession?.id == started.id)
        #expect(second.recoveryOutcome == .restored)
    }
}
