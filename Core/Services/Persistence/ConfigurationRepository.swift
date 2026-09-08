//
//  ConfigurationRepository.swift
//  time_frame
//
//  Application-level CRUD for PomodoroConfiguration, isolated from the UI.
//

import Foundation
import SwiftData
import os

/// Create/read/update/delete operations for `PomodoroConfiguration`, plus
/// duplication, default selection, and first-launch seeding.
///
/// This is the persistence boundary the UI (in a later milestone) and the
/// `SessionCoordinator` sit on top of, so SwiftData calls do not leak into
/// views or the coordinator. It is `@MainActor` and operates on the main
/// `ModelContext`; SwiftData model instances never cross an actor boundary
/// (ADR-011). Failures are surfaced as `PersistenceError`, never swallowed.
@MainActor
struct ConfigurationRepository {
    let context: ModelContext

    /// Fired after any successful mutation (create/update/delete/duplicate/setDefault/seed).
    ///
    /// A neutral, opaque hook: the repository knows nothing about *why* an observer cares. The
    /// app wires it to republish the Control Center quick-start catalog (Milestone 24, ADR-097),
    /// so the picker reflects a rename/create/delete without polling — but the persistence layer
    /// stays free of any widget/projection dependency (dependencies point downward only). It is
    /// best-effort and side-effect-only: a nil handler is the common case (tests, intents), and
    /// firing it never affects the save that just succeeded.
    private let onChange: (@MainActor () -> Void)?

    init(context: ModelContext, onChange: (@MainActor () -> Void)? = nil) {
        self.context = context
        self.onChange = onChange
    }

    // MARK: Read

    /// All configurations, newest first.
    func all() throws -> [PomodoroConfiguration] {
        var descriptor = FetchDescriptor<PomodoroConfiguration>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = []
        do {
            return try context.fetch(descriptor)
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// The number of stored configurations.
    func count() throws -> Int {
        do {
            return try context.fetchCount(FetchDescriptor<PomodoroConfiguration>())
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// The current default configuration, if one is set.
    func defaultConfiguration() throws -> PomodoroConfiguration? {
        // Filtered in memory: the set is tiny and this avoids any predicate
        // subtleties on stored Bool/enum properties.
        try all().first { $0.isDefault }
    }

    /// The configuration with the given id, if it still exists. A targeted fetch so the
    /// App Intents `ConfigurationEntity` query resolves one configuration cheaply and
    /// returns `nil` gracefully when it was deleted (mirrors `plan(with:)`).
    func configuration(with id: UUID) throws -> PomodoroConfiguration? {
        let descriptor = FetchDescriptor<PomodoroConfiguration>(predicate: #Predicate { $0.id == id })
        do {
            return try context.fetch(descriptor).first
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    // MARK: Create

    /// Validates a draft and inserts a new configuration.
    ///
    /// - Parameter makeDefault: when true, the new configuration becomes the
    ///   default (clearing any previous default) in the same save.
    @discardableResult
    func create(_ draft: ConfigurationDraft, makeDefault: Bool = false) throws -> PomodoroConfiguration {
        try draft.validated()

        let configuration = PomodoroConfiguration(
            name: draft.name,
            focusDuration: draft.focusDuration,
            shortBreakDuration: draft.shortBreakDuration,
            longBreakDuration: draft.longBreakDuration,
            sessionsBeforeLongBreak: draft.sessionsBeforeLongBreak,
            defaultTotalSessions: draft.totalSessions
        )
        context.insert(configuration)

        if makeDefault {
            clearDefaultFlag(except: configuration)
            configuration.isDefault = true
        }
        try save()
        onChange?()
        return configuration
    }

    // MARK: Update

    /// Validates a draft and applies it to an existing configuration.
    func update(_ configuration: PomodoroConfiguration, with draft: ConfigurationDraft) throws {
        try draft.validated()

        configuration.name = draft.name
        configuration.focusDuration = draft.focusDuration
        configuration.shortBreakDuration = draft.shortBreakDuration
        configuration.longBreakDuration = draft.longBreakDuration
        configuration.sessionsBeforeLongBreak = draft.sessionsBeforeLongBreak
        configuration.defaultTotalSessions = draft.totalSessions
        configuration.modifiedAt = Date()
        try save()
        onChange?()
    }

    // MARK: Delete

    /// Deletes a configuration. Sessions that referenced it are preserved (the
    /// relationship nullifies — ADR-007).
    func delete(_ configuration: PomodoroConfiguration) throws {
        context.delete(configuration)
        do {
            try context.save()
        } catch {
            throw PersistenceError.deleteFailed(String(describing: error))
        }
        onChange?()
    }

    // MARK: Duplicate

    /// Creates an independent copy of a configuration. The copy is never the
    /// default and is named "Copy of …".
    @discardableResult
    func duplicate(_ configuration: PomodoroConfiguration) throws -> PomodoroConfiguration {
        let copy = PomodoroConfiguration(
            name: "Copy of \(configuration.name)",
            focusDuration: configuration.focusDuration,
            shortBreakDuration: configuration.shortBreakDuration,
            longBreakDuration: configuration.longBreakDuration,
            sessionsBeforeLongBreak: configuration.sessionsBeforeLongBreak,
            defaultTotalSessions: configuration.defaultTotalSessions,
            isDefault: false
        )
        context.insert(copy)
        try save()
        onChange?()
        return copy
    }

    // MARK: Default selection

    /// Makes `configuration` the one default, clearing the flag on all others.
    func setDefault(_ configuration: PomodoroConfiguration) throws {
        clearDefaultFlag(except: configuration)
        configuration.isDefault = true
        try save()
        onChange?()
    }

    // MARK: Seeding

    /// Ensures a default configuration exists so a first-launch user has
    /// something to run. Idempotent: does nothing if any configuration already
    /// exists, so relaunching never creates duplicates and never overwrites a
    /// user's configurations. See ADR-015.
    @discardableResult
    func seedDefaultIfNeeded() throws -> PomodoroConfiguration? {
        guard try count() == 0 else { return nil }
        let classic = PomodoroConfiguration.classic()
        classic.isDefault = true
        context.insert(classic)
        try save()
        onChange?()
        AppLog.persistence.info("Seeded default configuration.")
        return classic
    }

    // MARK: Private

    /// Clears `isDefault` on every stored configuration except `keep`.
    private func clearDefaultFlag(except keep: PomodoroConfiguration) {
        let others = (try? all()) ?? []
        for config in others where config.id != keep.id && config.isDefault {
            config.isDefault = false
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
