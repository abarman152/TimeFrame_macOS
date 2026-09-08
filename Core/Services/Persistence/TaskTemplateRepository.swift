//
//  TaskTemplateRepository.swift
//  time_frame
//
//  Application-level CRUD for TaskTemplate, isolated from the UI. Mirrors the
//  conventions of ConfigurationRepository / SessionRepository.
//

import Foundation
import SwiftData
import os

/// Create/read/update/delete operations for `TaskTemplate`, plus duplication and
/// default selection.
///
/// This is the persistence boundary the Templates UI sits on top of, so SwiftData
/// calls do not leak into views. It is `@MainActor` and operates on the main
/// `ModelContext`; SwiftData model instances never cross an actor boundary
/// (ADR-011). Failures surface as `PersistenceError`, never swallowed. The
/// configuration a draft names is resolved here (by id) so callers pass only a
/// value-typed `TaskTemplateDraft`.
@MainActor
struct TaskTemplateRepository {
    let context: ModelContext

    /// Fired after any successful mutation (create/update/delete/duplicate/default/pin).
    ///
    /// The same neutral, opaque hook `ConfigurationRepository` already carries (ADR-097),
    /// reused here so the Quick Start surface can refresh *event-driven* when a template is
    /// pinned, renamed, or deleted — never by polling (ADR-105). The persistence layer stays
    /// free of any menu-bar/widget dependency: it knows only that "something changed".
    /// Best-effort and side-effect-only; a nil handler is the common case (tests, intents).
    private let onChange: (@MainActor () -> Void)?

    init(context: ModelContext, onChange: (@MainActor () -> Void)? = nil) {
        self.context = context
        self.onChange = onChange
    }

    // MARK: Read

    /// All templates, newest first.
    func all() throws -> [TaskTemplate] {
        let descriptor = FetchDescriptor<TaskTemplate>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// The number of stored templates.
    func count() throws -> Int {
        do {
            return try context.fetchCount(FetchDescriptor<TaskTemplate>())
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// The current default template, if one is set.
    func defaultTemplate() throws -> TaskTemplate? {
        // Filtered in memory: the set is tiny and this avoids predicate subtleties
        // on a stored Bool (mirrors ConfigurationRepository.defaultConfiguration).
        try all().first { $0.isDefault }
    }

    /// The template with the given id, if it still exists. A targeted fetch (not a
    /// full scan) so the App Intents `TaskTemplateEntity` query resolves one template
    /// cheaply and returns `nil` gracefully when it was deleted (mirrors
    /// `SessionPlanRepository.plan(with:)`).
    func template(with id: UUID) throws -> TaskTemplate? {
        let descriptor = FetchDescriptor<TaskTemplate>(predicate: #Predicate { $0.id == id })
        do {
            return try context.fetch(descriptor).first
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    // MARK: Create

    /// Validates a draft and inserts a new template.
    ///
    /// - Parameter makeDefault: when true, the new template becomes the default
    ///   (clearing any previous default) in the same save.
    @discardableResult
    func create(_ draft: TaskTemplateDraft, makeDefault: Bool = false) throws -> TaskTemplate {
        try draft.validated()
        let configuration = try resolveConfiguration(draft.configurationID)

        let template = TaskTemplate(
            name: draft.trimmedName,
            taskName: draft.trimmedTaskName,
            configuration: configuration,
            defaultTotalSessions: draft.defaultTotalSessions
        )
        // Stored as the catalog's stable identifier, never an SF Symbol name (ADR-103).
        template.iconIdentifier = draft.icon.rawValue
        context.insert(template)

        if makeDefault {
            clearDefaultFlag(except: template)
            template.isDefault = true
        }
        try save()
        onChange?()
        return template
    }

    // MARK: Update

    /// Validates a draft and applies it to an existing template, bumping
    /// `updatedAt`. The persisted template is only mutated here (on Save), never
    /// while the editor is open.
    func update(_ template: TaskTemplate, with draft: TaskTemplateDraft) throws {
        try draft.validated()
        let configuration = try resolveConfiguration(draft.configurationID)

        template.name = draft.trimmedName
        template.taskName = draft.trimmedTaskName
        template.configuration = configuration
        template.defaultTotalSessions = draft.defaultTotalSessions
        template.iconIdentifier = draft.icon.rawValue
        template.updatedAt = Date()
        // `isPinned` is deliberately NOT part of the draft: an edit must never silently
        // change what the user pinned. A rename therefore keeps the pin (ADR-104).
        try save()
        onChange?()
    }

    // MARK: Delete

    /// Deletes a template. Historical sessions (and their intervals) and the
    /// referenced configuration are untouched — a template is only a reusable
    /// definition (ADR-024).
    func delete(_ template: TaskTemplate) throws {
        context.delete(template)
        do {
            try context.save()
        } catch {
            throw PersistenceError.deleteFailed(String(describing: error))
        }
        // Deleting a pinned template removes it from Quick Start: the pin lives on the row
        // that just went away, and this refresh republishes the remaining pins (ADR-104).
        onChange?()
    }

    // MARK: Duplicate

    /// Creates an independent copy of a template. The copy has a new identity and
    /// fresh timestamps, is never the default, and is named "… Copy"; it preserves
    /// the task name, configuration reference, and default session count. Editing
    /// the copy never affects the original (independent identities).
    @discardableResult
    func duplicate(_ template: TaskTemplate) throws -> TaskTemplate {
        let copy = TaskTemplate(
            name: "\(template.name) Copy",
            taskName: template.taskName,
            configuration: template.configuration,
            defaultTotalSessions: template.defaultTotalSessions,
            isDefault: false
        )
        // The copy inherits the icon but never the pin: pinning is an explicit user choice
        // about one item, so a duplicate starts unpinned (ADR-104).
        copy.iconIdentifier = template.iconIdentifier
        context.insert(copy)
        try save()
        onChange?()
        return copy
    }

    // MARK: Default selection

    /// Makes `template` the one default, clearing the flag on all others.
    func setDefault(_ template: TaskTemplate) throws {
        clearDefaultFlag(except: template)
        template.isDefault = true
        try save()
        onChange?()
    }

    /// Clears the default flag on `template` if it is set (so there can be no
    /// default at all). Idempotent.
    func clearDefault(_ template: TaskTemplate) throws {
        guard template.isDefault else { return }
        template.isDefault = false
        try save()
        onChange?()
    }

    // MARK: Quick Start pinning (ADR-104)

    /// Pins or unpins the template for Quick Start. Idempotent: re-pinning an already
    /// pinned template keeps its original `pinnedAt`, so the Quick Start order does not
    /// jump when the user taps twice.
    ///
    /// Pin state is stored **on the template**, keyed by its stable `id`. There is no
    /// separate pin table and no name-keyed list, so renaming preserves the pin and
    /// deleting the template removes it from Quick Start with nothing left to reconcile.
    func setPinned(_ template: TaskTemplate, _ pinned: Bool, at date: Date = Date()) throws {
        guard template.isPinned != pinned else { return }
        template.isPinned = pinned
        template.pinnedAt = pinned ? date : nil
        try save()
        onChange?()
    }

    /// Every pinned template, oldest pin first (a stable order the user chose by pinning).
    func pinned() throws -> [TaskTemplate] {
        try all()
            .filter(\.isPinned)
            .sorted { QuickStartOrder.isOrderedBefore(($0.pinnedAt, $0.name, $0.id),
                                                      ($1.pinnedAt, $1.name, $1.id)) }
    }

    // MARK: Private

    /// Resolves the configuration a draft names. Validation already guaranteed a
    /// non-nil id; if the row cannot be found (e.g. it was deleted between
    /// selection and save) this surfaces as a template validation failure rather
    /// than silently storing a template with no configuration.
    private func resolveConfiguration(_ id: UUID?) throws -> PomodoroConfiguration {
        guard let id else {
            throw PersistenceError.invalidTemplate([.missingConfiguration])
        }
        let descriptor = FetchDescriptor<PomodoroConfiguration>(
            predicate: #Predicate { $0.id == id }
        )
        do {
            guard let configuration = try context.fetch(descriptor).first else {
                throw PersistenceError.invalidTemplate([.missingConfiguration])
            }
            return configuration
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// Clears `isDefault` on every stored template except `keep`.
    private func clearDefaultFlag(except keep: TaskTemplate) {
        let others = (try? all()) ?? []
        for template in others where template.id != keep.id && template.isDefault {
            template.isDefault = false
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
