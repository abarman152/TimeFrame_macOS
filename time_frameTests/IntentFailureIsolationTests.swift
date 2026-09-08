//
//  IntentFailureIsolationTests.swift
//  time_frameTests (Milestone 12)
//
//  Proves the core architectural guarantee of Milestone 12: an App Intent failure can never
//  corrupt the timer, and a repository/resolution failure never leaves a partial session
//  behind. Also a small regression pass showing the other integration surfaces (menu bar,
//  widget projection) still read the ONE coordinator after an intent acts on it.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Intent failure isolation")
struct IntentFailureIsolationTests {

    @Test("A failing intent leaves a running session untouched")
    func failureDoesNotCorruptTimer() throws {
        let rig = try makeAppIntentRig(focus: 600)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Research")
        rig.clock.advance(by: 120)
        let remainingBefore = rig.coordinator.engine.remaining
        let indexBefore = rig.coordinator.engine.currentIndex

        // Any start attempt while active must throw and change nothing.
        let template = try insertTemplate(rig.container, configuration: rig.config)
        #expect(throws: TimeFrameIntentError.sessionAlreadyRunning) {
            try rig.actions.startTemplate(id: template.id)
        }

        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.coordinator.engine.currentIndex == indexBefore)
        expectClose(rig.coordinator.engine.remaining, remainingBefore, tolerance: 1)
    }

    @Test("A resolution failure creates no partial session")
    func resolutionFailureNoPartialSession() throws {
        let rig = try makeAppIntentRig()
        let template = try insertTemplate(rig.container, configuration: rig.config)
        let id = template.id
        rig.container.mainContext.delete(template)
        try rig.container.mainContext.save()

        #expect(throws: TimeFrameIntentError.templateUnavailable) {
            try rig.actions.startTemplate(id: id)
        }
        // No engine start, no active session, nothing persisted.
        #expect(rig.coordinator.engine.state == .idle)
        #expect(rig.coordinator.activeSession == nil)
        #expect(try rig.coordinator.sessions.fetchRecoverableSession() == nil)
    }

    @Test("Control failures on an idle engine leave it idle")
    func controlFailureIdle() throws {
        let rig = try makeAppIntentRig()
        #expect(throws: TimeFrameIntentError.noActiveSession) { try rig.actions.stop() }
        #expect(rig.coordinator.engine.state == .idle)
        #expect(rig.coordinator.activeSession == nil)
    }
}

@MainActor
@Suite("App Intent regression — other surfaces still read one coordinator")
struct AppIntentRegressionTests {

    @Test("Menu bar and widget projections reflect an intent-started session")
    func projectionsAgree() throws {
        let rig = try makeAppIntentRig(focus: 600, total: 4)
        try rig.actions.startSession(configurationID: rig.config.id, taskName: "Research", totalSessions: 4)
        rig.clock.advance(by: 60)

        // Menu bar projection — same source of truth.
        let menu = MenuBarPresentationState(coordinator: rig.coordinator)
        #expect(menu.situation == .running)
        #expect(menu.taskName == "Research")
        #expect(menu.phase == .focus)

        // Widget projection — same source of truth.
        let widget = WidgetProjectionMapper.projection(from: rig.coordinator, now: rig.clock.now())
        #expect(widget.state == .running)
        #expect(widget.title == "Research")

        // App Intent projection — same source of truth.
        let intent = rig.actions.status()
        #expect(intent.situation == .running)
        #expect(intent.taskName == "Research")

        // All three agree on the live phase.
        #expect(menu.phase == intent.phase)
    }

    @Test("Stopping through an intent updates all read-only surfaces consistently")
    func stopReflectedEverywhere() throws {
        let rig = try makeAppIntentRig(focus: 600)
        try rig.coordinator.startSession(configuration: rig.config)
        try rig.actions.stop()

        #expect(rig.actions.status().situation == .idle)
        #expect(MenuBarPresentationState(coordinator: rig.coordinator).situation == .empty)
        #expect(WidgetProjectionMapper.projection(from: rig.coordinator, now: rig.clock.now()).state == .idle)
    }
}
