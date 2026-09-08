//
//  QuickStartPinningTests.swift
//  time_frameTests (Milestone 28)
//
//  Pinning is stored on the item itself, keyed by its stable `id` (ADR-104). These tests
//  hold the consequences of that decision — the properties a side table would have got wrong:
//
//   • renaming a pinned item keeps the pin (identity is the id, never the name);
//   • deleting a pinned item removes it from Quick Start with no orphan left behind;
//   • editing an item never silently changes what the user pinned;
//   • duplicating copies the icon but not the pin;
//   • pin/unpin is idempotent and does not reshuffle the order.
//
//  They also cover icon save/load for both Templates and Plans, including the fallback for a
//  stored value the catalog does not recognise.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("Quick Start pinning and icons")
@MainActor
struct QuickStartPinningTests {

    // MARK: Templates — icons

    @Test("A template saves and loads its chosen icon")
    func templateIconRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)

        let template = try templates.create(
            TaskTemplateDraft(name: "Research", taskName: "Papers",
                              configurationID: config.id, icon: .laptop))

        #expect(template.iconIdentifier == TimeFrameIconIdentifier.laptop.rawValue)
        #expect(template.icon == .laptop)

        try templates.update(template, with: TaskTemplateDraft(
            name: "Research", taskName: "Papers", configurationID: config.id, icon: .graduationCap))
        let reloaded = try #require(try templates.template(with: template.id))
        #expect(reloaded.icon == .graduationCap)
        _ = container
    }

    @Test("A template with no chosen icon uses the template default")
    func templateDefaultIcon() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)

        let template = try templates.create(
            TaskTemplateDraft(name: "Research", taskName: "Papers", configurationID: config.id))
        #expect(template.icon == .templateDefault)
        _ = container
    }

    @Test("A template with an unrecognised stored icon falls back, never renders raw data")
    func templateInvalidIconFallsBack() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let template = try templates.create(
            TaskTemplateDraft(name: "Research", taskName: "Papers", configurationID: config.id))

        // Simulates a corrupt row, a downgrade, or a value written by a newer build.
        template.iconIdentifier = "some.symbol.from.the.future"
        try container.mainContext.save()

        #expect(template.icon == .templateDefault)
        #expect(!template.icon.symbolName.isEmpty)
        _ = container
    }

    // MARK: Templates — pinning

    @Test("Pinning and unpinning a template updates its state and pin date")
    func pinAndUnpinTemplate() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let template = try templates.create(
            TaskTemplateDraft(name: "Research", taskName: "Papers", configurationID: config.id))

        #expect(template.isPinned == false)
        #expect(template.pinnedAt == nil)

        let pinnedAt = Date(timeIntervalSince1970: 1_000)
        try templates.setPinned(template, true, at: pinnedAt)
        #expect(template.isPinned)
        #expect(template.pinnedAt == pinnedAt)
        #expect(try templates.pinned().map(\.id) == [template.id])

        try templates.setPinned(template, false)
        #expect(template.isPinned == false)
        #expect(template.pinnedAt == nil)
        #expect(try templates.pinned().isEmpty)
        _ = container
    }

    @Test("Re-pinning an already pinned template keeps its original pin date")
    func pinIsIdempotent() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let template = try templates.create(
            TaskTemplateDraft(name: "Research", taskName: "Papers", configurationID: config.id))

        let first = Date(timeIntervalSince1970: 1_000)
        try templates.setPinned(template, true, at: first)
        try templates.setPinned(template, true, at: Date(timeIntervalSince1970: 9_999))
        #expect(template.pinnedAt == first, "Re-pinning must not reshuffle Quick Start")
        _ = container
    }

    @Test("Renaming a pinned template preserves the pin (identity is the id, not the name)")
    func renamePreservesPin() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let template = try templates.create(
            TaskTemplateDraft(name: "Research", taskName: "Papers", configurationID: config.id))
        let pinnedAt = Date(timeIntervalSince1970: 1_000)
        try templates.setPinned(template, true, at: pinnedAt)
        let id = template.id

        try templates.update(template, with: TaskTemplateDraft(
            name: "Deep Research", taskName: "Papers", configurationID: config.id, icon: .brain))

        #expect(template.id == id)
        #expect(template.name == "Deep Research")
        #expect(template.isPinned, "An edit must never silently unpin an item")
        #expect(template.pinnedAt == pinnedAt)
        #expect(try templates.pinned().map(\.id) == [id])
        _ = container
    }

    @Test("Deleting a pinned template removes it from Quick Start, leaving nothing behind")
    func deleteRemovesFromQuickStart() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let keep = try templates.create(
            TaskTemplateDraft(name: "Keep", taskName: "A", configurationID: config.id))
        let doomed = try templates.create(
            TaskTemplateDraft(name: "Doomed", taskName: "B", configurationID: config.id))
        try templates.setPinned(keep, true, at: Date(timeIntervalSince1970: 1))
        try templates.setPinned(doomed, true, at: Date(timeIntervalSince1970: 2))
        #expect(try templates.pinned().count == 2)

        try templates.delete(doomed)

        let remaining = try templates.pinned()
        #expect(remaining.map(\.id) == [keep.id])
        #expect(try templates.all().count == 1)
        _ = container
    }

    @Test("Duplicating a template copies the icon but never the pin")
    func duplicateCopiesIconNotPin() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let original = try templates.create(
            TaskTemplateDraft(name: "Research", taskName: "Papers",
                              configurationID: config.id, icon: .briefcase))
        try templates.setPinned(original, true)

        let copy = try templates.duplicate(original)
        #expect(copy.icon == .briefcase)
        #expect(copy.isPinned == false)
        #expect(copy.pinnedAt == nil)
        #expect(try templates.pinned().map(\.id) == [original.id])
        _ = container
    }

    // MARK: Plans

    @Test("A plan saves and loads its chosen icon, and falls back for an unknown one")
    func planIconRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let plans = makePlanRepository(container)

        var draft = simplePlanDraft(config)
        draft.icon = .target
        let plan = try plans.create(draft)
        #expect(plan.icon == .target)
        #expect(plan.iconIdentifier == TimeFrameIconIdentifier.target.rawValue)

        var edited = plan.draft
        edited.icon = .chart
        try plans.update(plan, with: edited)
        #expect(plan.icon == .chart)

        plan.iconIdentifier = "not-in-the-catalog"
        try container.mainContext.save()
        #expect(plan.icon == .planDefault)
        _ = container
    }

    @Test("A plan with no chosen icon uses the plan default")
    func planDefaultIcon() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let plans = makePlanRepository(container)
        let plan = try plans.create(simplePlanDraft(config))
        #expect(plan.icon == .planDefault)
        _ = container
    }

    @Test("Pinning, renaming and deleting a plan behave exactly like a template")
    func planPinLifecycle() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let plans = makePlanRepository(container)
        let plan = try plans.create(simplePlanDraft(config, name: "Weekly Focus"))
        let pinnedAt = Date(timeIntervalSince1970: 500)

        try plans.setPinned(plan, true, at: pinnedAt)
        #expect(try plans.pinned().map(\.id) == [plan.id])

        var renamed = plan.draft
        renamed.name = "Weekly Deep Focus"
        try plans.update(plan, with: renamed)
        #expect(plan.name == "Weekly Deep Focus")
        #expect(plan.isPinned)
        #expect(plan.pinnedAt == pinnedAt)

        try plans.delete(plan)
        #expect(try plans.pinned().isEmpty)
        _ = container
    }

    @Test("Duplicating a plan copies the icon but never the pin")
    func planDuplicate() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let plans = makePlanRepository(container)
        var draft = simplePlanDraft(config)
        draft.icon = .flag
        let plan = try plans.create(draft)
        try plans.setPinned(plan, true)

        let copy = try plans.duplicate(plan)
        #expect(copy.icon == .flag)
        #expect(copy.isPinned == false)
        #expect(try plans.pinned().map(\.id) == [plan.id])
        _ = container
    }

    // MARK: Ordering

    @Test("Pinned items are listed oldest pin first, and a rename does not reorder them")
    func pinnedOrderIsStable() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let first = try templates.create(
            TaskTemplateDraft(name: "Zebra", taskName: "A", configurationID: config.id))
        let second = try templates.create(
            TaskTemplateDraft(name: "Alpha", taskName: "B", configurationID: config.id))

        try templates.setPinned(first, true, at: Date(timeIntervalSince1970: 100))
        try templates.setPinned(second, true, at: Date(timeIntervalSince1970: 200))
        #expect(try templates.pinned().map(\.name) == ["Zebra", "Alpha"])

        try templates.update(first, with: TaskTemplateDraft(
            name: "Omega", taskName: "A", configurationID: config.id))
        #expect(try templates.pinned().map(\.id) == [first.id, second.id])
        _ = container
    }

    // MARK: Change notification (event-driven refresh — ADR-105)

    @Test("Every template mutation fires the repository change hook")
    func templateMutationsNotify() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let counter = ChangeCounter()
        let templates = TaskTemplateRepository(context: container.mainContext) { counter.bump() }

        let template = try templates.create(
            TaskTemplateDraft(name: "Research", taskName: "Papers", configurationID: config.id))
        #expect(counter.count == 1)

        try templates.setPinned(template, true)
        #expect(counter.count == 2)

        try templates.update(template, with: TaskTemplateDraft(
            name: "Renamed", taskName: "Papers", configurationID: config.id))
        #expect(counter.count == 3)

        try templates.duplicate(template)
        #expect(counter.count == 4)

        try templates.delete(template)
        #expect(counter.count == 5)
        _ = container
    }

    @Test("Every plan mutation fires the repository change hook")
    func planMutationsNotify() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let counter = ChangeCounter()
        let plans = SessionPlanRepository(context: container.mainContext) { counter.bump() }

        let plan = try plans.create(simplePlanDraft(config))
        #expect(counter.count == 1)

        try plans.setPinned(plan, true)
        #expect(counter.count == 2)

        try plans.update(plan, with: plan.draft)
        #expect(counter.count == 3)

        try plans.duplicate(plan)
        #expect(counter.count == 4)

        try plans.delete(plan)
        #expect(counter.count == 5)
        _ = container
    }

    @Test("An unchanged pin state is a no-op and does not notify")
    func redundantPinDoesNotNotify() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let counter = ChangeCounter()
        let templates = TaskTemplateRepository(context: container.mainContext) { counter.bump() }
        let template = try templates.create(
            TaskTemplateDraft(name: "Research", taskName: "Papers", configurationID: config.id))
        counter.reset()

        try templates.setPinned(template, false)   // already unpinned
        #expect(counter.count == 0)
        _ = container
    }
}

/// Counts calls to a repository's neutral change hook.
@MainActor
final class ChangeCounter {
    private(set) var count = 0
    func bump() { count += 1 }
    func reset() { count = 0 }
}
