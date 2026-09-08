//
//  NotificationSessionSnapshot.swift
//  time_frame
//
//  A pure, `Sendable` projection of a running `FocusSession`, taken on the main actor
//  before any notification work is deferred — so no SwiftData model ever crosses the
//  async boundary (the same discipline the Calendar layer uses with `LivePayload`).
//  It carries exactly what the scheduler needs to lay out the session's upcoming
//  transitions from the engine's authoritative timeline.
//

import Foundation

/// A framework-independent description of a running session's timeline, sufficient to
/// derive every upcoming interval-start notification and the completion notification.
nonisolated struct NotificationSessionSnapshot: Equatable, Sendable {

    /// One interval in the session's plan.
    nonisolated struct Interval: Equatable, Sendable {
        let index: Int
        let phase: TimerPhase
        let duration: TimeInterval
        /// Configuration name for a focus interval; empty for breaks.
        let configurationName: String
    }

    /// The session's stable id (the cancellation / dedup key).
    let sessionID: UUID
    /// The task name (may be empty).
    let taskName: String
    /// Index of the interval currently running.
    let currentIndex: Int
    /// The authoritative end of the current interval (`targetEndAt`), from which every
    /// later boundary is derived. This is the engine's timeline, never a fabricated
    /// value (§23/§31).
    let currentIntervalEnd: Date
    /// All intervals in planned order.
    let intervals: [Interval]

    /// The total number of focus intervals in the whole plan.
    var totalFocusCount: Int { intervals.filter { $0.phase == .focus }.count }
}

extension NotificationSessionSnapshot {
    /// Builds a snapshot from a live `FocusSession`, or nil if it has no running
    /// current interval with an authoritative end (nothing to schedule). Must be
    /// called on the main actor (it reads the SwiftData model).
    @MainActor
    init?(session: FocusSession) {
        let ordered = session.orderedIntervals
        guard !ordered.isEmpty else { return nil }
        let index = session.currentIntervalIndex
        guard let current = ordered.first(where: { $0.order == index }),
              let end = current.targetEndAt else { return nil }

        self.sessionID = session.id
        self.taskName = session.taskName
        self.currentIndex = index
        self.currentIntervalEnd = end
        self.intervals = ordered.map {
            Interval(index: $0.order,
                     phase: $0.phase,
                     duration: $0.plannedDuration,
                     configurationName: $0.configurationName)
        }
    }
}
