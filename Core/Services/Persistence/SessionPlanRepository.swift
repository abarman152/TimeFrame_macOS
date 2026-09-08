//
//  SessionPlanRepository.swift
//  time_frame
//
//  Application-level CRUD for SessionPlan / SessionPlanItem, isolated from the UI.
//  Mirrors the conventions of Configuration/Session/TaskTemplate repositories. It
//  contains no timer logic — a plan is a designed sequence, and executing one is
//  the SessionCoordinator's job (ADR-026).
//

import Foundation
import SwiftData
import os

/// Create/read/update/delete plus duplication for `SessionPlan` and its owned
/// `SessionPlanItem`s.
///
/// This is the persistence boundary the Plans UI sits on top of, so SwiftData calls
/// do not leak into views. It is `@MainActor` and operates on the main
/// `ModelContext`; SwiftData model instances never cross an actor boundary
/// (ADR-011). Failures surface as `PersistenceError`, never swallowed. A draft
/// carries its configurations by **id**; the repository resolves them and freezes
/// each focus item's configuration name so display survives a later configuration
/// deletion (ADR-019 principle).
@MainActor
struct SessionPlanRepository {
    let context: ModelContext

    /// Fired after any successful mutation (create/update/delete/duplicate/pin). The same
    /// neutral, opaque hook `ConfigurationRepository` carries (ADR-097), so the Quick Start
    /// surface refreshes event-driven when a plan is pinned, renamed, or deleted — never by
    /// polling (ADR-105). Best-effort and side-effect-only.
    private let onChange: (@MainActor () -> Void)?

    init(context: ModelContext, onChange: (@MainActor () -> Void)? = nil) {
        self.context = context
        self.onChange = onChange
    }

    // MARK: Read

    /// All plans, most recently updated first.
    func all() throws -> [SessionPlan] {
        let descriptor = FetchDescriptor<SessionPlan>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// The number of stored plans.
    func count() throws -> Int {
        do {
            return try context.fetchCount(FetchDescriptor<SessionPlan>())
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// The plan with the given id, if it still exists.
    func plan(with id: UUID) throws -> SessionPlan? {
        let descriptor = FetchDescriptor<SessionPlan>(predicate: #Predicate { $0.id == id })
        do {
            return try context.fetch(descriptor).first
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    // MARK: Create

    /// Validates a draft and inserts a new plan with its items. Ordering is
    /// normalized from array position so the stored `order` is always contiguous.
    @discardableResult
    func create(_ draft: SessionPlanDraft) throws -> SessionPlan {
        let normalized = draft.normalized
        try normalized.validated()
        let configurations = try configurationLookup()
        try requireResolvableFocusConfigurations(normalized, configurations: configurations)

        let plan = SessionPlan(name: normalized.trimmedName, taskName: normalized.trimmedTaskName)
        // Stored as the catalog's stable identifier, never an SF Symbol name (ADR-103).
        plan.iconIdentifier = normalized.icon.rawValue
        context.insert(plan)
        for itemDraft in normalized.items {
            plan.items.append(try makeItem(itemDraft, configurations: configurations))
        }
        try save()
        onChange?()
        AppLog.persistence.info("Created session plan with \(normalized.items.count, privacy: .public) items.")
        return plan
    }

    // MARK: Update

    /// Validates a draft and applies it to an existing plan, reconciling items by
    /// id (updated in place, added, or removed) so stable identities are preserved
    /// and no duplicate rows are created. Bumps `updatedAt`.
    func update(_ plan: SessionPlan, with draft: SessionPlanDraft) throws {
        let normalized = draft.normalized
        try normalized.validated()
        let configurations = try configurationLookup()
        try requireResolvableFocusConfigurations(normalized, configurations: configurations)

        var existing = Dictionary(
            plan.items.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let keptIDs = Set(normalized.items.map(\.id))

        // Remove items no longer in the draft. Collect first, then delete, so the
        // live relationship array is not mutated while it is being iterated.
        let toRemove = plan.items.filter { !keptIDs.contains($0.id) }
        for item in toRemove {
            context.delete(item)
        }

        // Update existing items in place; create new ones.
        for itemDraft in normalized.items {
            if let item = existing[itemDraft.id] {
                apply(itemDraft, to: item, configurations: configurations)
                existing.removeValue(forKey: itemDraft.id)
            } else {
                plan.items.append(try makeItem(itemDraft, configurations: configurations))
            }
        }

        plan.name = normalized.trimmedName
        plan.taskName = normalized.trimmedTaskName
        plan.iconIdentifier = normalized.icon.rawValue
        plan.updatedAt = Date()
        // `isPinned` is deliberately NOT part of the draft: editing a plan must never
        // silently change what the user pinned, so a rename keeps the pin (ADR-104).
        try save()
        onChange?()
    }

    // MARK: Delete

    /// Deletes a plan and (by cascade) its items. Configurations, historical
    /// sessions, and any session already started from the plan are untouched — a
    /// plan is only a reusable design (ADR-029).
    func delete(_ plan: SessionPlan) throws {
        context.delete(plan)
        do {
            try context.save()
        } catch {
            throw PersistenceError.deleteFailed(String(describing: error))
        }
        // Deleting a pinned plan removes it from Quick Start: the pin lived on the row that
        // just went away, so nothing is left to reconcile (ADR-104).
        onChange?()
    }

    // MARK: Duplicate

    /// Creates an independent copy of a plan: a new identity, fresh timestamps, a
    /// "… Copy" name, and independent items (new ids, same values). Editing the copy
    /// never affects the original.
    @discardableResult
    func duplicate(_ plan: SessionPlan) throws -> SessionPlan {
        let copy = SessionPlan(name: "\(plan.name) Copy", taskName: plan.taskName)
        // The copy inherits the icon but never the pin — pinning is an explicit choice
        // about one item (ADR-104).
        copy.iconIdentifier = plan.iconIdentifier
        context.insert(copy)
        for item in plan.orderedItems {
            copy.items.append(
                SessionPlanItem(
                    order: item.order,
                    phase: item.phase,
                    duration: item.duration,
                    configuration: item.configuration,
                    configurationName: item.configurationName
                )
            )
        }
        try save()
        onChange?()
        return copy
    }

    // MARK: Quick Start pinning (ADR-104)

    /// Pins or unpins the plan for Quick Start. Idempotent: re-pinning keeps the original
    /// `pinnedAt` so the Quick Start order does not jump.
    ///
    /// Pin state is stored **on the plan**, keyed by its stable `id` — no separate pin
    /// table, so a rename preserves the pin and a delete removes it from Quick Start.
    func setPinned(_ plan: SessionPlan, _ pinned: Bool, at date: Date = Date()) throws {
        guard plan.isPinned != pinned else { return }
        plan.isPinned = pinned
        plan.pinnedAt = pinned ? date : nil
        try save()
        onChange?()
    }

    /// Every pinned plan, oldest pin first.
    func pinned() throws -> [SessionPlan] {
        try all()
            .filter(\.isPinned)
            .sorted { QuickStartOrder.isOrderedBefore(($0.pinnedAt, $0.name, $0.id),
                                                      ($1.pinnedAt, $1.name, $1.id)) }
    }

    // MARK: Private

    /// A snapshot of every configuration keyed by id, so item resolution does not
    /// hit the store once per item.
    private func configurationLookup() throws -> [UUID: PomodoroConfiguration] {
        do {
            let all = try context.fetch(FetchDescriptor<PomodoroConfiguration>())
            return Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// Fails validation if any focus item names a configuration that cannot be
    /// resolved (e.g. it was deleted between selection and save), so an incomplete
    /// plan is never silently stored (mirrors `TaskTemplateRepository`).
    private func requireResolvableFocusConfigurations(
        _ draft: SessionPlanDraft,
        configurations: [UUID: PomodoroConfiguration]
    ) throws {
        for item in draft.items where item.isFocus {
            guard let id = item.configurationID, configurations[id] != nil else {
                throw PersistenceError.invalidPlan([.focusMissingConfiguration])
            }
        }
    }

    /// Builds a fresh persisted item from a draft, resolving its configuration.
    private func makeItem(
        _ draft: PlanItemDraft,
        configurations: [UUID: PomodoroConfiguration]
    ) throws -> SessionPlanItem {
        let item = SessionPlanItem(order: draft.order, phase: draft.phase, duration: draft.duration)
        apply(draft, to: item, configurations: configurations)
        return item
    }

    /// Applies a draft's values to an item, resolving and freezing its configuration.
    private func apply(
        _ draft: PlanItemDraft,
        to item: SessionPlanItem,
        configurations: [UUID: PomodoroConfiguration]
    ) {
        item.order = draft.order
        item.phase = draft.phase
        item.duration = draft.duration
        if draft.isFocus, let id = draft.configurationID, let config = configurations[id] {
            item.configuration = config
            // Freeze the configuration's current name for robust display after a
            // later deletion (ADR-019 principle).
            item.configurationName = config.name
        } else {
            item.configuration = nil
            // Preserve a previously frozen name for a focus item whose configuration
            // was deleted, so it still shows what it used; clear it for breaks.
            item.configurationName = draft.isFocus ? draft.configurationName : ""
        }
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            throw PersistenceError.saveFailed(String(describing: error))
        }
    }
}
