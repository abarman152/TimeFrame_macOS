//
//  ConfigurationValidation.swift
//  time_frame
//
//  Validation rules and limits for PomodoroConfiguration values.
//

import Foundation

/// The accepted bounds for a `PomodoroConfiguration`.
///
/// Durations are in **seconds**. The maxima are deliberately generous but finite
/// so a typo (e.g. a duration of millions of seconds) is rejected rather than
/// producing an unusable plan. See ADR-015.
nonisolated enum ConfigurationLimits {
    /// The smallest a focus interval may be (must be strictly positive).
    static let minFocusDuration: TimeInterval = 1
    /// The largest any single interval may be: 8 hours.
    static let maxDuration: TimeInterval = 8 * 60 * 60
    /// The largest number of focus sessions in one run.
    static let maxTotalSessions = 24
    /// The largest long-break interval (focus blocks between long breaks).
    static let maxSessionsBeforeLongBreak = 12
}

/// A single validation failure for a configuration, with a human-readable
/// reason. `nonisolated`/`Sendable`/`Equatable` so it can travel inside a
/// `PersistenceError` and be asserted in tests.
nonisolated enum ConfigurationValidationError: Error, Equatable, Sendable, Hashable {
    case emptyName
    case focusDurationNotPositive
    case shortBreakNegative
    case longBreakNegative
    case totalSessionsNotPositive
    case sessionsBeforeLongBreakNotPositive
    case focusDurationTooLong
    case shortBreakTooLong
    case longBreakTooLong
    case tooManySessions
    case sessionsBeforeLongBreakTooLarge

    /// A short, user-facing explanation.
    var message: String {
        switch self {
        case .emptyName:
            return "The name can't be empty."
        case .focusDurationNotPositive:
            return "Focus duration must be greater than zero."
        case .shortBreakNegative:
            return "Short break duration can't be negative."
        case .longBreakNegative:
            return "Long break duration can't be negative."
        case .totalSessionsNotPositive:
            return "There must be at least one focus session."
        case .sessionsBeforeLongBreakNotPositive:
            return "Sessions before a long break must be at least one."
        case .focusDurationTooLong:
            return "Focus duration is too long (max 8 hours)."
        case .shortBreakTooLong:
            return "Short break is too long (max 8 hours)."
        case .longBreakTooLong:
            return "Long break is too long (max 8 hours)."
        case .tooManySessions:
            return "Too many focus sessions (max \(ConfigurationLimits.maxTotalSessions))."
        case .sessionsBeforeLongBreakTooLarge:
            return "Long-break interval is too large (max \(ConfigurationLimits.maxSessionsBeforeLongBreak))."
        }
    }
}

/// The proposed values for creating or updating a `PomodoroConfiguration`.
///
/// Kept as a plain value so validation is a pure function (trivially testable)
/// and the same rules apply to create and update. Invalid input is **never
/// silently modified** — `validate()` reports every violated rule so the caller
/// can surface them.
nonisolated struct ConfigurationDraft: Equatable, Sendable {
    var name: String
    var focusDuration: TimeInterval
    var shortBreakDuration: TimeInterval
    var longBreakDuration: TimeInterval
    var sessionsBeforeLongBreak: Int
    var totalSessions: Int

    init(
        name: String,
        focusDuration: TimeInterval = 25 * 60,
        shortBreakDuration: TimeInterval = 5 * 60,
        longBreakDuration: TimeInterval = 15 * 60,
        sessionsBeforeLongBreak: Int = 4,
        totalSessions: Int = 4
    ) {
        self.name = name
        self.focusDuration = focusDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.sessionsBeforeLongBreak = sessionsBeforeLongBreak
        self.totalSessions = totalSessions
    }

    /// Every rule this draft violates, in a stable order. Empty means valid.
    func validate() -> [ConfigurationValidationError] {
        var errors: [ConfigurationValidationError] = []
        let limits = ConfigurationLimits.self

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyName)
        }

        // Focus duration: strictly positive, within the maximum.
        if !(focusDuration > 0) {
            errors.append(.focusDurationNotPositive)
        } else if focusDuration > limits.maxDuration {
            errors.append(.focusDurationTooLong)
        }

        // Breaks: non-negative (zero disables the break), within the maximum.
        if shortBreakDuration < 0 {
            errors.append(.shortBreakNegative)
        } else if shortBreakDuration > limits.maxDuration {
            errors.append(.shortBreakTooLong)
        }
        if longBreakDuration < 0 {
            errors.append(.longBreakNegative)
        } else if longBreakDuration > limits.maxDuration {
            errors.append(.longBreakTooLong)
        }

        // Counts: strictly positive, within the maximum.
        if totalSessions < 1 {
            errors.append(.totalSessionsNotPositive)
        } else if totalSessions > limits.maxTotalSessions {
            errors.append(.tooManySessions)
        }
        if sessionsBeforeLongBreak < 1 {
            errors.append(.sessionsBeforeLongBreakNotPositive)
        } else if sessionsBeforeLongBreak > limits.maxSessionsBeforeLongBreak {
            errors.append(.sessionsBeforeLongBreakTooLarge)
        }

        return errors
    }

    /// Throws `PersistenceError.invalidConfiguration` if any rule is violated.
    func validated() throws {
        let errors = validate()
        guard errors.isEmpty else {
            throw PersistenceError.invalidConfiguration(errors)
        }
    }
}
