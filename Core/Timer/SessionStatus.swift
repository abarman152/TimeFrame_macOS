//
//  SessionStatus.swift
//  time_frame
//
//  The persisted lifecycle status of a FocusSession.
//

import Foundation

/// The durable lifecycle status of a persisted `FocusSession`.
///
/// This is deliberately **distinct from the engine's `TimerState`**. The engine
/// models the live timer (`idle`/`running`/`paused`/`completed`/`cancelled`);
/// `SessionStatus` models the *persisted* lifecycle, which additionally needs a
/// `planned` state (a session that exists but has not started) and an
/// `interrupted` state (a session the app could not safely resume, e.g. after a
/// crash with inconsistent data). Keeping the two separate lets the timer engine
/// stay free of persistence and recovery concerns. See
/// `docs/04-SESSION-LIFECYCLE.md` and `docs/DECISIONS.md` (ADR-012).
///
/// `nonisolated` so it can be constructed from any isolation domain and stored
/// on a SwiftData `@Model` (it is `String`-backed and `Codable`).
nonisolated enum SessionStatus: String, Codable, Sendable, CaseIterable, Hashable {
    /// The session has been created/planned but not yet started.
    case planned

    /// The session is active and its current interval is running.
    case running

    /// The session is active but frozen on its current interval.
    case paused

    /// Every planned interval finished normally.
    case completed

    /// The user stopped the session before its plan finished.
    case cancelled

    /// The session could not be safely resumed after the app was unavailable
    /// (crash / inconsistent persisted state). Terminal.
    case interrupted

    /// Whether the session is still active (can accept pause/resume/skip/stop).
    var isActive: Bool { self == .running || self == .paused }

    /// Whether the session has reached a terminal state.
    var isTerminal: Bool {
        self == .completed || self == .cancelled || self == .interrupted
    }

    /// Whether a persisted session in this status is a candidate for recovery on
    /// launch (it was live when the app stopped).
    var isRecoverable: Bool { self == .running || self == .paused }

    /// Maps a live engine `TimerState` onto the persisted lifecycle status.
    ///
    /// The engine has no notion of `planned` (its equivalent is `idle`) or
    /// `interrupted` (a recovery-only outcome the coordinator assigns
    /// explicitly), so `idle` maps to `planned` and `interrupted` is never
    /// produced here.
    init(_ engineState: TimerState) {
        switch engineState {
        case .idle: self = .planned
        case .running: self = .running
        case .paused: self = .paused
        case .completed: self = .completed
        case .cancelled: self = .cancelled
        }
    }
}
