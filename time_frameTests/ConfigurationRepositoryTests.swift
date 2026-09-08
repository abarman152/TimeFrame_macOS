//
//  ConfigurationRepositoryTests.swift
//  time_frameTests
//
//  CRUD, duplication, default selection, and idempotent seeding for
//  PomodoroConfiguration (Milestone 2). Uses in-memory stores.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Configuration repository")
struct ConfigurationRepositoryTests {

    @Test("Create inserts a valid configuration")
    func create() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        let config = try repo.create(ConfigurationDraft(name: "Deep Work"))
        #expect(config.name == "Deep Work")
        #expect(try repo.count() == 1)
    }

    @Test("Create rejects an invalid draft and stores nothing")
    func createInvalid() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        #expect(throws: PersistenceError.self) {
            try repo.create(ConfigurationDraft(name: "", focusDuration: -1))
        }
        #expect(try repo.count() == 0)
    }

    @Test("Read returns all configurations, newest first")
    func readAll() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        try repo.create(ConfigurationDraft(name: "A"))
        try repo.create(ConfigurationDraft(name: "B"))
        let all = try repo.all()
        #expect(all.count == 2)
    }

    @Test("Update applies validated changes and bumps modifiedAt")
    func update() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        let config = try repo.create(ConfigurationDraft(name: "A"))
        let before = config.modifiedAt
        try repo.update(config, with: ConfigurationDraft(name: "A2", focusDuration: 30 * 60))
        #expect(config.name == "A2")
        #expect(config.focusDuration == 30 * 60)
        #expect(config.modifiedAt >= before)
    }

    @Test("Update rejects invalid changes")
    func updateInvalid() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        let config = try repo.create(ConfigurationDraft(name: "A"))
        #expect(throws: PersistenceError.self) {
            try repo.update(config, with: ConfigurationDraft(name: "A", focusDuration: 0))
        }
        #expect(config.focusDuration == 25 * 60) // unchanged
    }

    @Test("Delete removes a configuration")
    func delete() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        let config = try repo.create(ConfigurationDraft(name: "A"))
        try repo.delete(config)
        #expect(try repo.count() == 0)
    }

    @Test("Duplicate creates an independent, non-default copy")
    func duplicate() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        let original = try repo.create(ConfigurationDraft(name: "A", focusDuration: 20 * 60), makeDefault: true)
        let copy = try repo.duplicate(original)
        #expect(copy.name == "Copy of A")
        #expect(copy.focusDuration == 20 * 60)
        #expect(copy.isDefault == false)
        #expect(copy.id != original.id)
        #expect(try repo.count() == 2)
    }

    @Test("Set default marks exactly one configuration as default")
    func setDefault() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        let a = try repo.create(ConfigurationDraft(name: "A"), makeDefault: true)
        let b = try repo.create(ConfigurationDraft(name: "B"))
        try repo.setDefault(b)
        #expect(b.isDefault)
        #expect(a.isDefault == false)
        #expect(try repo.defaultConfiguration()?.id == b.id)
        #expect(try repo.all().filter(\.isDefault).count == 1)
    }

    @Test("Seeding creates a default configuration on an empty store")
    func seedOnce() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        let seeded = try repo.seedDefaultIfNeeded()
        #expect(seeded != nil)
        #expect(seeded?.isDefault == true)
        #expect(try repo.count() == 1)
    }

    @Test("Seeding is idempotent — relaunch never duplicates the default")
    func seedIdempotent() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        try repo.seedDefaultIfNeeded()
        let second = try repo.seedDefaultIfNeeded() // simulate a relaunch
        #expect(second == nil)
        #expect(try repo.count() == 1)
    }

    @Test("Seeding does not overwrite existing user configurations")
    func seedRespectsExisting() throws {
        let container = try makeInMemoryContainer()
        let repo = makeConfigRepository(container)
        try repo.create(ConfigurationDraft(name: "Mine"))
        let seeded = try repo.seedDefaultIfNeeded()
        #expect(seeded == nil)
        #expect(try repo.count() == 1)
        #expect(try repo.all().first?.name == "Mine")
    }
}
