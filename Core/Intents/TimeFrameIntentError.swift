//
//  TimeFrameIntentError.swift
//  time_frame (Milestone 12)
//
//  The only error type the App Intents layer surfaces to the user. Every case maps to a
//  short, friendly sentence — never a Swift error, SwiftData error, UUID, or internal
//  detail (a privacy/clarity requirement of Milestone 12). Conforms to
//  `CustomLocalizedStringResourceConvertible` so the App Intents runtime speaks/shows the
//  message directly, and to `LocalizedError` so it reads correctly anywhere else.
//

import Foundation
import AppIntents

/// A user-facing failure from a Time Frame App Intent.
///
/// Deliberately small and closed: intents translate every internal failure (a repository
/// throw, a missing reference, an invalid state) into one of these before it can reach the
/// user, so implementation details never leak (ADR-056).
nonisolated enum TimeFrameIntentError: Error, CustomLocalizedStringResourceConvertible, LocalizedError, Equatable {
    /// A control/query intent ran with no session active.
    case noActiveSession
    /// A start intent ran while a session was already running or paused.
    case sessionAlreadyRunning
    /// The referenced task template no longer exists (deleted since it was picked).
    case templateUnavailable
    /// The referenced session plan no longer exists.
    case planUnavailable
    /// The referenced configuration no longer exists.
    case configurationUnavailable
    /// The template/plan exists but has lost the configuration it needs to start.
    case templateNeedsConfiguration
    /// The plan exists but is not startable (no focus intervals, or a lost configuration).
    case planNotStartable
    /// The session could not be started for an unexpected reason (persistence failure).
    /// Kept generic so no internal error text is exposed.
    case couldNotStartSession
    /// A control action (pause/resume/skip/restart/stop) failed unexpectedly. Generic so
    /// no internal persistence error text is exposed.
    case actionFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActiveSession:
            return "No Time Frame session is currently running."
        case .sessionAlreadyRunning:
            return "A Time Frame session is already running. Stop it first to start a new one."
        case .templateUnavailable:
            return "That template is no longer available."
        case .planUnavailable:
            return "That plan is no longer available."
        case .configurationUnavailable:
            return "That configuration is no longer available."
        case .templateNeedsConfiguration:
            return "The configuration used by this template is no longer available."
        case .planNotStartable:
            return "This plan can't be started because it has no usable focus intervals."
        case .couldNotStartSession:
            return "Time Frame couldn't start the session. Please try again."
        case .actionFailed:
            return "Time Frame couldn't complete that action. Please try again."
        }
    }

    /// Mirrors the localized message so the error also reads correctly outside App Intents.
    var errorDescription: String? { String(localized: localizedStringResource) }
}
