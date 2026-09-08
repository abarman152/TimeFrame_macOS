//
//  StatisticsSnapshot.swift
//  time_frame
//
//  The immutable result of aggregating persisted history over a date range
//  (Milestone 10). A snapshot is a pure value: given the same inputs, range and
//  calendar, `StatisticsAggregator` always produces the same snapshot, so statistics
//  are fully reproducible from history and need never be persisted (the store stays
//  the single source of truth; no second analytics database — see docs/19-STATISTICS.md).
//

import Foundation

/// Focus totals for one calendar day, used by the daily breakdown and the day charts.
nonisolated struct DailyStatistics: Equatable, Sendable, Identifiable {
    /// Start of the calendar day this bucket represents.
    let date: Date
    let focusDuration: TimeInterval
    let breakDuration: TimeInterval
    let completedFocusIntervals: Int
    /// Sessions that both started this day and completed (for the "sessions completed" chart).
    let completedSessions: Int

    var id: Date { date }

    /// Whether any focus time landed on this day (used to skip empty days when ranking).
    var hasFocus: Bool { focusDuration > 0 }
}

/// Focus time grouped by (frozen) configuration name.
nonisolated struct ConfigurationStatistics: Equatable, Sendable, Identifiable {
    let configurationName: String
    let focusDuration: TimeInterval
    let completedFocusIntervals: Int

    var id: String { configurationName }
}

/// A current-vs-previous focus-time comparison for trends. Percentage change is
/// `nil` when the previous period had zero focus (division by zero is never reported
/// as a number).
nonisolated struct StatisticsComparison: Equatable, Sendable {
    let current: TimeInterval
    let previous: TimeInterval

    /// Signed difference (positive when the current period focused more).
    var absoluteDifference: TimeInterval { current - previous }

    /// Signed fractional change (e.g. `0.226` for +22.6%). `nil` when `previous == 0`.
    var percentageChange: Double? {
        previous == 0 ? nil : (current - previous) / previous
    }

    /// The direction of change, for a paired label/icon (colour is never the sole cue).
    var direction: Direction {
        if current > previous { return .up }
        if current < previous { return .down }
        return .flat
    }

    nonisolated enum Direction: Sendable { case up, down, flat }
}

/// Everything the Statistics UI (and the Today summary) needs for one period, derived
/// purely from history. Read-only: producing a snapshot never mutates any model.
nonisolated struct StatisticsSnapshot: Equatable, Sendable {
    let range: StatisticsDateRange

    // MARK: Session metrics
    /// Sessions that started within the range (by `startedAt`).
    let startedSessions: Int
    /// Started sessions whose lifecycle status is `completed`.
    let completedSessions: Int
    /// Sessions the user stopped before the plan finished (`cancelled`).
    let stoppedSessions: Int
    /// Sessions that could not be safely recovered (`interrupted`).
    let interruptedSessions: Int

    // MARK: Focus / break totals (completed intervals only)
    let focusDuration: TimeInterval
    let breakDuration: TimeInterval
    /// Number of focus intervals that ran to completion within the range.
    let completedFocusIntervals: Int
    /// The largest single-session total completed-focus time among sessions in range.
    let longestFocusSession: TimeInterval

    // MARK: Breakdowns
    /// One entry per calendar day in the range, ascending. Days with no activity are
    /// still present (zero-valued) so charts show a continuous axis.
    let daily: [DailyStatistics]
    /// Focus time per configuration name, descending by focus time.
    let configurations: [ConfigurationStatistics]

    // MARK: Derived

    /// Completed ÷ started. `nil` when no session started (never a divide-by-zero).
    var completionRate: Double? {
        startedSessions == 0 ? nil : Double(completedSessions) / Double(startedSessions)
    }

    /// Mean completed-focus interval length. `nil` when there were no completed focus
    /// intervals.
    var averageFocusInterval: TimeInterval? {
        completedFocusIntervals == 0 ? nil : focusDuration / Double(completedFocusIntervals)
    }

    /// The day with the most focus time, or `nil` when no day had any focus (so the UI
    /// never claims a "most productive day" without data to support it).
    var mostProductiveDay: DailyStatistics? {
        daily.filter(\.hasFocus).max { $0.focusDuration < $1.focusDuration }
    }

    /// Whether the range recorded no activity at all (no started session, no focus).
    var isEmpty: Bool {
        startedSessions == 0 && focusDuration == 0 && completedFocusIntervals == 0
    }
}
