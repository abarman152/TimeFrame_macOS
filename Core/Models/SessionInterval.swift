//
//  SessionInterval.swift
//  time_frame
//
//  A persisted single interval within a FocusSession.
//

import Foundation
import SwiftData

/// One concrete interval of a session: a focus block, a short break, or a long
/// break, together with its planned duration, ordering and actual outcome.
@Model
final class SessionInterval {
    // No `#Unique` on `id`: CloudKit mirroring does not support unique
    // constraints (ADR-061). `id` is still a stable, freshly generated identifier.
    private(set) var id: UUID = UUID()

    /// Which kind of interval this is. Stored via `TimerPhase` (Codable).
    var phase: TimerPhase = TimerPhase.focus

    /// The planned length in seconds, taken from the configuration when the
    /// session's plan was generated.
    var plannedDuration: TimeInterval = 0

    var startedAt: Date?
    var endedAt: Date?

    /// The authoritative end instant while this interval is running. Nil unless
    /// running. Persisting the target end (rather than a countdown) is what lets
    /// recovery reconstruct the interval correctly even after a pause/resume
    /// re-anchored it. See ADR-013.
    var targetEndAt: Date?

    /// The frozen remaining seconds captured when this interval was paused. Nil
    /// unless paused. This is the one place a "remaining" value is stored — a
    /// paused interval has no running target end from which to derive it. See
    /// ADR-013.
    var remainingAtPause: TimeInterval?

    /// The interval's lifecycle status. Replaces a bare `isCompleted` flag so
    /// history distinguishes completed / skipped / cancelled and the in-progress
    /// states. See `IntervalStatus`.
    var status: IntervalStatus = IntervalStatus.pending

    /// Position within the owning session's plan (0-based).
    var order: Int = 0

    /// The name of the configuration this interval was generated from, frozen when
    /// the session started. Empty for breaks and for sessions started before this
    /// field existed. This is what lets a multi-configuration plan record which
    /// configuration each focus used, keeping History accurate without a live
    /// reference (ADR-028). Defaulted so older stores migrate cleanly.
    var configurationName: String = ""

    /// The session this interval belongs to. Inverse is declared on
    /// `FocusSession.intervals`; no macro here (one side only).
    var session: FocusSession?

    init(
        phase: TimerPhase,
        plannedDuration: TimeInterval,
        order: Int,
        startedAt: Date? = nil
    ) {
        self.id = UUID()
        self.phase = phase
        self.plannedDuration = plannedDuration
        self.order = order
        self.startedAt = startedAt
    }

    /// Builds a persisted interval from an engine `PlannedInterval`.
    convenience init(planned: PlannedInterval) {
        self.init(phase: planned.phase, plannedDuration: planned.duration, order: planned.index)
    }

    /// Whether the interval ran to its planned end.
    var isCompleted: Bool { status == .completed }

    /// Whether the interval has reached a terminal state.
    var isTerminal: Bool { status.isTerminal }
}
