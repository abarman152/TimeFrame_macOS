//
//  PersistenceError.swift
//  time_frame
//
//  Structured, observable errors for the persistence / lifecycle layer.
//

import Foundation

/// Errors surfaced by the persistence layer.
///
/// Persistence failures are never silently swallowed (requirement of Milestone
/// 2): repositories and the coordinator throw these so callers — and tests — can
/// observe exactly what went wrong. The UI can later map them to friendly
/// messages. `underlying` carries the original SwiftData error as a string so
/// the value stays `Sendable` and log-safe.
nonisolated enum PersistenceError: Error, Equatable, Sendable {
    /// A `ModelContext.save()` failed.
    case saveFailed(String)

    /// A fetch failed.
    case fetchFailed(String)

    /// A delete failed.
    case deleteFailed(String)

    /// A configuration failed validation. Carries every rule that was violated.
    case invalidConfiguration([ConfigurationValidationError])

    /// A task template failed validation. Carries every rule that was violated.
    case invalidTemplate([TaskTemplateValidationError])

    /// A session plan failed validation. Carries every rule that was violated.
    case invalidPlan([SessionPlanValidationError])

    /// A session referenced a configuration that no longer exists when one was
    /// required.
    case missingConfiguration

    /// A persisted session was too inconsistent to recover.
    case corruptedSession(String)

    /// Recovery of a session failed.
    case recoveryFailed(String)
}

extension PersistenceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .saveFailed(let detail):
            return "Couldn't save changes. \(detail)"
        case .fetchFailed(let detail):
            return "Couldn't load data. \(detail)"
        case .deleteFailed(let detail):
            return "Couldn't delete. \(detail)"
        case .invalidConfiguration(let errors):
            let reasons = errors.map(\.message).joined(separator: " ")
            return "The configuration is invalid. \(reasons)"
        case .invalidTemplate(let errors):
            let reasons = errors.map(\.message).joined(separator: " ")
            return "The template is invalid. \(reasons)"
        case .invalidPlan(let errors):
            let reasons = errors.map(\.message).joined(separator: " ")
            return "The plan is invalid. \(reasons)"
        case .missingConfiguration:
            return "The referenced configuration is missing."
        case .corruptedSession(let detail):
            return "The session data was inconsistent. \(detail)"
        case .recoveryFailed(let detail):
            return "Couldn't restore the previous session. \(detail)"
        }
    }
}
