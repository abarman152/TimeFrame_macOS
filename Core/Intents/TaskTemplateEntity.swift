//
//  TaskTemplateEntity.swift
//  time_frame (Milestone 12)
//
//  The App Intents representation of a persisted `TaskTemplate`, so Shortcuts/Siri can offer
//  the user's real templates as a parameter for "Start Template" (ADR-057). It is an
//  immutable value carrying only what a picker needs — a stable id and frozen display strings
//  — never the live SwiftData model. Its query reads through the existing
//  `TaskTemplateRepository`; it mutates nothing.
//

import Foundation
import AppIntents

/// A selectable task template for App Intents / Shortcuts.
///
/// The `id` is the template's stable `UUID` (never an array index — ADR-057), so a
/// shortcut keeps working across relaunches. Display strings are frozen at query time; if
/// the template is later deleted the query simply stops returning it.
struct TaskTemplateEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Task Template")

    static let defaultQuery = TaskTemplateEntityQuery()

    /// Stable identity — the template's `UUID`.
    let id: UUID
    /// The template's own name (how the reusable template is identified), e.g. "Research".
    let name: String
    /// The task a run from this template focuses on, e.g. "Research Quantum IDS".
    let taskName: String
    /// The frozen configuration label, or a neutral "Configuration unavailable".
    let configurationName: String

    var displayRepresentation: DisplayRepresentation {
        // Title = the template name; subtitle names the task and configuration so the
        // picker is meaningful and VoiceOver-friendly (never "Entity 7F3A…").
        let subtitle = taskName.isEmpty ? configurationName : "\(taskName) · \(configurationName)"
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)"
        )
    }

    /// Builds the value from a persisted template. `@MainActor` because it reads the
    /// SwiftData model; the resulting value is fully detached and Sendable.
    @MainActor
    init(_ template: TaskTemplate) {
        self.id = template.id
        self.name = template.name
        self.taskName = template.taskName
        self.configurationName = template.displayConfigurationName
    }
}

/// Resolves `TaskTemplateEntity` values from the persisted store, by id or by search string,
/// through the existing repository (ADR-057). Nonisolated so its `init()` satisfies
/// `EntityQuery`; each async method hops to the main actor to touch the main-context repository.
struct TaskTemplateEntityQuery: EntityStringQuery {
    @AppDependency private var data: IntentDataProvider

    // The `@AppDependency`-backed methods are thin forwarders to the `@MainActor` resolution
    // cores below, which take the repository explicitly. That keeps all query *logic*
    // unit-testable against an in-memory repository — the dependency manager only supplies the
    // repository at runtime, and is never needed by the tests.

    func entities(for identifiers: [UUID]) async throws -> [TaskTemplateEntity] {
        let provider = data
        return try await MainActor.run { try Self.resolve(identifiers, in: provider.templates) }
    }

    func suggestedEntities() async throws -> [TaskTemplateEntity] {
        let provider = data
        return try await MainActor.run { try Self.suggested(in: provider.templates) }
    }

    func entities(matching string: String) async throws -> [TaskTemplateEntity] {
        let provider = data
        return try await MainActor.run { try Self.matching(string, in: provider.templates) }
    }

    // MARK: Testable resolution cores

    /// Resolve specific templates the user previously chose (deleted ones drop out).
    @MainActor
    static func resolve(_ identifiers: [UUID], in repository: TaskTemplateRepository) throws -> [TaskTemplateEntity] {
        try identifiers.compactMap { id in
            try repository.template(with: id).map(TaskTemplateEntity.init)
        }
    }

    /// The templates offered when the parameter picker first opens.
    @MainActor
    static func suggested(in repository: TaskTemplateRepository) throws -> [TaskTemplateEntity] {
        try repository.all().map(TaskTemplateEntity.init)
    }

    /// Free-text filtering as the user types a template name in Shortcuts/Siri.
    @MainActor
    static func matching(_ string: String, in repository: TaskTemplateRepository) throws -> [TaskTemplateEntity] {
        let needle = string.lowercased()
        return try repository.all()
            .filter { $0.name.lowercased().contains(needle) || $0.taskName.lowercased().contains(needle) }
            .map(TaskTemplateEntity.init)
    }
}
