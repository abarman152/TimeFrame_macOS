//
//  MenuBarPresentationTests.swift
//  time_frameTests
//
//  The menu-bar presentation is a pure projection of the one authoritative engine (§48).
//  These tests build the real coordinator + engine and assert the projected
//  `MenuBarPresentationState` for every situation: idle, focus running, short/long break,
//  paused, completed, interrupted — plus that it shows the session's frozen values, not
//  the live configuration (§53/§57).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Menu bar presentation")
struct MenuBarPresentationTests {

    // MARK: Idle / empty (§50/§57)

    @Test("No active session projects the empty state")
    func idleEmpty() throws {
        let rig = try makeMenuBarRig()
        let state = rig.menuBar.presentation
        #expect(state.situation == .empty)
        #expect(state.hasActiveSession == false)
        #expect(state.taskName == nil)
        #expect(state.phase == nil)
        #expect(state.remaining == 0)
        // Never a bare 00:00 — the compact title is the app name (§50).
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: true) == "Time Frame")
    }

    // MARK: Focus running (§15/§57)

    @Test("A running focus session projects task, phase, remaining and progress")
    func focusRunning() throws {
        let rig = try makeMenuBarRig(focus: 1500, total: 4)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Write RFC")

        let state = rig.menuBar.presentation
        #expect(state.situation == .running)
        #expect(state.hasActiveSession)
        #expect(state.taskName == "Write RFC")
        #expect(state.configurationName == "Test")
        #expect(state.phase == .focus)
        #expect(state.currentPhaseIsFocus)
        expectClose(state.remaining, 1500)
        #expect(state.currentFocusNumber == 1)
        #expect(state.totalFocusSessions == 4)
        #expect(state.completedFocusCount == 0)
        #expect(state.nextPhase == .shortBreak)
        expectClose(state.nextDuration ?? -1, 300)
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: true) == "Focus 25:00")
        #expect(MenuBarStatusPresentation.symbolName(for: state) == "timer")
    }

    // MARK: Short break (§16/§57)

    @Test("A short break projects the break phase and next focus")
    func shortBreak() throws {
        // before: 4 → the first break is short.
        let rig = try makeMenuBarRig(focus: 10, short: 300, before: 4, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 10) // finish focus 0
        try rig.coordinator.tick()

        let state = rig.menuBar.presentation
        #expect(state.situation == .running)
        #expect(state.phase == .shortBreak)
        #expect(state.currentPhaseIsFocus == false)
        #expect(state.completedFocusCount == 1)
        #expect(state.nextPhase == .focus)
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: true) == "Break 05:00")
        #expect(MenuBarStatusPresentation.symbolName(for: state) == "cup.and.saucer")
    }

    // MARK: Long break (§17/§57)

    @Test("A long break projects the long-break phase")
    func longBreak() throws {
        // before: 1 → every break is a long break; the first break is long.
        let rig = try makeMenuBarRig(focus: 10, long: 900, before: 1, total: 2)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 10) // finish focus 0
        try rig.coordinator.tick()

        let state = rig.menuBar.presentation
        #expect(state.phase == .longBreak)
        #expect(state.completedFocusCount == 1)
        expectClose(state.remaining, 900)
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: true) == "Break 15:00")
    }

    // MARK: Paused (§18/§57)

    @Test("Pausing freezes the projected remaining time")
    func paused() throws {
        let rig = try makeMenuBarRig(focus: 1500, total: 4)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Read")
        rig.clock.advance(by: 60)
        try rig.coordinator.pause()

        let state = rig.menuBar.presentation
        #expect(state.situation == .paused)
        #expect(state.hasActiveSession) // paused is still active
        #expect(state.phase == .focus)
        expectClose(state.remaining, 1440)

        // The engine is paused, so the projection stays frozen as the clock moves on (§18).
        rig.clock.advance(by: 120)
        expectClose(rig.menuBar.presentation.remaining, 1440)
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: true) == "Paused 24:00")
    }

    // MARK: Completed (§51/§57)

    @Test("Completion projects the completed state, not a stale countdown")
    func completed() throws {
        let rig = try makeMenuBarRig(focus: 10, short: 5, total: 1)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Done thing")
        rig.clock.advance(by: 100) // past the whole plan
        try rig.coordinator.tick()
        #expect(rig.coordinator.engine.state == .completed)

        let state = rig.menuBar.presentation
        #expect(state.situation == .completed)
        #expect(state.hasActiveSession == false)
        #expect(state.taskName == "Done thing")
        #expect(state.remaining == 0)
        #expect(state.totalFocusSessions == 1)
        // Title is "Done", never a stale "Focus 00:00" (§51).
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: true) == "Done")
    }

    // MARK: Interrupted (§52/§57)

    @Test("An interrupted recovery projects the interrupted state")
    func interrupted() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let context = container.mainContext

        // A "running" session with a corrupt anchor cannot be restored (mirrors recovery).
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
        _ = try coordinator.recover()
        let menuBar = MenuBarCoordinator(session: coordinator,
                                         preferences: MenuBarPreferencesStore(defaults: makeScratchDefaults()))

        let state = menuBar.presentation
        #expect(state.situation == .interrupted)
        #expect(state.hasActiveSession == false)
        #expect(state.recovery == .interrupted)
        #expect(state.taskName == "broken")
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: true) == "Time Frame")
    }

    // MARK: Configuration independence (§53/§54)

    @Test("The projection shows the session's frozen configuration name, not the live one")
    func frozenConfigurationName() throws {
        let rig = try makeMenuBarRig(focus: 1500, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        #expect(rig.menuBar.presentation.configurationName == "Test")

        // Rename the live configuration mid-run; the running session is unaffected (§54).
        rig.config.name = "Renamed"
        try rig.container.mainContext.save()
        #expect(rig.menuBar.presentation.configurationName == "Test")
    }
}
