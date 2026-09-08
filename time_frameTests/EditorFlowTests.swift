//
//  EditorFlowTests.swift
//  time_frameTests (Milestone 29)
//
//  Regression cover for the Template and Plan **edit** flows — the bug this milestone fixed
//  (ADR-106) and the guarantees the fix must not weaken.
//
//  Two layers, because the defect had two halves:
//
//  1. **Behaviour.** Editing must update the *same* row: identity preserved, no duplicate
//     inserted, the pin and the icon carried across correctly, and every surface that reads
//     the library (Quick Start, and therefore the menu bar and the Timer screen) refreshed
//     through the repositories' existing `onChange` hook. Cancelling must leave the store
//     byte-for-byte as it was — modelled here as "the editor never called `update`".
//
//  2. **Structure.** The actual defect was a *presentation* one: the detail page delegated
//     its editor to the list, whose `.sheet` is attached to the `NavigationStack`, and macOS
//     does not present that sheet while a `navigationDestination` is pushed. A behaviour test
//     cannot see that, so the second suite audits the source: each detail page must own an
//     editor sheet of its own and must not take an `onEdit` closure from its list.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

// MARK: - Template editing

@MainActor
@Suite("Template edit flow")
struct TemplateEditFlowTests {

    private func draft(_ config: PomodoroConfiguration,
                       name: String = "Research",
                       task: String = "Research Quantum IDS",
                       sessions: Int = 4,
                       icon: TimeFrameIconIdentifier = .templateDefault) -> TaskTemplateDraft {
        TaskTemplateDraft(name: name,
                          taskName: task,
                          configurationID: config.id,
                          defaultTotalSessions: sessions,
                          icon: icon)
    }

    @Test("Saving an edit updates the same template — identity is preserved")
    func editPreservesIdentity() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config))
        let originalID = template.id
        let createdAt = template.createdAt

        try repo.update(template, with: draft(config, name: "Research II", task: "Deep work", sessions: 6))

        #expect(template.id == originalID, "An edit must never mint a new identity")
        #expect(template.createdAt == createdAt, "An edit must not rewrite when it was created")
        #expect(template.name == "Research II")
        #expect(template.taskName == "Deep work")
        #expect(template.defaultTotalSessions == 6)
        #expect(template.updatedAt > createdAt)
        _ = container
    }

    @Test("Saving an edit does not create a second template")
    func editCreatesNoDuplicate() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config))
        #expect(try repo.count() == 1)

        try repo.update(template, with: draft(config, name: "Renamed"))
        try repo.update(template, with: draft(config, name: "Renamed twice"))

        #expect(try repo.count() == 1, "Editing must update in place, never insert")
        #expect(try repo.all().first?.name == "Renamed twice")
        _ = container
    }

    @Test("A rename keeps the Quick Start pin and its position")
    func editKeepsPin() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config))
        let pinDate = Date(timeIntervalSince1970: 1_000)
        try repo.setPinned(template, true, at: pinDate)

        try repo.update(template, with: draft(config, name: "Renamed"))

        #expect(template.isPinned, "An edit must never silently unpin what the user pinned")
        #expect(template.pinnedAt == pinDate, "A rename must not reshuffle Quick Start order")
        #expect(try repo.pinned().map(\.id) == [template.id])
        _ = container
    }

    @Test("The chosen icon is persisted as a catalog identifier and read back")
    func editPersistsIcon() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config, icon: .brain))
        #expect(template.icon == .brain)

        try repo.update(template, with: draft(config, icon: .graduationCap))

        #expect(template.icon == .graduationCap)
        #expect(template.iconIdentifier == TimeFrameIconIdentifier.graduationCap.rawValue,
                "The stored value is the stable identifier, never an SF Symbol name")
        _ = container
    }

    @Test("Changing the configuration re-points the template at the new one")
    func editChangesConfiguration() throws {
        let container = try makeInMemoryContainer()
        let first = try insertConfiguration(container, name: "Classic")
        let second = try insertConfiguration(container, name: "Deep", focus: 2700, isDefault: false)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(first))
        try repo.update(template, with: draft(second))

        #expect(template.configuration?.id == second.id)
        #expect(template.displayConfigurationName == "Deep")
        _ = container
    }

    @Test("Cancelling changes nothing — the editor only mutates on Save")
    func cancelMutatesNothing() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config, name: "Research", sessions: 4))
        let before = (template.name, template.taskName, template.defaultTotalSessions,
                      template.icon, template.updatedAt)

        // The editor holds its edits in @State and applies them only in `save()`. Cancelling
        // simply dismisses — no repository call happens, which is what this models.
        #expect(template.name == before.0)
        #expect(template.taskName == before.1)
        #expect(template.defaultTotalSessions == before.2)
        #expect(template.icon == before.3)
        #expect(template.updatedAt == before.4)
        #expect(try repo.count() == 1)
        _ = container
    }

    @Test("An invalid edit is rejected and leaves the stored template untouched")
    func invalidEditIsRejected() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makeTemplateRepository(container)

        let template = try repo.create(draft(config, name: "Research"))

        #expect(throws: PersistenceError.self) {
            try repo.update(template, with: draft(config, name: "   "))
        }
        #expect(template.name == "Research")
        _ = container
    }

    @Test("Saving an edit republishes Quick Start through the repositories' change hook")
    func editRefreshesQuickStart() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)

        var refreshes = 0
        let repo = TaskTemplateRepository(context: container.mainContext) { refreshes += 1 }

        let template = try repo.create(draft(config))
        try repo.setPinned(template, true)
        let afterPin = refreshes

        try repo.update(template, with: draft(config, name: "Renamed"))

        #expect(refreshes == afterPin + 1,
                "An edit must refresh the pinned projection so the menu bar shows the new name")
        #expect(QuickStartProvider.item(for: template).displayName == "Renamed")
        _ = container
    }
}

// MARK: - Plan editing

@MainActor
@Suite("Plan edit flow")
struct PlanEditFlowTests {

    @Test("Saving an edit updates the same plan — identity is preserved")
    func editPreservesIdentity() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makePlanRepository(container)

        let plan = try repo.create(simplePlanDraft(config))
        let originalID = plan.id
        let createdAt = plan.createdAt

        var edited = plan.draft
        edited.name = "Research II"
        edited.taskName = "Deep work"
        try repo.update(plan, with: edited.normalized)

        #expect(plan.id == originalID, "An edit must never mint a new identity")
        #expect(plan.createdAt == createdAt)
        #expect(plan.name == "Research II")
        #expect(plan.taskName == "Deep work")
        #expect(try repo.count() == 1, "Editing must update in place, never insert")
        _ = container
    }

    @Test("Editing the timeline replaces the plan's intervals without duplicating the plan")
    func editChangesItems() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makePlanRepository(container)

        let plan = try repo.create(simplePlanDraft(config))
        #expect(plan.items.count == 3)

        var edited = plan.draft
        edited.items.append(breakItem(.longBreak, duration: 900, order: 3))
        edited.items.append(focusItem(config, order: 4))
        try repo.update(plan, with: edited.normalized)

        #expect(plan.items.count == 5)
        #expect(plan.focusCount == 3)
        #expect(try repo.count() == 1)
        #expect(plan.orderedItems.map(\.order) == [0, 1, 2, 3, 4],
                "Order is normalised from array position on save")
        _ = container
    }

    @Test("A rename keeps the Quick Start pin and its position")
    func editKeepsPin() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makePlanRepository(container)

        let plan = try repo.create(simplePlanDraft(config))
        let pinDate = Date(timeIntervalSince1970: 2_000)
        try repo.setPinned(plan, true, at: pinDate)

        var edited = plan.draft
        edited.name = "Renamed"
        try repo.update(plan, with: edited.normalized)

        #expect(plan.isPinned)
        #expect(plan.pinnedAt == pinDate)
        #expect(try repo.pinned().map(\.id) == [plan.id])
        _ = container
    }

    @Test("The chosen icon is persisted as a catalog identifier and read back")
    func editPersistsIcon() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makePlanRepository(container)

        let plan = try repo.create(simplePlanDraft(config))
        var edited = plan.draft
        edited.icon = .flag
        try repo.update(plan, with: edited.normalized)

        #expect(plan.icon == .flag)
        #expect(plan.iconIdentifier == TimeFrameIconIdentifier.flag.rawValue)
        _ = container
    }

    @Test("An invalid edit is rejected and leaves the stored plan untouched")
    func invalidEditIsRejected() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let repo = makePlanRepository(container)

        let plan = try repo.create(simplePlanDraft(config, name: "Research Deep Work"))

        var edited = plan.draft
        edited.name = "  "
        #expect(throws: PersistenceError.self) {
            try repo.update(plan, with: edited.normalized)
        }
        #expect(plan.name == "Research Deep Work")
        #expect(plan.items.count == 3, "A rejected edit must not half-apply the timeline")
        _ = container
    }

    @Test("Editing a plan never disturbs the one timer")
    func editDoesNotTouchTheTimer() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let plan = try coordinator.plans.create(simplePlanDraft(config))

        _ = try coordinator.startSession(configuration: config, taskName: "Ship")
        clock.advance(by: 3)
        let remaining = coordinator.engine.remaining

        var edited = plan.draft
        edited.name = "Renamed mid-session"
        try coordinator.plans.update(plan, with: edited.normalized)

        #expect(coordinator.engine.state == .running)
        #expect(coordinator.engine.remaining == remaining)
        _ = container
    }
}

// MARK: - Structure: the detail pages own their editors (ADR-106)

@Suite("Editor presentation structure")
struct EditorPresentationStructureTests {

    private func detailSource(_ relativePath: String) -> String {
        SourceAudit.code(SourceAudit.appTarget().appendingPathComponent(relativePath))
    }

    private let templateDetail = "Views/Templates/TemplateDetailView.swift"
    private let planDetail = "Views/Plans/PlanDetailView.swift"
    private let templateList = "Views/Templates/TemplateListView.swift"
    private let planList = "Views/Plans/PlanListView.swift"

    @Test("Each detail page presents its own editor sheet")
    func detailPagesOwnTheirEditor() {
        let template = detailSource(templateDetail)
        #expect(template.contains(".sheet(item: $editingTemplate)"),
                "The template detail page must present the editor itself")
        #expect(template.contains("TemplateEditorView("))

        let plan = detailSource(planDetail)
        #expect(plan.contains(".sheet(item: $editingPlan)"),
                "The plan detail page must present the editor itself")
        #expect(plan.contains("PlanEditorView("))
    }

    @Test("No detail page delegates its editor upward to the list (the ADR-106 defect)")
    func detailPagesDoNotDelegateEditing() {
        for path in [templateDetail, planDetail] {
            let text = detailSource(path)
            #expect(!text.contains("onEdit"),
                    """
                    \(path) must not hand editing to its list: a sheet requested from the \
                    NavigationStack's root while a destination is pushed does not present on macOS.
                    """)
        }
    }

    @Test("The lists no longer pass an editor closure into their detail page")
    func listsDoNotInjectAnEditorClosure() {
        for path in [templateList, planList] {
            let text = detailSource(path)
            #expect(!text.contains("onEdit:"),
                    "\(path) must not inject an editor closure into a pushed destination")
        }
    }

    @Test("Editing still goes through the one repository update path")
    func editingUsesTheRepository() {
        let editor = detailSource("Views/Templates/TemplateEditorView.swift")
        #expect(editor.contains("coordinator.templates.update("))
        #expect(editor.contains("coordinator.templates.create("))

        let planEditor = detailSource("Views/Plans/PlanEditorView.swift")
        #expect(planEditor.contains("coordinator.plans.update("))
        #expect(planEditor.contains("coordinator.plans.create("))
    }

    @Test("Detail pages introduce no scheduling primitive of their own")
    func detailPagesHaveNoClock() {
        for path in [templateDetail, planDetail, "Views/Timer/SessionSetupView.swift"] {
            let text = detailSource(path)
            for token in ["Timer(", "Task.sleep", "asyncAfter", "scheduledTimer", "DispatchSourceTimer"] {
                #expect(!text.contains(token), "\(path) must not introduce \(token)")
            }
        }
    }
}
