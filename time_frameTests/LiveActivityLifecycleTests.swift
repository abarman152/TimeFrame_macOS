//
//  LiveActivityLifecycleTests.swift
//  time_frameTests (Milestone 16)
//
//  Drives the platform-neutral `LiveActivityCoordinator` end-to-end through the real
//  `SessionCoordinator` lifecycle seam (via the app's fan-out shape), asserting the fake service
//  is driven correctly at each transition. No ActivityKit runtime; fully deterministic (ADR-072).
//

import Foundation
import Testing
@testable import time_frame

@Suite("LiveActivityLifecycleTests")
@MainActor
struct LiveActivityLifecycleTests {

    @Test("A full run starts one activity and ends it on completion")
    func fullRun() throws {
        let rig = try makeLiveActivityRig(total: 2)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Focus")
        #expect(rig.service.activeCount == 1)

        while rig.coordinator.engine.state.isActive { try rig.coordinator.skip() }
        #expect(rig.coordinator.engine.state == .completed)
        #expect(rig.service.activeCount == 0)   // wound down on completion
    }

    @Test("A disabled preference means no activity is ever started")
    func disabledNeverStarts() throws {
        let rig = try makeLiveActivityRig()
        rig.preferences.enabled = false
        try rig.coordinator.startSession(configuration: rig.config)
        #expect(rig.service.activeCount == 0)
    }

    @Test("An unsupported platform means no activity is ever started")
    func unsupportedNeverStarts() throws {
        let rig = try makeLiveActivityRig(supported: false)
        try rig.coordinator.startSession(configuration: rig.config)
        #expect(rig.service.activeCount == 0)
    }
}

@Suite("LiveActivityStartTests")
@MainActor
struct LiveActivityStartTests {

    @Test("Starting a session starts exactly one activity for that session id")
    func startCreatesOne() throws {
        let rig = try makeLiveActivityRig()
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Draft")
        let id = try #require(rig.coordinator.activeSession?.id)
        #expect(rig.service.soleActiveID == id)
        #expect(rig.service.calls.contains(.start(id)))
        #expect(rig.service.snapshot(for: id)?.identity.taskName == "Draft")
    }

    @Test("Redaction preferences hide task/configuration on the started activity")
    func startRedacts() throws {
        let rig = try makeLiveActivityRig()
        rig.preferences.showsTaskName = false
        rig.preferences.showsConfiguration = false
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Secret")
        let id = try #require(rig.coordinator.activeSession?.id)
        #expect(rig.service.snapshot(for: id)?.identity.taskName == "")
        #expect(rig.service.snapshot(for: id)?.identity.configurationName == "")
    }
}

@Suite("LiveActivityUpdateTests")
@MainActor
struct LiveActivityUpdateTests {

    @Test("An auto interval boundary refreshes the activity in place (no new activity)")
    func autoBoundaryUpdates() throws {
        let rig = try makeLiveActivityRig(focus: 10, short: 5, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        let id = try #require(rig.coordinator.activeSession?.id)

        // Elapse the focus interval so the engine auto-advances to the break on tick.
        rig.clock.advance(by: 11)
        try rig.coordinator.tick()

        #expect(rig.service.soleActiveID == id)         // still exactly one, same session
        #expect(rig.service.calls.contains(.update(id)))
        #expect(rig.service.snapshot(for: id)?.content.phase == .shortBreak)
    }
}

@Suite("LiveActivityPauseResumeTests")
@MainActor
struct LiveActivityPauseResumeTests {

    @Test("Pause updates to paused content; resume updates back to running")
    func pauseResume() throws {
        let rig = try makeLiveActivityRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let id = try #require(rig.coordinator.activeSession?.id)

        rig.clock.advance(by: 2)
        try rig.coordinator.pause()
        #expect(rig.service.snapshot(for: id)?.content.runState == .paused)
        #expect(rig.service.snapshot(for: id)?.content.pausedRemainingSeconds != nil)

        try rig.coordinator.resume()
        #expect(rig.service.snapshot(for: id)?.content.runState == .running)
        #expect(rig.service.activeCount == 1)   // never a duplicate across pause/resume
    }
}

@Suite("LiveActivitySkipTests")
@MainActor
struct LiveActivitySkipTests {

    @Test("Skipping a non-final interval updates the activity, keeping one")
    func skipUpdates() throws {
        let rig = try makeLiveActivityRig(total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        let id = try #require(rig.coordinator.activeSession?.id)

        try rig.coordinator.skip()
        #expect(rig.coordinator.engine.state.isActive)   // not the final interval
        #expect(rig.service.soleActiveID == id)
        #expect(rig.service.calls.contains(.update(id)))
    }
}

@Suite("LiveActivityStopTests")
@MainActor
struct LiveActivityStopTests {

    @Test("Stopping ends the activity immediately")
    func stopEnds() throws {
        let rig = try makeLiveActivityRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let id = try #require(rig.coordinator.activeSession?.id)

        try rig.coordinator.stop()
        #expect(rig.service.activeCount == 0)
        #expect(rig.service.calls.contains(.end(id)))
    }
}

@Suite("LiveActivityCompletionTests")
@MainActor
struct LiveActivityCompletionTests {

    @Test("Completion sends a final update then ends the activity")
    func completionWindsDown() throws {
        let rig = try makeLiveActivityRig(total: 1)
        try rig.coordinator.startSession(configuration: rig.config)

        while rig.coordinator.engine.state.isActive { try rig.coordinator.skip() }
        #expect(rig.coordinator.engine.state == .completed)
        #expect(rig.service.activeCount == 0)
        // The last recorded call for the session is an end (after a final content update).
        if case .end = rig.service.calls.last { } else { Issue.record("expected final end call") }
    }
}
