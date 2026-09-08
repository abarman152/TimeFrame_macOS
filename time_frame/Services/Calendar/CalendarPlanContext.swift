//
//  CalendarPlanContext.swift
//  time_frame
//
//  The pure input the CalendarEventGenerator turns into event drafts. It is a
//  framework-independent projection of a plan or a live session: everything the
//  generator needs (task, optional plan name, ordered intervals, an anchor start
//  time) and nothing about EventKit or SwiftData.
//

import Foundation

/// A framework-independent description of what to put on the calendar.
///
/// The same context type feeds both flows:
/// - **Manual plan add:** built from a `SessionPlanExecutionSnapshot` with a chosen
///   *planned* start time.
/// - **Live session:** built from the running `FocusSession` with its *actual*
///   start time (ADR-036, §31 — never a fabricated timestamp).
nonisolated struct CalendarPlanContext: Equatable, Sendable {

    /// One interval to represent.
    nonisolated struct Interval: Equatable, Sendable {
        let phase: TimerPhase
        let duration: TimeInterval
        /// Configuration name for a focus interval; empty for breaks.
        let configurationName: String
    }

    /// The task the session focuses on (may be empty).
    let taskName: String
    /// The originating plan's name, or "" for an ad-hoc / configuration session.
    let planName: String
    /// The anchor start time (planned for a manual add, actual for a live session).
    let startDate: Date
    /// The ordered intervals.
    let intervals: [Interval]

    init(taskName: String, planName: String = "", startDate: Date, intervals: [Interval]) {
        self.taskName = taskName
        self.planName = planName
        self.startDate = startDate
        self.intervals = intervals
    }

    /// The total planned duration in seconds.
    var totalDuration: TimeInterval { intervals.reduce(0) { $0 + $1.duration } }

    /// The number of focus intervals.
    var focusCount: Int { intervals.filter { $0.phase == .focus }.count }

    /// The number of break intervals.
    var breakCount: Int { intervals.filter { $0.phase.isBreak }.count }

    /// The anchor end time (start + total).
    var endDate: Date { startDate.addingTimeInterval(totalDuration) }

    /// A best-effort single title for the whole session: the task, else the plan
    /// name, else a neutral default.
    var defaultTitle: String {
        if !taskName.isEmpty { return taskName }
        if !planName.isEmpty { return planName }
        return "Focus session"
    }

    /// The distinct focus configuration names, in first-seen order.
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
}

extension CalendarPlanContext {
    /// Builds a context from a frozen plan snapshot and a chosen planned start.
    init(snapshot: SessionPlanExecutionSnapshot, planName: String, startDate: Date) {
        self.init(
            taskName: snapshot.taskName,
            planName: planName,
            startDate: startDate,
            intervals: snapshot.intervals.map {
                Interval(phase: $0.phase, duration: $0.duration, configurationName: $0.configurationName)
            }
        )
    }
}
