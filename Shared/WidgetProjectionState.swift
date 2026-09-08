//
//  WidgetProjectionState.swift
//  Time Frame — shared widget projection (Milestone 11)
//
//  The neutral vocabulary the widget projection speaks. These enums are deliberately
//  independent of the domain's `TimerState`/`TimerPhase` (which live in the app target
//  and import nothing widget-related): the projection is a *value copy* the app writes
//  and the widget reads, never a shared reference to live timer state (ADR-055).
//
//  Both enums decode **defensively**: an unknown raw value from a newer app writing an
//  older-read widget (or a corrupt payload) resolves to a safe fallback instead of
//  throwing, so the widget can always render *something* and never crashes on bad data.
//
//  This file is compiled into BOTH the app target and the widget extension. It imports
//  only Foundation — no SwiftData, no WidgetKit, no TimerEngine.
//

import Foundation

/// The coarse situation the widget renders. Mirrors the menu bar's `Situation` plus an
/// explicit `unavailable` case for when no projection could be read (missing App Group,
/// corrupt payload, or a first launch before the app has written anything).
public enum WidgetSessionState: String, Codable, Sendable, CaseIterable, Hashable {
    /// No active or recently-finished session — the calm "Ready to focus" state.
    case idle
    /// A session is running (focus or break) and its interval is counting down.
    case running
    /// A session is active but frozen on its current interval.
    case paused
    /// Every planned interval finished normally.
    case completed
    /// The app could not safely resume a session after relaunch.
    case interrupted
    /// No trustworthy projection could be read. The widget shows a stable fallback.
    case unavailable

    /// Whether a session is live (running or paused).
    public var isActive: Bool { self == .running || self == .paused }

    /// Decodes defensively: an unknown string resolves to `.unavailable` rather than
    /// throwing, so a forward-incompatible or corrupt payload degrades gracefully.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetSessionState(rawValue: raw) ?? .unavailable
    }
}

/// The current interval's phase, or `none` when nothing is counting down.
public enum WidgetPhase: String, Codable, Sendable, CaseIterable, Hashable {
    case focus
    case shortBreak
    case longBreak
    /// No active interval (idle / completed / interrupted / unavailable).
    case none

    /// Whether this phase represents working time.
    public var isFocus: Bool { self == .focus }

    /// Whether this phase represents a break (short or long).
    public var isBreak: Bool { self == .shortBreak || self == .longBreak }

    /// Decodes defensively: an unknown string resolves to `.none`.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetPhase(rawValue: raw) ?? WidgetPhase.none
    }
}

/// The direction of today's focus versus the equivalent prior day, for a glanceable trend
/// on the statistics widget (Milestone 14). The app derives this from the SAME
/// `StatisticsAggregator` the dashboard uses (today vs yesterday) and freezes it into the
/// projection — the widget never computes it, it only renders a paired arrow + label so the
/// trend is never conveyed by colour alone.
public enum WidgetFocusTrend: String, Codable, Sendable, CaseIterable, Hashable {
    /// Focused more today than the prior day.
    case up
    /// Focused less today than the prior day.
    case down
    /// The same (or no meaningful change).
    case steady

    /// Decodes defensively: an unknown string resolves to `.steady`.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetFocusTrend(rawValue: raw) ?? .steady
    }
}
