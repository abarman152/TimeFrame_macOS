//
//  QuickStartProjectionTests.swift
//  time_frameTests (Milestone 28)
//
//  Quick Start is a read-only projection of the authoritative repositories, not a store
//  (ADR-104). These tests drive the pure projection layer: what a pinned Template or Plan
//  looks like as a row, how the list is ordered, what happens when the underlying item is
//  renamed, edited, made unstartable, or deleted, and the exact accessibility phrasing.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("Quick Start projection")
@MainActor
struct QuickStartProjectionTests {

    @Test("An empty library projects an empty Quick Start list")
    func emptyList() throws {
        let container = try makeInMemoryContainer()
        let items = QuickStartProvider.items(templates: makeTemplateRepository(container),
                                             plans: makePlanRepository(container))
        #expect(items.isEmpty)
        _ = container
    }

    @Test("Only pinned items appear")
    func onlyPinnedItemsAppear() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let pinned = try templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship", configurationID: config.id))
        _ = try templates.create(
            TaskTemplateDraft(name: "Unpinned", taskName: "Other", configurationID: config.id))
        try templates.setPinned(pinned, true)

        let items = QuickStartProvider.items(templates: templates, plans: makePlanRepository(container))
        #expect(items.map(\.name) == ["Deep Work"])
        #expect(items.map(\.kind) == [.template])
        _ = container
    }

    @Test("A pinned template's row carries its icon and a focus/break subtitle")
    func templateRowContents() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, name: "Deep Work",
                                             focus: 50 * 60, short: 10 * 60)
        let templates = makeTemplateRepository(container)
        let template = try templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship",
                              configurationID: config.id, icon: .laptop))
        try templates.setPinned(template, true)

        let item = try #require(QuickStartProvider.items(
            templates: templates, plans: makePlanRepository(container)).first)
        #expect(item.id == template.id)
        #expect(item.kind == .template)
        #expect(item.icon == .laptop)
        #expect(item.subtitle == "50 min focus · 10 min break")
        #expect(item.isStartable)
        _ = container
    }

    @Test("A pinned plan's row carries its icon and a focus-count/duration subtitle")
    func planRowContents() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 1500, short: 300)
        let plans = makePlanRepository(container)
        var draft = simplePlanDraft(config, name: "Weekly Focus")
        draft.icon = .target
        let plan = try plans.create(draft)
        try plans.setPinned(plan, true)

        let item = try #require(QuickStartProvider.items(
            templates: makeTemplateRepository(container), plans: plans).first)
        #expect(item.kind == .plan)
        #expect(item.icon == .target)
        #expect(item.subtitle.hasPrefix("2 focus sessions · "))
        #expect(item.isStartable)
        _ = container
    }

    @Test("A rename is reflected on the next projection; the pin and identity survive")
    func renameFlowsThrough() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let template = try templates.create(
            TaskTemplateDraft(name: "Old Name", taskName: "Ship", configurationID: config.id))
        try templates.setPinned(template, true)
        let id = template.id

        try templates.update(template, with: TaskTemplateDraft(
            name: "New Name", taskName: "Ship", configurationID: config.id, icon: .bolt))

        let item = try #require(QuickStartProvider.items(
            templates: templates, plans: makePlanRepository(container)).first)
        #expect(item.id == id, "The row is keyed by the stable id, not the name")
        #expect(item.name == "New Name")
        #expect(item.icon == .bolt)
        _ = container
    }

    @Test("A deleted pinned item simply stops appearing")
    func deleteRemovesRow() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let template = try templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship", configurationID: config.id))
        try templates.setPinned(template, true)
        try templates.delete(template)

        #expect(QuickStartProvider.items(templates: templates,
                                         plans: makePlanRepository(container)).isEmpty)
        _ = container
    }

    @Test("An item whose configuration was deleted is still listed, but not startable")
    func unstartableItemIsListedAndExplained() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let template = try templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship", configurationID: config.id))
        try templates.setPinned(template, true)

        // Nullify rule: deleting the configuration clears the reference, keeps the template.
        container.mainContext.delete(config)
        try container.mainContext.save()

        let item = try #require(QuickStartProvider.items(
            templates: templates, plans: makePlanRepository(container)).first)
        #expect(item.isStartable == false)
        #expect(item.subtitle == "Needs a configuration")
        #expect(item.unavailableReason != nil, "A disabled control must explain itself in words")
        _ = container
    }

    @Test("Templates and plans are interleaved by pin date, oldest first")
    func mixedOrdering() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let templates = makeTemplateRepository(container)
        let plans = makePlanRepository(container)

        let template = try templates.create(
            TaskTemplateDraft(name: "Template", taskName: "T", configurationID: config.id))
        let plan = try plans.create(simplePlanDraft(config, name: "Plan"))

        try plans.setPinned(plan, true, at: Date(timeIntervalSince1970: 100))
        try templates.setPinned(template, true, at: Date(timeIntervalSince1970: 200))

        let items = QuickStartProvider.items(templates: templates, plans: plans)
        #expect(items.map(\.kind) == [.plan, .template])
        _ = container
    }

    // MARK: Pure ordering and phrasing

    @Test("Ordering is total and deterministic, even without pin dates")
    func orderingIsDeterministic() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        // A recorded pin date always sorts before a missing one.
        #expect(QuickStartOrder.isOrderedBefore((Date(timeIntervalSince1970: 1), "Z", a),
                                                (nil, "A", b)))
        #expect(!QuickStartOrder.isOrderedBefore((nil, "A", a),
                                                 (Date(timeIntervalSince1970: 1), "Z", b)))
        // Equal dates fall back to name, then id — never an unstable comparison.
        let same = Date(timeIntervalSince1970: 5)
        #expect(QuickStartOrder.isOrderedBefore((same, "Alpha", a), (same, "Beta", b)))
        #expect(QuickStartOrder.isOrderedBefore((same, "Same", a), (same, "Same", b)))
        #expect(!QuickStartOrder.isOrderedBefore((same, "Same", b), (same, "Same", b)))
    }

    @Test("A row's accessibility label names the item, its kind, and its summary")
    func rowAccessibilityPhrasing() {
        let item = QuickStartItem(id: UUID(), kind: .template, name: "Deep Work",
                                  subtitle: "50 min focus · 10 min break",
                                  icon: .laptop, isStartable: true, pinnedAt: nil)
        #expect(item.startAccessibilityLabel == "Start Deep Work")
        #expect(item.accessibilityLabel == "Deep Work, Template, 50 min focus · 10 min break")
        #expect(item.unavailableReason == nil)

        let plan = QuickStartItem(id: UUID(), kind: .plan, name: "Weekly Focus",
                                  subtitle: "4 focus sessions · 3h",
                                  icon: .target, isStartable: false, pinnedAt: nil)
        #expect(plan.startAccessibilityLabel == "Start Weekly Focus")
        #expect(plan.accessibilityLabel.contains("Plan"))
        #expect(plan.unavailableReason == "Needs a configuration before it can start")
    }

    @Test("An unnamed item still has a usable name and spoken label")
    func unnamedItemDegradesGracefully() {
        let item = QuickStartItem(id: UUID(), kind: .plan, name: "   ", subtitle: "x",
                                  icon: .list, isStartable: true, pinnedAt: nil)
        #expect(item.displayName == "Untitled Plan")
        #expect(item.startAccessibilityLabel == "Start Untitled Plan")
    }

    // MARK: Pin control phrasing (shared by every surface)

    @Test("The pin control says and speaks the same thing everywhere")
    func pinPhrasing() {
        #expect(QuickStartPinPresentation.title(isPinned: false) == "Pin to Quick Start")
        #expect(QuickStartPinPresentation.title(isPinned: true) == "Pinned to Quick Start")
        #expect(QuickStartPinPresentation.menuTitle(isPinned: false) == "Pin to Quick Start")
        #expect(QuickStartPinPresentation.menuTitle(isPinned: true) == "Remove from Quick Start")
        #expect(QuickStartPinPresentation.symbolName(isPinned: false) == "pin")
        #expect(QuickStartPinPresentation.symbolName(isPinned: true) == "pin.fill")
        #expect(QuickStartPinPresentation.accessibilityLabel(name: "Deep Work", isPinned: false)
                == "Pin Deep Work to Quick Start")
        #expect(QuickStartPinPresentation.accessibilityLabel(name: "Deep Work", isPinned: true)
                == "Remove Deep Work from Quick Start")
        #expect(QuickStartPinPresentation.accessibilityLabel(name: "  ", isPinned: false)
                == "Pin this item to Quick Start")
        #expect(!QuickStartPinPresentation.accessibilityHint(isPinned: true).isEmpty)
        #expect(!QuickStartPinPresentation.accessibilityHint(isPinned: false).isEmpty)
    }
}
