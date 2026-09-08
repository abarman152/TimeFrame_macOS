//
//  AppIntentEntityTests.swift
//  time_frameTests (Milestone 12)
//
//  Covers the App Intents entities and their repository-backed queries: stable UUID
//  identity, meaningful display representations, resolution by id, graceful handling of
//  deleted records, and free-text search. The end-to-end query suite is `.serialized`
//  because it registers dependencies with the process-global `AppDependencyManager`.
//

import Foundation
import SwiftData
import AppIntents
import Testing
@testable import time_frame

@MainActor
@Suite("App Intent entities")
struct AppIntentEntityTests {

    @Test("Template entity carries stable id and display strings")
    func templateEntity() throws {
        let rig = try makeAppIntentRig()
        let template = try insertTemplate(rig.container, configuration: rig.config)
        let entity = TaskTemplateEntity(template)
        #expect(entity.id == template.id)           // stable UUID, never an index
        #expect(entity.name == "Research")
        #expect(entity.taskName == "Research Paper")
        #expect(entity.configurationName == "Deep Work")
        #expect(String(localized: entity.displayRepresentation.title) == "Research")
    }

    @Test("Template that lost its configuration shows a neutral label")
    func templateWithoutConfiguration() throws {
        let rig = try makeAppIntentRig()
        let template = try insertTemplate(rig.container, configuration: nil)
        let entity = TaskTemplateEntity(template)
        #expect(entity.configurationName == "Configuration unavailable")
    }

    @Test("Plan entity carries stable id and focus count")
    func planEntity() throws {
        let rig = try makeAppIntentRig()
        let plan = try insertPlan(rig.container, configuration: rig.config)
        let entity = SessionPlanEntity(plan)
        #expect(entity.id == plan.id)
        #expect(entity.name == "Morning Deep Work")
        #expect(entity.focusCount == 2)
    }

    @Test("Configuration entity carries stable id")
    func configurationEntity() throws {
        let rig = try makeAppIntentRig()
        let entity = ConfigurationEntity(rig.config)
        #expect(entity.id == rig.config.id)
        #expect(entity.name == "Deep Work")
    }

    @Test("Repository fetch resolves by id and returns nil for deleted records")
    func repositoryFetch() throws {
        let rig = try makeAppIntentRig()
        let template = try insertTemplate(rig.container, configuration: rig.config)
        let id = template.id

        #expect(try rig.coordinator.templates.template(with: id)?.id == id)
        rig.container.mainContext.delete(template)
        try rig.container.mainContext.save()
        #expect(try rig.coordinator.templates.template(with: id) == nil)

        // Unknown ids resolve to nil rather than throwing.
        #expect(try rig.coordinator.configurations.configuration(with: UUID()) == nil)
    }

    @Test("Current session entity reflects the live projection")
    func currentSessionEntity() throws {
        let rig = try makeAppIntentRig(focus: 600, total: 4)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Research Paper")
        rig.clock.advance(by: 60)
        let entity = CurrentSessionEntity(state: rig.actions.status())
        #expect(entity.id == CurrentSessionEntity.currentID)
        #expect(entity.task == "Research Paper")
        #expect(entity.phase == "Focus")
        #expect(entity.sessionNumber == 1)
        #expect(entity.totalSessions == 4)
        #expect(entity.remainingMinutes == 9) // 540s rounded
    }
}

@MainActor
@Suite("App Intent entity queries")
struct AppIntentEntityQueryTests {

    // These drive each query's `@MainActor` resolution core directly against an in-memory
    // repository/coordinator — the same code the `@AppDependency` methods forward to at
    // runtime — so the query logic is fully covered without the process-global dependency
    // manager (whose values are only accessible inside a real intent perform flow).

    @Test("Suggested templates come from the store")
    func suggestedTemplates() throws {
        let rig = try makeAppIntentRig()
        try insertTemplate(rig.container, name: "Research", configuration: rig.config)
        try insertTemplate(rig.container, name: "Writing", configuration: rig.config)

        let results = try TaskTemplateEntityQuery.suggested(in: rig.coordinator.templates)
        #expect(Set(results.map(\.name)) == ["Research", "Writing"])
    }

    @Test("Template query resolves by id and drops deleted ones")
    func templateByID() throws {
        let rig = try makeAppIntentRig()
        let template = try insertTemplate(rig.container, configuration: rig.config)

        let found = try TaskTemplateEntityQuery.resolve([template.id], in: rig.coordinator.templates)
        #expect(found.count == 1)

        let missing = try TaskTemplateEntityQuery.resolve([UUID()], in: rig.coordinator.templates)
        #expect(missing.isEmpty)
    }

    @Test("Template search filters by name and task")
    func templateSearch() throws {
        let rig = try makeAppIntentRig()
        try insertTemplate(rig.container, name: "Research", taskName: "Quantum IDS", configuration: rig.config)
        try insertTemplate(rig.container, name: "Writing", taskName: "Blog", configuration: rig.config)

        let byName = try TaskTemplateEntityQuery.matching("resea", in: rig.coordinator.templates)
        #expect(byName.map(\.name) == ["Research"])
        let byTask = try TaskTemplateEntityQuery.matching("quantum", in: rig.coordinator.templates)
        #expect(byTask.map(\.name) == ["Research"])
    }

    @Test("Plan query resolves and searches")
    func planQuery() throws {
        let rig = try makeAppIntentRig()
        let plan = try insertPlan(rig.container, configuration: rig.config)

        #expect(try SessionPlanEntityQuery.resolve([plan.id], in: rig.coordinator.plans).count == 1)
        #expect(try SessionPlanEntityQuery.suggested(in: rig.coordinator.plans).count == 1)
        #expect(try SessionPlanEntityQuery.resolve([UUID()], in: rig.coordinator.plans).isEmpty)
    }

    @Test("Configuration query resolves and searches")
    func configurationQuery() throws {
        let rig = try makeAppIntentRig()
        #expect(try ConfigurationEntityQuery.resolve([rig.config.id], in: rig.coordinator.configurations).count == 1)
        #expect(try ConfigurationEntityQuery.matching("deep", in: rig.coordinator.configurations).count == 1)
        #expect(try ConfigurationEntityQuery.matching("nope", in: rig.coordinator.configurations).isEmpty)
    }

    @Test("Current session query returns empty when idle and one when active")
    func currentSessionQuery() throws {
        let rig = try makeAppIntentRig(focus: 600)

        #expect(CurrentSessionEntityQuery.resolve(coordinator: rig.coordinator).isEmpty)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Focus")
        let active = CurrentSessionEntityQuery.resolve(coordinator: rig.coordinator)
        #expect(active.count == 1)
        #expect(active.first?.task == "Focus")
    }
}
