//
//  StatisticsInput.swift
//  time_frame
//
//  The pure, Sendable value snapshot the statistics layer aggregates over
//  (Milestone 10). Statistics are a **read-only projection of persisted history**:
//  the repository maps each `FocusSession`/`SessionInterval` into these immutable
//  values *once*, and the pure `StatisticsAggregator` computes every metric from
//  them without ever touching SwiftData, SwiftUI, or the timer engine. Keeping the
//  aggregation input a plain value type is what makes the whole statistics engine
//  deterministically testable without a store or a running UI.
//

import Foundation

/// One persisted interval, reduced to the fields statistics needs. Frozen values
/// only — never a live reference — so a metric can never change when a
/// configuration is later renamed or deleted (mirrors History's rule; ADR-019/028).
nonisolated struct IntervalStatInput: Equatable, Sendable {
    let phase: TimerPhase
    let status: IntervalStatus
    /// The interval's own frozen planned length. For a `completed` interval this is
    /// the time actually focused/rested (it ran to its planned end), which is the
    /// reliable, deterministic figure History already reports.
    let plannedDuration: TimeInterval
    let startedAt: Date?
    let endedAt: Date?
    /// The configuration name frozen on this interval (set for plan-started, possibly
    /// multi-configuration sessions; empty otherwise). The aggregator falls back to
    /// the session-level frozen name when this is empty.
    let configurationName: String

    init(
        phase: TimerPhase,
        status: IntervalStatus,
        plannedDuration: TimeInterval,
        startedAt: Date?,
        endedAt: Date?,
        configurationName: String
    ) {
        self.phase = phase
        self.status = status
        self.plannedDuration = plannedDuration
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.configurationName = configurationName
    }

    /// Whether this interval ran to its planned end (the only intervals that count
    /// toward focus/break totals — a skipped or cancelled interval was not "focused").
    var isCompleted: Bool { status == .completed }

    /// The instant this interval is attributed to a calendar day by. Prefers the end
    /// instant (the moment the focus/break was banked); falls back to the start.
    var attributionDate: Date? { endedAt ?? startedAt }
}

/// One persisted session, reduced to the fields statistics needs, together with its
/// intervals. Built once by `StatisticsRepository` (or directly from a `FocusSession`
/// in the UI); the aggregator only ever reads these values.
nonisolated struct SessionStatInput: Equatable, Sendable, Identifiable {
    let id: UUID
    let taskName: String
    /// The session-level frozen configuration name (a single config's name, or a
    /// plan summary). Used for the configuration breakdown when an interval carries
    /// no name of its own.
    let configurationName: String
    let status: SessionStatus
    let startedAt: Date?
    let endedAt: Date?
    let intervals: [IntervalStatInput]

    init(
        id: UUID,
        taskName: String,
        configurationName: String,
        status: SessionStatus,
        startedAt: Date?,
        endedAt: Date?,
        intervals: [IntervalStatInput]
    ) {
        self.id = id
        self.taskName = taskName
        self.configurationName = configurationName
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.intervals = intervals
    }

    /// Whether the session actually began (has a start instant). Planned-but-never-run
    /// sessions are excluded from every "started sessions" metric.
    var didStart: Bool { startedAt != nil }

    /// This session's total completed focus time, summed from its own completed focus
    /// intervals (used for the "longest focus session" metric).
    var completedFocusDuration: TimeInterval {
        intervals
            .filter { $0.phase == .focus && $0.isCompleted }
            .reduce(0) { $0 + $1.plannedDuration }
    }
}
