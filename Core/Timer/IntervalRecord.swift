//
//  IntervalRecord.swift
//  time_frame
//
//  The engine's in-memory history of intervals that have already ended.
//

import Foundation

/// How an interval ended.
nonisolated enum IntervalOutcome: String, Codable, Sendable, Hashable {
    /// The interval ran to its planned end.
    case completed
    /// The user skipped the interval before it finished.
    case skipped
    /// The interval was in progress when the whole session was stopped.
    case cancelled
}

/// An immutable record of an interval that has finished, kept by the engine so
/// that skipping or stopping never silently discards session history.
nonisolated struct IntervalRecord: Equatable, Sendable, Hashable {
    let index: Int
    let phase: TimerPhase
    let plannedDuration: TimeInterval
    let startedAt: Date
    let endedAt: Date
    let outcome: IntervalOutcome
}
