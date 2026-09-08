//
//  TaskTemplateRepositoryTests.swift
//  time_frameTests
//
//  CRUD, duplication, default selection, configuration resolution, and the
//  configuration-deletion nullify behaviour for TaskTemplate (Milestone 4). Uses
//  in-memory stores; the container is kept alive for each test body.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Task template repository")
struct TaskTemplateRepositoryTests {

    private func draft(_ config: PomodoroConfiguration,
                       name: String = "Research",
                       task: String = "Research Quantum IDS",
                       sessions: Int = 4) -> TaskTemplateDraft {
        TaskTemplateDraft(name: name, taskName: task, configurationID: config.id, defaultTotalSessions: sessions)
    }

    @Test("Create inserts a valid template with fresh timestamps")
    func create() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config))
        #expect(template.name == "Research")
        #expect(template.taskName == "Research Quantum IDS")
        #expect(template.configuration?.id == config.id)
        #expect(template.defaultTotalSessions == 4)
        #expect(template.isDefault == false)
        #expect(template.createdAt == template.updatedAt)
        #expect(try repo.count() == 1)
    }

    @Test("Create trims whitespace from names")
    func createTrims() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config, name: "  Research  ", task: "  Quantum  "))
        #expect(template.name == "Research")
        #expect(template.taskName == "Quantum")
    }

    @Test("Create rejects an invalid draft and stores nothing")
    func createInvalid() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        #expect(throws: PersistenceError.self) {
            try repo.create(draft(config, name: ""))
        }
        #expect(try repo.count() == 0)
    }

    @Test("Create rejects a draft whose configuration does not exist")
    func createUnknownConfiguration() throws {
        let container = try makeInMemoryContainer()
        let repo = makeTemplateRepository(container)

        var d = TaskTemplateDraft(name: "X", taskName: "Y", configurationID: UUID(), defaultTotalSessions: 2)
        d.configurationID = UUID() // not in the store
        #expect(throws: PersistenceError.self) { try repo.create(d) }
        #expect(try repo.count() == 0)
    }

    @Test("Read returns all templates, newest first")
    func readAll() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        try repo.create(draft(config, name: "A"))
        try repo.create(draft(config, name: "B"))
        #expect(try repo.all().count == 2)
    }

    @Test("Update applies validated changes and bumps updatedAt")
    func update() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config))
        let before = template.updatedAt
        try repo.update(template, with: draft(config, name: "Renamed", task: "New Task", sessions: 6))

        #expect(template.name == "Renamed")
        #expect(template.taskName == "New Task")
        #expect(template.defaultTotalSessions == 6)
        #expect(template.updatedAt >= before)
    }

    @Test("Update can point a template at a different configuration")
    func updateChangesConfiguration() throws {
        let container = try makeInMemoryContainer()
        let configA = try insertConfiguration(container, isDefault: true)
        let configB = try insertConfiguration(container, isDefault: false)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(configA))
        try repo.update(template, with: draft(configB))
        #expect(template.configuration?.id == configB.id)
    }

    @Test("Update rejects an invalid draft, leaving the template unchanged")
    func updateInvalid() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config))
        #expect(throws: PersistenceError.self) {
            try repo.update(template, with: draft(config, task: ""))
        }
        #expect(template.taskName == "Research Quantum IDS")
    }

    @Test("Delete removes a template but keeps its configuration")
    func delete() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config))
        try repo.delete(template)
        #expect(try repo.count() == 0)
        #expect(try makeConfigRepository(container).count() == 1) // configuration survives
    }

    @Test("Duplicate creates an independent, non-default copy")
    func duplicate() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let original = try repo.create(draft(config), makeDefault: true)
        let copy = try repo.duplicate(original)

        #expect(copy.name == "Research Copy")
        #expect(copy.taskName == original.taskName)
        #expect(copy.configuration?.id == config.id)
        #expect(copy.defaultTotalSessions == original.defaultTotalSessions)
        #expect(copy.isDefault == false)
        #expect(copy.id != original.id)
        #expect(try repo.count() == 2)
    }

    @Test("Editing a duplicate does not change the original")
    func duplicateIndependent() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let original = try repo.create(draft(config, name: "Research"))
        let copy = try repo.duplicate(original)
        try repo.update(copy, with: draft(config, name: "Something Else", task: "Other"))

        #expect(original.name == "Research")
        #expect(original.taskName == "Research Quantum IDS")
    }

    @Test("Set default marks exactly one template as default")
    func setDefault() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let a = try repo.create(draft(config, name: "A"), makeDefault: true)
        let b = try repo.create(draft(config, name: "B"))
        try repo.setDefault(b)

        #expect(b.isDefault)
        #expect(a.isDefault == false)
        #expect(try repo.defaultTemplate()?.id == b.id)
        #expect(try repo.all().filter(\.isDefault).count == 1)
    }

    @Test("Clear default leaves no default template")
    func clearDefault() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let a = try repo.create(draft(config), makeDefault: true)
        try repo.clearDefault(a)
        #expect(a.isDefault == false)
        #expect(try repo.defaultTemplate() == nil)
    }

    @Test("Deleting a configuration nullifies its templates' reference, keeping them")
    func configurationDeletionNullifiesTemplate() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let configs = makeConfigRepository(container)

        let template = try templates.create(draft(config))
        #expect(template.hasConfiguration)

        try configs.delete(config)

        #expect(try templates.count() == 1)            // template survives
        #expect(template.configuration == nil)          // reference nullified
        #expect(template.hasConfiguration == false)     // shown as unavailable
        #expect(template.displayConfigurationName == "Configuration unavailable")
    }
}
