//
//  TimerControlIntentTests.swift
//  time_frameTests (Milestone 12)
//
//  Proves the control intents' logic routes through the one coordinator (pause/resume/skip/
//  restart/stop map to the existing engine operations) and that each reports
//  `noActiveSession` when nothing is running. No timer is created here — the mock clock and
//  the authoritative engine do all the work.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Timer control intents")
struct TimerControlIntentTests {

    @Test("Pause then resume moves the engine between paused and running")
    func pauseResume() throws {
        let rig = try makeAppIntentRig(focus: 600)
        try rig.coordinator.startSession(configuration: rig.config)

        try rig.actions.pause()
        #expect(rig.coordinator.engine.state == .paused)

        try rig.actions.resume()
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("Skip advances to the next interval")
    func skipAdvances() throws {
        let rig = try makeAppIntentRig(focus: 10, short: 5, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        let didComplete = try rig.actions.skip()
        #expect(!didComplete)
        #expect(rig.coordinator.engine.currentPhase == .shortBreak)
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("Skipping the final interval completes the session")
    func skipCompletes() throws {
        let rig = try makeAppIntentRig(focus: 10, short: 5, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        _ = try rig.actions.skip() // skip focus → short break
        let didComplete = try rig.actions.skip() // skip short break → complete
        #expect(didComplete)
        #expect(rig.coordinator.engine.state == .completed)
    }

    @Test("Restart resets the current interval to its full duration")
    func restart() throws {
        let rig = try makeAppIntentRig(focus: 600)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 200)
        expectClose(rig.coordinator.engine.remaining, 400, tolerance: 1)

        try rig.actions.restart()
        expectClose(rig.coordinator.engine.remaining, 600, tolerance: 1)
    }

    @Test("Stop cancels the run but preserves history (never a delete)")
    func stopPreservesHistory() throws {
        let rig = try makeAppIntentRig(focus: 10, short: 5, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        let session = rig.coordinator.activeSession
        rig.clock.advance(by: 10); try rig.coordinator.tick() // complete one focus interval

        try rig.actions.stop()
        #expect(rig.coordinator.engine.state == .cancelled)
        // The session still exists with its recorded intervals — stop is not a delete.
        #expect(session != nil)
        #expect((session?.intervals.count ?? 0) >= 1)
    }

    @Test("Every control reports noActiveSession when idle")
    func idleBehavior() throws {
        let rig = try makeAppIntentRig()
        #expect(throws: TimeFrameIntentError.noActiveSession) { try rig.actions.pause() }
        #expect(throws: TimeFrameIntentError.noActiveSession) { try rig.actions.resume() }
        #expect(throws: TimeFrameIntentError.noActiveSession) { try rig.actions.skip() }
        #expect(throws: TimeFrameIntentError.noActiveSession) { try rig.actions.restart() }
        #expect(throws: TimeFrameIntentError.noActiveSession) { try rig.actions.stop() }
    }

    @Test("Controls also report noActiveSession after the run has completed")
    func completedThenControl() throws {
        let rig = try makeAppIntentRig(focus: 10, short: 5, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        _ = try rig.actions.skip(); _ = try rig.actions.skip() // complete
        #expect(rig.coordinator.engine.state == .completed)
        #expect(throws: TimeFrameIntentError.noActiveSession) { try rig.actions.pause() }
    }
}

@MainActor
@Suite("Current status intent")
struct CurrentStatusIntentTests {

    @Test("Idle answer")
    func idle() throws {
        let rig = try makeAppIntentRig()
        let text = AppIntentDialogText.status(rig.actions.status())
        #expect(text.contains("No Time Frame session"))
    }

    @Test("Focus answer names task, session index, and remaining time")
    func focus() throws {
        let rig = try makeAppIntentRig(focus: 20 * 60, total: 4)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Research Paper")
        rig.clock.advance(by: 2 * 60) // 18 minutes remaining

        let state = rig.actions.status()
        #expect(state.sessionIndex == 1)
        let text = AppIntentDialogText.status(state)
        #expect(text.contains("Research Paper"))
        #expect(text.contains("Session 1 of 4"))
        #expect(text.contains("18 minutes"))
    }

    @Test("Break answer uses break wording")
    func onBreak() throws {
        let rig = try makeAppIntentRig(focus: 10, short: 5 * 60, total: 4)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Writing")
        rig.clock.advance(by: 10); try rig.coordinator.tick() // into the short break
        let text = AppIntentDialogText.status(rig.actions.status())
        #expect(text.lowercased().contains("break"))
    }

    @Test("Paused answer mentions paused with correct remaining")
    func paused() throws {
        let rig = try makeAppIntentRig(focus: 20 * 60)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Writing")
        rig.clock.advance(by: 5 * 60) // 15 minutes remaining
        try rig.coordinator.pause()
        let text = AppIntentDialogText.status(rig.actions.status())
        #expect(text.lowercased().contains("paused"))
        #expect(text.contains("15 minutes"))
    }

    @Test("Completed answer")
    func completed() throws {
        let rig = try makeAppIntentRig(focus: 10, short: 5, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        _ = try rig.actions.skip(); _ = try rig.actions.skip()
        let text = AppIntentDialogText.status(rig.actions.status())
        #expect(text.lowercased().contains("complete"))
    }
}
