//
//  Milestone4ApplicationTests.swift
//  time_frameTests
//
//  Task Template behaviour: the template → SessionSetupPrefill → SessionCoordinator
//  → FocusSession workflow, independence of templates from historical sessions and
//  from configuration edits/deletes, per-run override isolation, and the lifecycle
//  of a template-started session. Deterministic (mock clock, in-memory store).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
private func makeTemplate(
    _ container: ModelContainer,
    configuration config: PomodoroConfiguration,
    name: String = "Research",
    task: String = "Research Quantum IDS",
    sessions: Int = 4
) throws -> TaskTemplate {
    let repo = makeTemplateRepository(container)
    return try repo.create(TaskTemplateDraft(
        name: name, taskName: task, configurationID: config.id, defaultTotalSessions: sessions))
}

/// Mirrors exactly what `SessionSetupView` does when the user presses Start after a
/// template prefill: it reads the prefill's values and calls the one existing
/// `startSession` path. No second session-start implementation exists.
@MainActor
@discardableResult
private func startFromTemplate(
    _ coordinator: SessionCoordinator,
    _ template: TaskTemplate,
    totalSessionsOverride: Int? = nil
) throws -> FocusSession? {
    let prefill = SessionSetupPrefill(template: template)
    guard let configuration = template.configuration else { return nil }
    return try coordinator.startSession(
        configuration: configuration,
        taskName: prefill.taskName,
        totalSessions: totalSessionsOverride ?? prefill.totalSessions
    )
}

@MainActor
@Suite("Task template model")
struct TaskTemplateModelTests {

    @Test("A template keeps its own name distinct from the task name")
    func nameVsTaskName() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let template = try makeTemplate(container, configuration: config, name: "Research", task: "Research Quantum IDS")
        #expect(template.name == "Research")
        #expect(template.taskName == "Research Quantum IDS")
        #expect(template.name != template.taskName)
    }

    @Test("A template with a configuration is complete")
    func hasConfiguration() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let template = try makeTemplate(container, configuration: config)
        #expect(template.hasConfiguration)
        #expect(template.displayConfigurationName == config.name)
    }
}

@MainActor
@Suite("Template populates session setup")
struct TemplateSessionSetupTests {

    @Test("A prefill copies the template's task, configuration, and session count")
    func prefillPopulatesFields() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let template = try makeTemplate(container, configuration: config, task: "Research Quantum IDS", sessions: 4)

        let prefill = SessionSetupPrefill(template: template)
        #expect(prefill.taskName == "Research Quantum IDS")
        #expect(prefill.configurationID == config.id)
        #expect(prefill.totalSessions == 4)
    }

    @Test("Starting from a template creates a normal FocusSession")
    func startCreatesSession() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 100, total: 4)
        let template = try makeTemplate(container, configuration: config, task: "Research Quantum IDS", sessions: 4)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try startFromTemplate(coordinator, template))
        #expect(session.taskName == "Research Quantum IDS")
        #expect(session.configurationName == config.name)
        #expect(coordinator.engine.totalFocusSessions == 4)
        #expect(coordinator.engine.state == .running)
        #expect(coordinator.activeSession?.id == session.id)
    }

    @Test("A per-run session-count override does not mutate the template")
    func overrideDoesNotMutateTemplate() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 100, total: 4)
        let template = try makeTemplate(container, configuration: config, sessions: 4)
        let coordinator = makeCoordinator(container, clock: clock)

        // Start with 6 sessions for this run only.
        _ = try #require(try startFromTemplate(coordinator, template, totalSessionsOverride: 6))
        #expect(coordinator.engine.totalFocusSessions == 6) // this run
        #expect(template.defaultTotalSessions == 4)         // template unchanged
    }
}

@MainActor
@Suite("Template independence from history")
struct TemplateIndependenceTests {

    @Test("Editing a template does not change an already-started session")
    func editTemplateDoesNotChangeSession() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 100)
        let template = try makeTemplate(container, configuration: config, task: "Research Quantum IDS")
        let coordinator = makeCoordinator(container, clock: clock)
        let repo = makeTemplateRepository(container)

        let session = try #require(try startFromTemplate(coordinator, template))
        #expect(session.taskName == "Research Quantum IDS")

        // Rename the template's task after the session started.
        try repo.update(template, with: TaskTemplateDraft(
            name: template.name, taskName: "New Research Task",
            configurationID: config.id, defaultTotalSessions: template.defaultTotalSessions))

        #expect(template.taskName == "New Research Task") // template changed
        #expect(session.taskName == "Research Quantum IDS") // session unchanged
    }

    @Test("Editing the configuration does not change an already-started session")
    func editConfigDoesNotChangeSession() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 10)
        let template = try makeTemplate(container, configuration: config)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try startFromTemplate(coordinator, template))
        #expect(coordinator.engine.currentPlannedDuration == 10)

        try coordinator.configurations.update(config, with: ConfigurationDraft(
            name: config.name, focusDuration: 60 * 60,
            shortBreakDuration: config.shortBreakDuration,
            longBreakDuration: config.longBreakDuration,
            sessionsBeforeLongBreak: config.sessionsBeforeLongBreak,
            totalSessions: config.defaultTotalSessions))

        #expect(config.focusDuration == 60 * 60)                   // config updated
        #expect(coordinator.engine.currentPlannedDuration == 10)   // run unchanged
        #expect(session.orderedIntervals[0].plannedDuration == 10) // persisted interval unchanged
    }

    @Test("Deleting a template does not delete its already-started session")
    func deleteTemplateKeepsSession() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 10)
        let template = try makeTemplate(container, configuration: config, task: "Research Quantum IDS")
        let coordinator = makeCoordinator(container, clock: clock)
        let repo = makeTemplateRepository(container)
        let sessions = makeSessionRepository(container)

        let session = try #require(try startFromTemplate(coordinator, template))
        try coordinator.stop() // finish the run so nothing is mid-flight

        try repo.delete(template)

        #expect(try repo.count() == 0)                       // template gone
        #expect(try sessions.allSessions().count == 1)       // session remains
        #expect(session.taskName == "Research Quantum IDS")  // history intact
    }

    @Test("A template whose configuration was deleted cannot start (no configuration)")
    func unavailableTemplateCannotStart() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)
        let template = try makeTemplate(container, configuration: config)
        let coordinator = makeCoordinator(container, clock: clock)

        try coordinator.configurations.delete(config)
        #expect(template.hasConfiguration == false)

        let session = try startFromTemplate(coordinator, template)
        #expect(session == nil)                       // start is a no-op without a configuration
        #expect(coordinator.engine.state == .idle)
    }
}

@MainActor
@Suite("Template-started session lifecycle")
struct TemplateSessionLifecycleTests {

    @Test("A template-started session can pause and resume")
    func pauseResume() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 100)
        let template = try makeTemplate(container, configuration: config)
        let coordinator = makeCoordinator(container, clock: clock)

        _ = try #require(try startFromTemplate(coordinator, template))
        clock.advance(by: 5)
        try coordinator.pause()
        #expect(coordinator.engine.state == .paused)
        try coordinator.resume()
        #expect(coordinator.engine.state == .running)
    }

    @Test("A template-started session can skip the current interval")
    func skip() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 100, short: 50, total: 2)
        let template = try makeTemplate(container, configuration: config, sessions: 2)
        let coordinator = makeCoordinator(container, clock: clock)

        _ = try #require(try startFromTemplate(coordinator, template))
        #expect(coordinator.engine.currentIndex == 0)
        try coordinator.skip()
        #expect(coordinator.engine.currentIndex == 1)
    }

    @Test("A template-started session runs to completion")
    func complete() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 10, short: 5, total: 1)
        let template = try makeTemplate(container, configuration: config, sessions: 1)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try startFromTemplate(coordinator, template))
        clock.advance(by: 10); try coordinator.tick() // focus completes → break runs
        clock.advance(by: 5); try coordinator.tick()  // break completes → session done

        #expect(coordinator.engine.state == .completed)
        #expect(session.status == .completed)
        #expect(session.completedFocusCount == 1)
    }
}
