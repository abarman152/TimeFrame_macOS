//
//  AppIntentStateProjectionTests.swift
//  time_frameTests (Milestone 12)
//
//  Proves `AppIntentSessionState` is a faithful, read-only projection of the one
//  authoritative engine across every lifecycle state, and that `AppIntentDialogText` phrases
//  each state correctly. Deterministic: a mock clock, heartbeat off, no real time.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("App Intent state projection")
struct AppIntentStateProjectionTests {

    @Test("Idle before any session")
    func idle() throws {
        let rig = try makeAppIntentRig()
        let state = rig.actions.status()
        #expect(state.situation == .idle)
        #expect(state.state == .idle)
        #expect(!state.isActive)
        #expect(!state.hasSession)
        #expect(state.phase == nil)
        #expect(state.sessionIndex == nil)
        #expect(state.totalSessions == nil)
    }

    @Test("Running focus interval")
    func focus() throws {
        let rig = try makeAppIntentRig(focus: 600, total: 4)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Research Paper")
        rig.clock.advance(by: 120) // 2 minutes elapsed → 8 remaining

        let state = rig.actions.status()
        #expect(state.situation == .running)
        #expect(state.phase == .focus)
        #expect(state.taskName == "Research Paper")
        #expect(state.configurationName == "Deep Work")
        #expect(state.sessionIndex == 1)
        #expect(state.totalSessions == 4)
        #expect(state.nextPhase == .shortBreak)
        expectClose(state.remaining, 480, tolerance: 1)
    }

    @Test("Short break interval")
    func shortBreak() throws {
        let rig = try makeAppIntentRig(focus: 10, short: 5, before: 4, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 10) // finish first focus
        try rig.coordinator.tick()

        let state = rig.actions.status()
        #expect(state.situation == .running)
        #expect(state.phase == .shortBreak)
        #expect(state.nextPhase == .focus)
    }

    @Test("Long break interval")
    func longBreak() throws {
        let rig = try makeAppIntentRig(focus: 10, short: 5, long: 15, before: 2, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 25) // focus, short, focus → now at the long break (index 3)
        try rig.coordinator.tick()

        let state = rig.actions.status()
        #expect(state.phase == .longBreak)
        expectClose(state.remaining, 15, tolerance: 1)
    }

    @Test("Paused freezes remaining")
    func paused() throws {
        let rig = try makeAppIntentRig(focus: 600)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 100) // 500 remaining
        try rig.coordinator.pause()
        rig.clock.advance(by: 999) // time passes while paused — must not change remaining

        let state = rig.actions.status()
        #expect(state.situation == .paused)
        #expect(state.state == .paused)
        expectClose(state.remaining, 500, tolerance: 1)
    }

    @Test("Completed after last interval")
    func completed() throws {
        let rig = try makeAppIntentRig(focus: 10, short: 5, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 10); try rig.coordinator.tick() // focus done → short break
        rig.clock.advance(by: 5); try rig.coordinator.tick()  // break done → completed

        let state = rig.actions.status()
        #expect(state.situation == .completed)
        #expect(state.state == .completed)
        #expect(!state.isActive)
    }

    @Test("Interrupted situation maps from recovery outcome")
    func interruptedMapping() {
        // Built directly via the memberwise initializer: the interrupted outcome is a
        // recovery-only state (exercised end-to-end by the recovery suites); here we verify
        // the projection's own mapping and phrasing.
        let state = AppIntentSessionState(
            situation: .interrupted, state: .idle, phase: nil,
            taskName: "Research Paper", configurationName: "Deep Work",
            remaining: 0, sessionIndex: nil, totalSessions: nil, nextPhase: nil
        )
        #expect(state.situation == .interrupted)
        #expect(state.hasSession)
        #expect(!state.isActive)
    }
}

@Suite("App Intent dialog text")
struct AppIntentDialogTextTests {

    @Test("Focus status names task, session, and remaining")
    func focusStatus() {
        let state = AppIntentSessionState(
            situation: .running, state: .running, phase: .focus,
            taskName: "Research Paper", configurationName: "Deep Work",
            remaining: 18 * 60, sessionIndex: 2, totalSessions: 4, nextPhase: .shortBreak)
        let text = AppIntentDialogText.status(state)
        #expect(text.contains("Research Paper"))
        #expect(text.contains("Session 2 of 4"))
        #expect(text.contains("18 minutes"))
    }

    @Test("Break status uses break wording")
    func breakStatus() {
        let state = AppIntentSessionState(
            situation: .running, state: .running, phase: .shortBreak,
            taskName: "Research Paper", configurationName: "Deep Work",
            remaining: 5 * 60, sessionIndex: 2, totalSessions: 4, nextPhase: .focus)
        let text = AppIntentDialogText.status(state)
        #expect(text.lowercased().contains("break"))
        #expect(text.contains("5 minutes"))
    }

    @Test("Paused status mentions paused")
    func pausedStatus() {
        let state = AppIntentSessionState(
            situation: .paused, state: .paused, phase: .focus,
            taskName: "Writing", configurationName: "Deep Work",
            remaining: 90, sessionIndex: 1, totalSessions: 2, nextPhase: .shortBreak)
        let text = AppIntentDialogText.status(state)
        #expect(text.lowercased().contains("paused"))
    }

    @Test("Idle and completed have their own sentences")
    func idleCompleted() {
        let idle = AppIntentSessionState(
            situation: .idle, state: .idle, phase: nil, taskName: nil,
            configurationName: nil, remaining: 0, sessionIndex: nil,
            totalSessions: nil, nextPhase: nil)
        #expect(AppIntentDialogText.status(idle).contains("No Time Frame session"))

        let done = AppIntentSessionState(
            situation: .completed, state: .completed, phase: nil, taskName: "X",
            configurationName: "Deep Work", remaining: 0, sessionIndex: nil,
            totalSessions: 4, nextPhase: nil)
        #expect(AppIntentDialogText.status(done).lowercased().contains("complete"))
    }

    @Test("Remaining clause rounds and singularizes")
    func remainingClause() {
        #expect(AppIntentDialogText.remainingClause(18 * 60) == "18 minutes")
        #expect(AppIntentDialogText.remainingClause(60) == "1 minute")
        #expect(AppIntentDialogText.remainingClause(20) == "less than a minute")
        #expect(AppIntentDialogText.remainingClause(-5) == "less than a minute")
    }

    @Test("Start confirmation names task, configuration, and count")
    func startConfirmation() {
        let text = AppIntentDialogText.started(task: "Research Paper", configurationName: "Deep Work", sessionCount: 4)
        #expect(text.contains("Research Paper"))
        #expect(text.contains("Deep Work"))
        #expect(text.contains("1 of 4"))
    }
}
