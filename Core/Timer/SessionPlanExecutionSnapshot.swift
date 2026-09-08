//
//  SessionPlanExecutionSnapshot.swift
//  time_frame
//
//  The immutable value that freezes a Session Plan at the instant it is started,
//  so the running session is independent of any later edit to the saved plan or
//  its configurations. This is the boundary between the (mutable, SwiftData)
//  planning layer and the existing execution architecture (ADR-028).
//

import Foundation

/// An immutable, `Sendable` freeze of a plan ready to execute.
///
/// A plan can be edited, its configurations renamed, or the plan itself deleted
/// after a session starts; none of that may affect the running session. The
/// snapshot guarantees this structurally: it copies every value the execution path
/// needs (task name, ordered intervals with their frozen phase, duration, and
/// configuration name) and holds **no** reference to the `SessionPlan`, its items,
/// or any `PomodoroConfiguration`. It is what `SessionCoordinator.startPlan` runs
/// from — never the live SwiftData objects.
///
/// The engine only needs each interval's phase and duration (`enginePlan`); the
/// per-interval `configurationName` is carried through so the persisted
/// `SessionInterval`s record which configuration each focus used, keeping History
/// accurate for multi-configuration plans without a live reference.
nonisolated struct SessionPlanExecutionSnapshot: Equatable, Sendable {

    /// One frozen interval to execute.
    nonisolated struct Interval: Equatable, Sendable {
        let index: Int
        let phase: TimerPhase
        let duration: TimeInterval
        /// The configuration name for a focus interval; empty for breaks.
        let configurationName: String
    }

    /// The task the session focuses on (copied from the plan).
    let taskName: String

    /// The intervals to run, already ordered and re-indexed from 0.
    let intervals: [Interval]

    /// Builds a snapshot from ordered plan-item values. Items are sorted by their
    /// `order` and re-indexed contiguously from 0, so the engine plan never has a
    /// gap regardless of how the items were stored.
    init(taskName: String, items: [PlanItemDraft]) {
        self.taskName = taskName
        self.intervals = items
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { offset, item in
                Interval(
                    index: offset,
                    phase: item.phase,
                    duration: item.duration,
                    configurationName: item.isFocus ? item.configurationName : ""
                )
            }
    }

    /// The engine plan (phase + duration only) this snapshot executes through the
    /// existing `TimerEngine` — no second timer implementation (ADR-028).
    var enginePlan: IntervalPlan {
        IntervalPlan(intervals: intervals.map {
            PlannedInterval(index: $0.index, phase: $0.phase, duration: $0.duration)
        })
    }

    /// Whether the snapshot has any interval to run.
    var isEmpty: Bool { intervals.isEmpty }

    /// The total planned duration in seconds (pure arithmetic).
    var totalDuration: TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }

    /// The number of focus intervals.
    var focusCount: Int {
        intervals.filter { $0.phase == .focus }.count
    }

    /// The distinct configuration names used by focus intervals, in first-seen
    /// order. Empty names (breaks) are ignored.
    var focusConfigurationNames: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for interval in intervals where interval.phase == .focus && !interval.configurationName.isEmpty {
            if seen.insert(interval.configurationName).inserted {
                result.append(interval.configurationName)
            }
        }
        return result
    }

    /// A single configuration label for the whole session: the one configuration
    /// name when every focus uses the same one, "Multiple configurations" when they
    /// differ, or "" when no focus names a configuration. Frozen onto the
    /// `FocusSession` for a readable History entry.
    var summaryConfigurationName: String {
        let names = focusConfigurationNames
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return "Multiple configurations"
        }
    }
}
