//
//  PomodoroConfigurationSnapshot.swift
//  time_frame
//
//  An immutable, Sendable snapshot of a Pomodoro configuration.
//

import Foundation

/// A validated, immutable copy of the values needed to run a session.
///
/// The timer engine operates on this value type rather than on the SwiftData
/// `PomodoroConfiguration` reference type. This keeps the engine free of any
/// persistence dependency, makes it trivially `Sendable`, and guarantees the
/// engine can never observe a configuration being mutated mid-session.
///
/// Construction validates and clamps its inputs so the rest of the engine can
/// assume sane values (positive durations, at least one session, a long-break
/// interval of at least one).
nonisolated struct PomodoroConfigurationSnapshot: Equatable, Sendable, Hashable {
    let focusDuration: TimeInterval
    let shortBreakDuration: TimeInterval
    let longBreakDuration: TimeInterval
    let sessionsBeforeLongBreak: Int
    let totalSessions: Int

    /// The smallest duration the engine will accept for any interval, in
    /// seconds. Durations at or below zero are invalid input; they are clamped
    /// up to this floor so an interval can never have a non-positive length.
    static let minimumDuration: TimeInterval = 1

    init(
        focusDuration: TimeInterval,
        shortBreakDuration: TimeInterval,
        longBreakDuration: TimeInterval,
        sessionsBeforeLongBreak: Int,
        totalSessions: Int
    ) {
        self.focusDuration = Self.sanitizedDuration(focusDuration)
        self.shortBreakDuration = Self.sanitizedDuration(shortBreakDuration)
        self.longBreakDuration = Self.sanitizedDuration(longBreakDuration)
        self.sessionsBeforeLongBreak = max(1, sessionsBeforeLongBreak)
        self.totalSessions = max(1, totalSessions)
    }

    private static func sanitizedDuration(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return minimumDuration }
        return max(minimumDuration, value)
    }

    /// Returns a copy with `totalSessions` replaced, when a non-nil override is
    /// given. Used to run a single session with a different focus-session count
    /// than the configuration's default, without mutating the configuration.
    func overriding(totalSessions: Int?) -> PomodoroConfigurationSnapshot {
        guard let totalSessions else { return self }
        return PomodoroConfigurationSnapshot(
            focusDuration: focusDuration,
            shortBreakDuration: shortBreakDuration,
            longBreakDuration: longBreakDuration,
            sessionsBeforeLongBreak: sessionsBeforeLongBreak,
            totalSessions: totalSessions
        )
    }
}

extension PomodoroConfigurationSnapshot {
    /// A conventional "classic Pomodoro" configuration (25 / 5 / 15, four
    /// sessions, long break every fourth). Useful for previews and tests.
    static let classic = PomodoroConfigurationSnapshot(
        focusDuration: 25 * 60,
        shortBreakDuration: 5 * 60,
        longBreakDuration: 15 * 60,
        sessionsBeforeLongBreak: 4,
        totalSessions: 4
    )
}
