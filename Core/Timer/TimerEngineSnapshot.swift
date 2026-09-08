//
//  TimerEngineSnapshot.swift
//  time_frame
//
//  An immutable, SwiftData-free value capturing everything needed to rebuild a
//  running/paused TimerEngine after the app was unavailable.
//

import Foundation

/// A pure-value description of a `TimerEngine`'s internal state at a point in
/// time, used to *restore* an engine on app relaunch.
///
/// The engine deliberately knows nothing about SwiftData. Recovery therefore
/// happens in two layers: the persistence layer reads the stored
/// `FocusSession`/`SessionInterval` rows and assembles this plain value, then
/// hands it to `TimerEngine.restore(from:)`. The engine never imports SwiftData;
/// the value type is the seam. See `docs/DECISIONS.md` (ADR-012, ADR-014).
///
/// All timeline anchors are `Date`s (or, for a paused interval, the frozen
/// remaining seconds). Nothing here is a live countdown: after restoring, the
/// engine derives the true state from these anchors and the current clock via
/// `synchronize()`. See ADR-013.
nonisolated struct TimerEngineSnapshot: Equatable, Sendable, Hashable {
    /// The lifecycle state to restore into. Only `.running` and `.paused` are
    /// meaningful for restoration; terminal/idle sessions are not restored.
    let state: TimerState

    /// Index of the current interval within the plan.
    let currentIndex: Int

    /// History of intervals that had already ended, in order.
    let completedIntervals: [IntervalRecord]

    /// When the current interval began running (nil if unknown).
    let intervalStartDate: Date?

    /// The authoritative end of the current interval while running. Nil while
    /// paused (a frozen interval has no target end).
    let intervalEndDate: Date?

    /// The frozen remaining seconds captured at pause. Nil while running.
    let remainingWhenPaused: TimeInterval?

    init(
        state: TimerState,
        currentIndex: Int,
        completedIntervals: [IntervalRecord],
        intervalStartDate: Date?,
        intervalEndDate: Date?,
        remainingWhenPaused: TimeInterval?
    ) {
        self.state = state
        self.currentIndex = currentIndex
        self.completedIntervals = completedIntervals
        self.intervalStartDate = intervalStartDate
        self.intervalEndDate = intervalEndDate
        self.remainingWhenPaused = remainingWhenPaused
    }
}
