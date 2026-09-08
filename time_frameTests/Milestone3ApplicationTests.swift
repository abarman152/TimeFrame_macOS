//
//  Milestone3ApplicationTests.swift
//  time_frameTests
//
//  Application-layer behaviour introduced in Milestone 3: the per-run session
//  count override, the frozen configuration-name snapshot, history-derived
//  values, edit-while-running isolation, relaunch recovery outcomes, and the
//  "start new session" reset. Deterministic (mock clock, in-memory store).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Session count override")
struct SessionCountOverrideTests {

    @Test("The override sets this run's focus count without touching the configuration")
    func overrideDoesNotMutateConfiguration() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, total: 4) // default 4 sessions
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(
            configuration: config, taskName: "X", totalSessions: 2))

        #expect(coordinator.engine.totalFocusSessions == 2)
        #expect(session.intervals.count == 4)          // focus, break, focus, break
        #expect(config.defaultTotalSessions == 4)      // configuration unchanged
    }

    @Test("Omitting the override uses the configuration's default count")
    func defaultCountUsedWhenNoOverride() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, total: 3)
        let coordinator = makeCoordinator(container, clock: clock)

        _ = try #require(try coordinator.startSession(configuration: config, taskName: "X"))
        #expect(coordinator.engine.totalFocusSessions == 3)
    }
}

@MainActor
@Suite("Configuration name snapshot")
struct ConfigurationNameSnapshotTests {

    @Test("A session freezes the configuration name at start")
    func snapshotCapturedAtStart() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container) // named "Test"
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config, taskName: "X"))
        #expect(session.configurationName == "Test")
        #expect(session.displayConfigurationName == "Test")
    }

    @Test("Renaming the configuration later does not change history")
    func renameDoesNotChangeHistory() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config, taskName: "X"))
        try coordinator.configurations.update(config, with: ConfigurationDraft(
            name: "Renamed",
            focusDuration: config.focusDuration,
            shortBreakDuration: config.shortBreakDuration,
            longBreakDuration: config.longBreakDuration,
            sessionsBeforeLongBreak: config.sessionsBeforeLongBreak,
            totalSessions: config.defaultTotalSessions
        ))

        #expect(config.name == "Renamed")
        #expect(session.configurationName == "Test")        // frozen
        #expect(session.displayConfigurationName == "Test")
    }

    @Test("Deleting the configuration leaves the history name intact")
    func deleteKeepsSnapshotName() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config, taskName: "X"))
        try coordinator.stop() // finish so nothing is mid-run
        try coordinator.configurations.delete(config)

        #expect(session.configurationName == "Test")
        #expect(session.displayConfigurationName == "Test")
    }
}

@MainActor
@Suite("History derived values")
struct HistoryDerivedValuesTests {

    @Test("Completed focus count and duration come from persisted intervals")
    func derivedFromIntervals() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 10, short: 5, total: 1)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config, taskName: "X"))
        clock.advance(by: 10); try coordinator.tick() // focus completes → break runs
        clock.advance(by: 5); try coordinator.tick()  // break completes → session done

        #expect(session.status == .completed)
        #expect(session.completedFocusCount == 1)
        #expect(session.plannedFocusCount == 1)
        expectClose(session.completedFocusDuration, 10)
    }

    @Test("A stopped session reports only the focus intervals it completed")
    func stoppedSessionCounts() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        // total 2 → F,B,F,B. Complete the first focus, then stop mid-second-focus.
        let config = try insertConfiguration(container, focus: 10, short: 5, total: 2)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config, taskName: "X"))
        clock.advance(by: 10); try coordinator.tick() // focus 0 done
        clock.advance(by: 5); try coordinator.tick()  // break done, focus 1 running
        clock.advance(by: 2); try coordinator.stop()

        #expect(session.status == .cancelled)
        #expect(session.completedFocusCount == 1) // only the first focus completed
        #expect(session.plannedFocusCount == 2)
    }
}

@MainActor
@Suite("Configuration edits do not affect the running session")
struct EditWhileRunningTests {

    @Test("Editing the active configuration leaves the running plan unchanged")
    func editDoesNotMutateRun() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 10) // 10-second focus
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config, taskName: "X"))
        #expect(coordinator.engine.currentPlannedDuration == 10)

        // Change the saved configuration to a much longer focus.
        try coordinator.configurations.update(config, with: ConfigurationDraft(
            name: config.name,
            focusDuration: 60 * 60,
            shortBreakDuration: config.shortBreakDuration,
            longBreakDuration: config.longBreakDuration,
            sessionsBeforeLongBreak: config.sessionsBeforeLongBreak,
            totalSessions: config.defaultTotalSessions
        ))

        #expect(config.focusDuration == 60 * 60)                       // config updated
        #expect(coordinator.engine.currentPlannedDuration == 10)       // run unchanged
        #expect(coordinator.engine.plan.interval(at: 0)?.duration == 10)
        #expect(session.orderedIntervals[0].plannedDuration == 10)     // persisted interval unchanged
    }
}

@MainActor
@Suite("Start-new-session reset")
struct PrepareForNewSessionTests {

    @Test("Preparing for a new session clears a completed run")
    func prepareResetsCompleted() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 10, short: 5, total: 1)
        let coordinator = makeCoordinator(container, clock: clock)

        _ = try #require(try coordinator.startSession(configuration: config, taskName: "X"))
        clock.advance(by: 10); try coordinator.tick()
        clock.advance(by: 5); try coordinator.tick()
        #expect(coordinator.engine.state == .completed)

        coordinator.prepareForNewSession()
        #expect(coordinator.engine.state == .idle)
        #expect(coordinator.activeSession == nil)
    }

    @Test("Preparing is ignored while a session is still active")
    func prepareIgnoredWhileActive() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)
        let coordinator = makeCoordinator(container, clock: clock)

        _ = try #require(try coordinator.startSession(configuration: config, taskName: "X"))
        coordinator.prepareForNewSession()
        #expect(coordinator.engine.state == .running) // untouched
        #expect(coordinator.activeSession != nil)
    }
}

@MainActor
@Suite("Recovery outcome surfaced to the UI")
struct RecoveryOutcomeTests {

    @Test("A restorable running session yields a restored outcome")
    func restoredOutcome() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 100)

        // Coordinator A starts and leaves a live running session persisted.
        let coordinatorA = makeCoordinator(container, clock: clock)
        _ = try #require(try coordinatorA.startSession(configuration: config, taskName: "X"))

        // Coordinator B (fresh engine) recovers from the same store.
        let coordinatorB = makeCoordinator(container, clock: clock)
        let restored = try coordinatorB.recover()

        #expect(restored)
        #expect(coordinatorB.recoveryOutcome == .restored)
        #expect(coordinatorB.engine.state == .running)

        coordinatorB.acknowledgeRecovery()
        #expect(coordinatorB.recoveryOutcome == .none)
    }

    @Test("An inconsistent recoverable session yields an interrupted outcome")
    func interruptedOutcome() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)

        // A session marked running but with no intervals cannot be safely
        // restored — recovery must mark it interrupted.
        let session = FocusSession(taskName: "Broken", configuration: config,
                                   status: .running, startedAt: clock.now())
        container.mainContext.insert(session)
        try container.mainContext.save()

        let coordinator = makeCoordinator(container, clock: clock)
        let restored = try coordinator.recover()

        #expect(restored == false)
        #expect(coordinator.recoveryOutcome == .interrupted)
        #expect(coordinator.interruptedSession?.taskName == "Broken")
        #expect(session.status == .interrupted)
    }
}
