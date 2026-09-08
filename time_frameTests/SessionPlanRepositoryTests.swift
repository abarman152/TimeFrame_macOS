//
//  SessionPlanRepositoryTests.swift
//  time_frameTests
//
//  Create / fetch / update / delete / duplicate for SessionPlan, plus relationship
//  integrity: configuration deletion nullifies (never deletes) plans, plan deletion
//  never deletes configurations, and ordering persists. Deterministic in-memory
//  store; the container is kept alive for each test.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Session plan repository")
struct SessionPlanRepositoryTests {

    @Test("Create inserts a plan with ordered items and fresh timestamps")
    func create() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 3000)
        let repo = makePlanRepository(container)

        let plan = try repo.create(simplePlanDraft(config))
        #expect(plan.name == "Research Deep Work")
        #expect(plan.taskName == "Research Quantum IDS")
        #expect(plan.orderedItems.map(\.order) == [0, 1, 2])
        #expect(plan.orderedItems.map(\.phase) == [.focus, .shortBreak, .focus])
        #expect(plan.focusCount == 2)
        #expect(try repo.count() == 1)
    }

    @Test("Create rejects an invalid draft")
    func createRejectsInvalid() throws {
        let container = try makeInMemoryContainer()
        let repo = makePlanRepository(container)
        #expect(throws: PersistenceError.self) {
            try repo.create(SessionPlanDraft(name: "", taskName: "", items: []))
        }
        #expect(try repo.count() == 0)
    }

    @Test("Fetch returns all plans, most recently updated first")
    func fetchAll() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 3000)
        let repo = makePlanRepository(container)

        let first = try repo.create(simplePlanDraft(config, name: "First"))
        let second = try repo.create(simplePlanDraft(config, name: "Second"))
        // Bump the first so it becomes most-recent.
        try repo.update(first, with: first.draft)

        let all = try repo.all()
        #expect(all.count == 2)
        #expect(all.first?.id == first.id)
        #expect(all.contains { $0.id == second.id })
    }

    @Test("Update edits values, reorders items, and preserves identities")
    func update() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 3000)
        let repo = makePlanRepository(container)
        let plan = try repo.create(simplePlanDraft(config))
        let originalIDs = plan.orderedItems.map(\.id)

        // Reverse the items and rename; ids are preserved through the draft.
        var draft = plan.draft
        draft.name = "Renamed"
        draft.items.reverse()
        try repo.update(plan, with: draft)

        #expect(plan.name == "Renamed")
        #expect(plan.orderedItems.map(\.order) == [0, 1, 2])
        // Same three items, now in reversed order — no duplicates created.
        #expect(plan.items.count == 3)
        #expect(Set(plan.items.map(\.id)) == Set(originalIDs))
        #expect(plan.orderedItems.first?.id == originalIDs.last)
    }

    @Test("Update can add and remove items without duplicating rows")
    func updateAddsAndRemoves() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 3000)
        let repo = makePlanRepository(container)
        let plan = try repo.create(simplePlanDraft(config))

        var draft = plan.draft
        draft.items.removeLast()                       // drop the trailing focus
        draft.items.append(focusItem(config, order: 99)) // add a fresh focus
        try repo.update(plan, with: draft)

        #expect(plan.items.count == 3)
        #expect(plan.orderedItems.map(\.order) == [0, 1, 2])
    }

    @Test("Delete removes a plan and its items but keeps the configuration")
    func delete() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 3000)
        let repo = makePlanRepository(container)
        let configRepo = makeConfigRepository(container)
        let plan = try repo.create(simplePlanDraft(config))

        try repo.delete(plan)
        #expect(try repo.count() == 0)
        // The configuration is untouched.
        #expect(try configRepo.count() == 1)
    }

    @Test("Duplicate creates an independent copy with new identities")
    func duplicate() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 3000)
        let repo = makePlanRepository(container)
        let plan = try repo.create(simplePlanDraft(config))

        let copy = try repo.duplicate(plan)
        #expect(copy.id != plan.id)
        #expect(copy.name == "Research Deep Work Copy")
        #expect(copy.items.count == plan.items.count)
        #expect(Set(copy.items.map(\.id)).isDisjoint(with: Set(plan.items.map(\.id))))

        // Editing the copy does not affect the original.
        var draft = copy.draft
        draft.items.removeAll()
        draft.items = [focusItem(config)]
        try repo.update(copy, with: draft)
        #expect(copy.items.count == 1)
        #expect(plan.items.count == 3)
    }

    @Test("Deleting a configuration nullifies its plan items, keeping the plan")
    func configDeletionNullifies() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 3000)
        let repo = makePlanRepository(container)
        let configRepo = makeConfigRepository(container)
        let plan = try repo.create(simplePlanDraft(config))

        try configRepo.delete(config)

        #expect(try repo.count() == 1)                       // plan survives
        let focus = plan.orderedItems.first { $0.isFocus }
        #expect(focus?.configuration == nil)                 // reference nullified
        #expect(focus?.configurationName == "Test")          // frozen name retained
        #expect(plan.isStartable == false)                   // incomplete until re-assigned
        #expect(focus?.displayConfigurationName == "Test")
    }

    @Test("A configuration reports how many plans reference it")
    func configReportsPlanUsage() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 3000)
        let repo = makePlanRepository(container)
        _ = try repo.create(simplePlanDraft(config))

        // The inverse relationship surfaces the focus items that reference the config.
        #expect(config.planItems.count == 2)
    }

    @Test("Ordering persists on refetch within the store")
    func orderingPersists() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 3000)
        let repo = makePlanRepository(container)
        let created = try repo.create(simplePlanDraft(config))
        let createdID = created.id

        let refetched = try #require(try repo.plan(with: createdID))
        #expect(refetched.orderedItems.map(\.order) == [0, 1, 2])
        #expect(refetched.orderedItems.map(\.phase) == [.focus, .shortBreak, .focus])
    }

    @Test("A plan can mix multiple configurations")
    func multipleConfigurations() throws {
        let container = try makeInMemoryContainer()
        let research = try insertConfiguration(container, focus: 3000, isDefault: true)
        let writing = try insertConfiguration(container, focus: 2700, isDefault: false)
        let repo = makePlanRepository(container)

        let draft = SessionPlanDraft(name: "Mixed", taskName: "Deep work", items: [
            focusItem(research, order: 0),
            breakItem(.shortBreak, duration: 600, order: 1),
            focusItem(writing, order: 2)
        ])
        let plan = try repo.create(draft)

        let focuses = plan.orderedItems.filter(\.isFocus)
        #expect(focuses.count == 2)
        #expect(focuses[0].configuration?.id == research.id)
        #expect(focuses[1].configuration?.id == writing.id)
    }
}
