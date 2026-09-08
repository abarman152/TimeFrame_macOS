//
//  TimerPhase.swift
//  time_frame
//
//  Domain vocabulary shared by the timer engine and the persistence layer.
//

import Foundation

/// The kind of interval a Pomodoro session moves through.
///
/// `TimerPhase` is deliberately independent of both SwiftUI and SwiftData so it
/// can be reused by the pure timer engine, the generated session plan, and the
/// persisted `SessionInterval` model without any of those layers depending on
/// each other.
nonisolated enum TimerPhase: String, Codable, Sendable, CaseIterable, Hashable {
    case focus
    case shortBreak
    case longBreak

    /// Whether this phase represents working time (as opposed to a break).
    var isFocus: Bool { self == .focus }

    /// Whether this phase represents a break (short or long).
    var isBreak: Bool { !isFocus }
}
