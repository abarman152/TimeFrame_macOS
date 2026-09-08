//
//  StartIntentTests.swift
//  time_frameTests (Milestone 12)
//
//  Drives the start intents' logic (`AppIntentSessionActions`) against a real in-memory
//  coordinator, proving they route through the existing session-start path — never a second
//  timer — and surface friendly errors. Covers Start Time Frame, Start Template, Start Plan.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Start Template intent")
struct StartTemplateIntentTests {

    @Test("Valid template starts through the existing path with the right prefill")
    func validTemplate() throws {
        let rig = try makeAppIntentRig(focus: 600)
        let template = try insertTemplate(
            rig.container, name: "Research", taskName: "Research Paper",
            configuration: rig.config, defaultTotalSessions: 3)

        let outcome = try rig.actions.startTemplate(id: template.id)
        #expect(outcome.taskName == "Research Paper")
        #expect(outcome.configurationName == "Deep Work")
        #expect(outcome.sessionCount == 3)

        // The running session reflects the template's values (prefill correctness).
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.coordinator.activeSession?.taskName == "Research Paper")
        #expect(rig.coordinator.engine.totalFocusSessions == 3)
    }

    @Test("Deleted template reports templateUnavailable")
    func deletedTemplate() throws {
        let rig = try makeAppIntentRig()
        let template = try insertTemplate(rig.container, configuration: rig.config)
        let id = template.id
        rig.container.mainContext.delete(template)
        try rig.container.mainContext.save()

        #expect(throws: TimeFrameIntentError.templateUnavailable) {
            try rig.actions.startTemplate(id: id)
        }
        #expect(rig.coordinator.engine.state == .idle)
    }

    @Test("Template without a configuration reports templateNeedsConfiguration")
    func templateMissingConfiguration() throws {
        let rig = try makeAppIntentRig()
        let template = try insertTemplate(rig.container, configuration: nil)
        #expect(throws: TimeFrameIntentError.templateNeedsConfiguration) {
            try rig.actions.startTemplate(id: template.id)
        }
    }

    @Test("Starting a template while active reports sessionAlreadyRunning")
    func activeConflict() throws {
        let rig = try makeAppIntentRig(focus: 600)
        let template = try insertTemplate(rig.container, configuration: rig.config)
        try rig.coordinator.startSession(configuration: rig.config)

        #expect(throws: TimeFrameIntentError.sessionAlreadyRunning) {
            try rig.actions.startTemplate(id: template.id)
        }
    }
}

@MainActor
@Suite("Start Plan intent")
struct StartPlanIntentTests {

    @Test("Valid plan starts via startPlan and is independent of the saved plan")
    func validPlan() throws {
        let rig = try makeAppIntentRig()
        let plan = try insertPlan(rig.container, configuration: rig.config)

        let outcome = try rig.actions.startPlan(id: plan.id)
        #expect(outcome.isPlan)
        #expect(outcome.planName == "Morning Deep Work")
        #expect(outcome.sessionCount == 2)
        #expect(rig.coordinator.engine.state == .running)

        // Deleting the plan afterwards does not stop or corrupt the running session (ADR-029).
        rig.container.mainContext.delete(plan)
        try rig.container.mainContext.save()
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("Deleted plan reports planUnavailable")
    func deletedPlan() throws {
        let rig = try makeAppIntentRig()
        let plan = try insertPlan(rig.container, configuration: rig.config)
        let id = plan.id
        rig.container.mainContext.delete(plan)
        try rig.container.mainContext.save()

        #expect(throws: TimeFrameIntentError.planUnavailable) {
            try rig.actions.startPlan(id: id)
        }
        #expect(rig.coordinator.engine.state == .idle)
    }

    @Test("Plan that lost its focus configuration is not startable")
    func planNotStartable() throws {
        let rig = try makeAppIntentRig()
        // A plan whose focus items reference no configuration is incomplete.
        let plan = try insertPlan(rig.container, configuration: nil)
        #expect(throws: TimeFrameIntentError.planNotStartable) {
            try rig.actions.startPlan(id: plan.id)
        }
    }

    @Test("Starting a plan while active reports sessionAlreadyRunning")
    func activeConflict() throws {
        let rig = try makeAppIntentRig(focus: 600)
        let plan = try insertPlan(rig.container, configuration: rig.config)
        try rig.coordinator.startSession(configuration: rig.config)
        #expect(throws: TimeFrameIntentError.sessionAlreadyRunning) {
            try rig.actions.startPlan(id: plan.id)
        }
    }
}

@MainActor
@Suite("Start Time Frame intent")
struct StartTimeFrameIntentTests {

    @Test("Named configuration starts with the given task and count")
    func namedConfiguration() throws {
        let rig = try makeAppIntentRig(focus: 600, total: 4)
        let outcome = try rig.actions.startSession(
            configurationID: rig.config.id, taskName: "Deep Focus", totalSessions: 2)
        #expect(outcome.configurationName == "Deep Work")
        #expect(outcome.sessionCount == 2) // override applied to this run only
        #expect(rig.coordinator.activeSession?.taskName == "Deep Focus")
        #expect(rig.coordinator.engine.totalFocusSessions == 2)
        // The saved configuration keeps its own default (never mutated by the override).
        #expect(rig.config.defaultTotalSessions == 4)
    }

    @Test("No configuration falls back to the default configuration")
    func defaultFallback() throws {
        let rig = try makeAppIntentRig(focus: 600, seedDefault: true)
        let outcome = try rig.actions.startSession(configurationID: nil, taskName: nil, totalSessions: nil)
        #expect(outcome.configurationName == "Deep Work")
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("Unknown configuration id reports configurationUnavailable")
    func unknownConfiguration() throws {
        let rig = try makeAppIntentRig()
        #expect(throws: TimeFrameIntentError.configurationUnavailable) {
            try rig.actions.startSession(configurationID: UUID(), taskName: nil, totalSessions: nil)
        }
    }

    @Test("No default configuration to fall back on reports configurationUnavailable")
    func noDefault() throws {
        // Build a rig with a non-default configuration, then clear defaults so none remain.
        let rig = try makeAppIntentRig(seedDefault: false)
        #expect(throws: TimeFrameIntentError.configurationUnavailable) {
            try rig.actions.startSession(configurationID: nil, taskName: nil, totalSessions: nil)
        }
    }

    @Test("Starting while active reports sessionAlreadyRunning")
    func activeConflict() throws {
        let rig = try makeAppIntentRig(focus: 600)
        try rig.coordinator.startSession(configuration: rig.config)
        #expect(throws: TimeFrameIntentError.sessionAlreadyRunning) {
            try rig.actions.startSession(configurationID: rig.config.id, taskName: nil, totalSessions: nil)
        }
    }
}
