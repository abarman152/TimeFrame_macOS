//
//  IntervalPlan.swift
//  time_frame
//
//  The ordered sequence of intervals the timer engine runs through. Pure value
//  types — trivially testable. This is the *execution* plan the engine consumes;
//  it is distinct from the user-designed, persisted `SessionPlan` model, which is
//  a planning entity that freezes into one of these before execution (ADR-026/031).
//

import Foundation

/// A single planned interval in a session: what kind it is, how long it should
/// last, and where it sits in the sequence.
nonisolated struct PlannedInterval: Equatable, Sendable, Hashable {
    /// Zero-based position of this interval within the plan.
    let index: Int
    /// The kind of interval (focus / short break / long break).
    let phase: TimerPhase
    /// The interval's planned duration in seconds.
    let duration: TimeInterval
}

/// The full ordered sequence of intervals for one session, generated from a
/// configuration.
///
/// The sequence is *never* hardcoded. For a configuration with N focus
/// sessions and a long-break interval of L, the plan is:
///
///     focus, break, focus, break, … , focus, break
///
/// where the break after focus number *k* is a long break when `k % L == 0`
/// and a short break otherwise. A break follows every focus block (including
/// the last), so a 4-session / interval-4 configuration produces:
///
///     Focus, Short, Focus, Short, Focus, Short, Focus, Long
///
/// See `docs/03-TIMER-ENGINE.md` for the sequencing rules and the rationale for
/// the trailing break. (The Session Planner, by contrast, makes the trailing break
/// optional — see `SessionPlanGenerator` and `docs/14-SESSION-PLANNER.md`.)
nonisolated struct IntervalPlan: Equatable, Sendable {
    /// The generated intervals, in execution order.
    let intervals: [PlannedInterval]

    /// Builds a plan from a validated configuration snapshot.
    init(configuration: PomodoroConfigurationSnapshot) {
        var built: [PlannedInterval] = []
        var index = 0

        let totalSessions = max(1, configuration.totalSessions)
        let longBreakInterval = max(1, configuration.sessionsBeforeLongBreak)

        for focusNumber in 1...totalSessions {
            built.append(
                PlannedInterval(index: index, phase: .focus, duration: configuration.focusDuration)
            )
            index += 1

            let isLongBreak = focusNumber % longBreakInterval == 0
            let breakPhase: TimerPhase = isLongBreak ? .longBreak : .shortBreak
            let breakDuration = isLongBreak
                ? configuration.longBreakDuration
                : configuration.shortBreakDuration

            built.append(
                PlannedInterval(index: index, phase: breakPhase, duration: breakDuration)
            )
            index += 1
        }

        self.intervals = built
    }

    /// Direct initializer for tests, previews, and Session Plan execution.
    init(intervals: [PlannedInterval]) {
        self.intervals = intervals
    }

    /// The number of intervals in the plan.
    var count: Int { intervals.count }

    /// Whether the plan contains no intervals.
    var isEmpty: Bool { intervals.isEmpty }

    /// The interval at `index`, or `nil` if the index is out of bounds.
    func interval(at index: Int) -> PlannedInterval? {
        guard intervals.indices.contains(index) else { return nil }
        return intervals[index]
    }
}
