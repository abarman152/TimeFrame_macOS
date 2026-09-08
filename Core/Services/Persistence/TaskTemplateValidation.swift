//
//  TaskTemplateValidation.swift
//  time_frame
//
//  Validation rules for TaskTemplate drafts. A dedicated, pure validation layer
//  so the same rules apply to create and update and are testable without the UI.
//

import Foundation

/// A single validation failure for a task template, with a human-readable reason.
/// `nonisolated`/`Sendable`/`Equatable` so it can travel inside a
/// `PersistenceError` and be asserted in tests.
nonisolated enum TaskTemplateValidationError: Error, Equatable, Sendable, Hashable {
    case emptyName
    case emptyTaskName
    case missingConfiguration
    case sessionCountNotPositive
    case tooManySessions

    /// A short, user-facing explanation.
    var message: String {
        switch self {
        case .emptyName:
            return "The template name can't be empty."
        case .emptyTaskName:
            return "The task name can't be empty."
        case .missingConfiguration:
            return "Choose a configuration for this template."
        case .sessionCountNotPositive:
            return "There must be at least one focus session."
        case .tooManySessions:
            return "Too many focus sessions (max \(ConfigurationLimits.maxTotalSessions))."
        }
    }
}

/// The proposed values for creating or updating a `TaskTemplate`.
///
/// A plain `Sendable` value so validation is a pure function (trivially testable)
/// and the same rules apply to create and update. The configuration is carried by
/// **id** (not the SwiftData model) so the draft stays value-typed; the repository
/// resolves it. Invalid input is **never silently modified** — `validate()`
/// reports every violated rule so the caller can surface them.
nonisolated struct TaskTemplateDraft: Equatable, Sendable {
    var name: String
    var taskName: String
    var configurationID: UUID?
    var defaultTotalSessions: Int
    /// The chosen icon. Typed, so an arbitrary SF Symbol string can never enter the
    /// draft — the editor picks a catalog member and the repository persists its stable
    /// identifier (ADR-103). Needs no validation rule: the type *is* the rule.
    var icon: TimeFrameIconIdentifier

    init(
        name: String = "",
        taskName: String = "",
        configurationID: UUID? = nil,
        defaultTotalSessions: Int = 4,
        icon: TimeFrameIconIdentifier = .templateDefault
    ) {
        self.name = name
        self.taskName = taskName
        self.configurationID = configurationID
        self.defaultTotalSessions = defaultTotalSessions
        self.icon = icon
    }

    /// The template name with surrounding whitespace removed — what gets persisted.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The task name with surrounding whitespace removed — what gets persisted.
    var trimmedTaskName: String {
        taskName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every rule this draft violates, in a stable order. Empty means valid.
    ///
    /// The session-count bound (1…`ConfigurationLimits.maxTotalSessions`) is shared
    /// with configuration validation so a template can never carry a count the
    /// timer could not run.
    func validate() -> [TaskTemplateValidationError] {
        var errors: [TaskTemplateValidationError] = []

        if trimmedName.isEmpty { errors.append(.emptyName) }
        if trimmedTaskName.isEmpty { errors.append(.emptyTaskName) }
        if configurationID == nil { errors.append(.missingConfiguration) }

        if defaultTotalSessions < 1 {
            errors.append(.sessionCountNotPositive)
        } else if defaultTotalSessions > ConfigurationLimits.maxTotalSessions {
            errors.append(.tooManySessions)
        }

        return errors
    }

    /// Throws `PersistenceError.invalidTemplate` if any rule is violated.
    func validated() throws {
        let errors = validate()
        guard errors.isEmpty else {
            throw PersistenceError.invalidTemplate(errors)
        }
    }
}
