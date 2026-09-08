//
//  TimerState.swift
//  time_frame
//
//  The explicit states of the timer/session state machine.
//

import Foundation

/// The lifecycle state of a running Pomodoro session.
///
/// The engine is modelled as an explicit finite state machine. Only the
/// transitions documented in `docs/03-TIMER-ENGINE.md` are permitted; the
/// engine ignores control messages that do not apply to its current state.
nonisolated enum TimerState: String, Codable, Sendable, CaseIterable, Hashable {
    /// No session is active. The engine is waiting for `start`.
    case idle

    /// A session is active and its current interval is counting down.
    case running

    /// A session is active but its current interval is frozen.
    case paused

    /// Every planned interval has finished normally.
    case completed

    /// The session was stopped before its plan finished.
    case cancelled

    /// Whether the session is still active (able to accept pause/skip/etc.).
    var isActive: Bool { self == .running || self == .paused }

    /// Whether the session has reached a terminal state.
    var isTerminal: Bool { self == .completed || self == .cancelled }
}
