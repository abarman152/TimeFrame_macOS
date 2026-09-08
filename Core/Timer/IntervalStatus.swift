//
//  IntervalStatus.swift
//  time_frame
//
//  The persisted status of a single SessionInterval.
//

import Foundation

/// The durable status of one persisted `SessionInterval`.
///
/// Richer than a simple `isCompleted` flag so history is never ambiguous: an
/// interval that ended can have ended by *completing*, being *skipped*, or being
/// *cancelled* when the whole session stopped. This mirrors the engine's
/// `IntervalOutcome` but adds the not-yet-terminal states (`pending`, `running`,
/// `paused`) that only make sense for a persisted, in-progress interval.
///
/// `nonisolated`, `String`-backed and `Codable` so it can be stored on a
/// SwiftData `@Model`.
nonisolated enum IntervalStatus: String, Codable, Sendable, CaseIterable, Hashable {
    /// Planned but not yet started.
    case pending

    /// Currently running.
    case running

    /// Started but currently frozen.
    case paused

    /// Ran to its planned end.
    case completed

    /// Ended early because the user skipped it.
    case skipped

    /// Was in progress when the whole session was stopped.
    case cancelled

    /// Whether the interval has reached a terminal state.
    var isTerminal: Bool {
        self == .completed || self == .skipped || self == .cancelled
    }

    /// Maps an engine `IntervalOutcome` (how a finished interval ended) onto the
    /// persisted terminal status.
    init(_ outcome: IntervalOutcome) {
        switch outcome {
        case .completed: self = .completed
        case .skipped: self = .skipped
        case .cancelled: self = .cancelled
        }
    }
}
