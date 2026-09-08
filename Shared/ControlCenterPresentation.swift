//
//  ControlCenterPresentation.swift
//  Time Frame — shared Control Center projection (Milestone 22)
//
//  The pure, Foundation-only decision layer behind Time Frame's iOS Control Center controls
//  (WidgetKit `ControlWidget`). Given the frozen `WidgetProjection` the app already writes to the
//  App Group (Milestone 11), it answers three questions and nothing else:
//
//    • what *situation* is the timer in, as a compact `ControlCenterSessionState`;
//    • which controls make *semantic sense* in that situation (`ControlCenterControlSet`);
//    • what a control should *look and read like* — title, SF Symbol, VoiceOver label
//      (`ControlCenterActionCatalog` / `ControlCenterPresentation`).
//
//  It is a *presentation* projection, never a second source of truth. It computes no elapsed time,
//  owns no timer, decrements no counter, reaches no coordinator, and touches no store: the live
//  "ticking" (where a control shows one) is left to WidgetKit between the projection's frozen
//  anchors, exactly like every other widget surface (ADR-055/090). The action a control performs is
//  the Milestone-15 `WidgetControlAction`, routed by the widget's `ControlWidgetButton` through the
//  ONE existing seam (`WidgetControlActions → AppIntentSessionActions → SessionCoordinator`) — this
//  file never performs it, so there is no second mutation path.
//
//  Compiled into BOTH the app target and the iOS widget extension (explicit membership; `Shared/`
//  is not a synchronized group). Foundation-only: no WidgetKit, no AppIntents, no SwiftUI, no
//  ActivityKit, no SwiftData, no CloudKit — so the whole decision layer is unit-testable without a
//  WidgetKit host and can never drift into a clock (ADR-091).
//

import Foundation

// MARK: - Situation

/// The compact situation a Control Center control switches on. Distinct from `WidgetSessionState`
/// only in that it splits `running` into focus vs break (a break can't be paused, so the primary
/// control offers *skip* instead) — everything else maps 1:1. It is derived purely from the
/// projection's `state` + `phase`; it never reads a clock.
public enum ControlCenterSessionState: String, Sendable, CaseIterable, Hashable, Codable {
    /// No active or recently-finished session — the calm "ready to focus" situation.
    case idle
    /// A focus interval is counting down.
    case focusRunning
    /// A break interval is counting down.
    case breakRunning
    /// A session is active but frozen on its current interval.
    case paused
    /// Every planned interval finished normally.
    case completed
    /// The app could not safely resume a session after relaunch.
    case interrupted
    /// No trustworthy projection could be read (missing App Group, corrupt payload, or a first
    /// launch before the app wrote anything). Treated as "offer Start" — the app validates.
    case unavailable

    /// Derives the situation from the read-only widget projection.
    public init(projection: WidgetProjection) {
        self.init(state: projection.state, phase: projection.phase)
    }

    /// Derives the situation from the neutral projection vocabulary. Pure; no clock, no domain.
    public init(state: WidgetSessionState, phase: WidgetPhase) {
        switch state {
        case .idle:        self = .idle
        case .running:     self = phase.isBreak ? .breakRunning : .focusRunning
        case .paused:      self = .paused
        case .completed:   self = .completed
        case .interrupted: self = .interrupted
        case .unavailable: self = .unavailable
        }
    }

    /// Whether a session is live (running focus, running break, or paused). Drives whether a
    /// dedicated Stop control is enabled.
    public var isActive: Bool {
        self == .focusRunning || self == .breakRunning || self == .paused
    }

    /// Whether an interval is actively counting down (focus or break, not paused).
    public var isRunning: Bool {
        self == .focusRunning || self == .breakRunning
    }
}

// MARK: - Which controls make sense

/// The pure decision of which controls are semantically valid in a situation, and which single
/// control is the *primary* one a one-tap Control Center button should perform. Mirrors the
/// Milestone-15 `WidgetControlSet` philosophy (a break offers skip, not pause) so the two surfaces
/// never disagree, and is unit-testable without any WidgetKit host (ADR-090).
public enum ControlCenterControlSet {

    /// The controls that make sense to offer in the given situation, in a sensible order. A
    /// dedicated Control Center control should only be *enabled* when its action is in this set.
    public static func controls(for state: ControlCenterSessionState) -> [WidgetControlAction] {
        switch state {
        case .idle, .completed, .interrupted, .unavailable:
            return [.start]
        case .focusRunning:
            return [.pause, .skip, .stop]
        case .breakRunning:
            // A break can't be paused meaningfully; skip advances it, stop ends the session.
            return [.skip, .stop]
        case .paused:
            return [.resume, .stop]
        }
    }

    /// The single most relevant action for a one-tap adaptive control in the given situation.
    /// Idle/finished → start; running focus → pause; running break → skip; paused → resume.
    /// Deterministic and total (every state resolves to exactly one action).
    public static func primaryAction(for state: ControlCenterSessionState) -> WidgetControlAction {
        switch state {
        case .idle, .completed, .interrupted, .unavailable:
            return .start
        case .focusRunning:
            return .pause
        case .breakRunning:
            return .skip
        case .paused:
            return .resume
        }
    }

    /// Whether the given action is offered (enabled) in the given situation.
    public static func isAvailable(_ action: WidgetControlAction, in state: ControlCenterSessionState) -> Bool {
        controls(for: state).contains(action)
    }
}

// MARK: - Appearance of a single action

/// The look-and-read of one control action: the short visible title, the SF Symbol, and a
/// VoiceOver label that never relies on the glyph or colour alone (Part 6 / ADR-090). A pure value.
public struct ControlCenterActionAppearance: Sendable, Equatable, Hashable {
    /// The action this appearance is for.
    public let action: WidgetControlAction
    /// The short visible button title, e.g. "Pause".
    public let title: String
    /// The SF Symbol name, e.g. "pause.fill".
    public let symbolName: String
    /// The full spoken label, e.g. "Pause focus timer" — always a complete sentence-like phrase so
    /// the control is meaningful to VoiceOver without seeing the symbol.
    public let accessibilityLabel: String

    public init(action: WidgetControlAction, title: String, symbolName: String, accessibilityLabel: String) {
        self.action = action
        self.title = title
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
    }
}

/// The single source of truth for how each control action looks and reads in Control Center. Kept
/// here (not in the widget view) so the appearance is unit-testable and the app and the widget can
/// never drift. SF Symbols and phrasing intentionally mirror the app's own control vocabulary.
public enum ControlCenterActionCatalog {

    /// The appearance for a control action. Total over the closed `WidgetControlAction` set.
    public static func appearance(for action: WidgetControlAction) -> ControlCenterActionAppearance {
        switch action {
        case .start:
            return ControlCenterActionAppearance(
                action: .start, title: "Start Timer", symbolName: "play.fill",
                accessibilityLabel: "Start Timer")
        case .pause:
            return ControlCenterActionAppearance(
                action: .pause, title: "Pause", symbolName: "pause.fill",
                accessibilityLabel: "Pause Focus Timer")
        case .resume:
            return ControlCenterActionAppearance(
                action: .resume, title: "Resume", symbolName: "play.fill",
                accessibilityLabel: "Resume Focus Timer")
        case .skip:
            return ControlCenterActionAppearance(
                action: .skip, title: "Skip", symbolName: "forward.end.fill",
                accessibilityLabel: "Skip Interval")
        case .stop:
            return ControlCenterActionAppearance(
                action: .stop, title: "Stop", symbolName: "stop.fill",
                accessibilityLabel: "Stop Timer")
        case .restart:
            return ControlCenterActionAppearance(
                action: .restart, title: "Restart", symbolName: "arrow.counterclockwise",
                accessibilityLabel: "Restart Interval")
        }
    }
}

// MARK: - Primary (adaptive) control content

/// Everything the adaptive "Time Frame" Control Center control needs to render for the current
/// situation: the resolved primary action and its appearance, plus whether a session is active (so
/// the control can tint itself as "on"). It carries NO countdown and NO elapsed time — the control
/// is a command surface, not a live readout (ADR-090). Produced by the widget's value provider from
/// the projection; consumed by the control body.
public struct ControlCenterPrimaryContent: Sendable, Equatable, Hashable {
    /// The situation this content was derived from.
    public let state: ControlCenterSessionState
    /// The single action the button performs when tapped.
    public let action: WidgetControlAction
    /// The short visible title.
    public let title: String
    /// The SF Symbol name.
    public let symbolName: String
    /// The full spoken VoiceOver label.
    public let accessibilityLabel: String

    public init(state: ControlCenterSessionState, appearance: ControlCenterActionAppearance) {
        self.state = state
        self.action = appearance.action
        self.title = appearance.title
        self.symbolName = appearance.symbolName
        self.accessibilityLabel = appearance.accessibilityLabel
    }

    /// Whether a session is live (drives the control's on/off tint & value label).
    public var isActive: Bool { state.isActive }
}

/// Derives the presentation values a `ControlWidget` renders. Pure and deterministic.
public enum ControlCenterPresentation {

    /// The adaptive primary control's content for a situation. When no trustworthy projection could
    /// be read, this returns the calm "Start Timer" content (`.unavailable → .start`), so a freshly
    /// added control before the app has written anything still shows a sensible, safe action.
    public static func primary(for state: ControlCenterSessionState) -> ControlCenterPrimaryContent {
        let action = ControlCenterControlSet.primaryAction(for: state)
        return ControlCenterPrimaryContent(
            state: state,
            appearance: ControlCenterActionCatalog.appearance(for: action))
    }

    /// Convenience: the adaptive primary content straight from a projection.
    public static func primary(for projection: WidgetProjection) -> ControlCenterPrimaryContent {
        primary(for: ControlCenterSessionState(projection: projection))
    }
}

// MARK: - Configurable quick-start control content (Milestone 23)

/// The look-and-read of the configurable quick-start Control Center control for a given selected
/// timer. It never carries a countdown or elapsed time — the control is a command surface, not a
/// live readout. Pure value; derived only from the selected timer's frozen name (ADR-093).
public struct QuickStartControlContent: Sendable, Equatable, Hashable {
    /// The short visible tile title, e.g. "Deep Work" (or "Start Timer" when nothing is selected).
    public let title: String
    /// The SF Symbol name — always the start glyph.
    public let symbolName: String
    /// The full spoken VoiceOver label, e.g. "Start Deep Work Timer" — a complete phrase that
    /// never relies on the glyph or colour alone.
    public let accessibilityLabel: String
    /// Whether a specific saved timer is selected (vs. the default-configuration fallback).
    public let hasSelection: Bool

    public init(title: String, symbolName: String, accessibilityLabel: String, hasSelection: Bool) {
        self.title = title
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
        self.hasSelection = hasSelection
    }
}

/// Derives the configurable quick-start control's presentation from the selected timer's name.
/// Pure and deterministic: no store, no clock, no domain — the widget passes in the frozen name
/// carried by the configured entity (or `nil` when the user hasn't chosen / the choice was
/// deleted), and this returns the title + VoiceOver phrasing to render (ADR-093/094).
public enum QuickStartControlPresentation {

    /// The content for a selected timer name. A `nil` or blank name is the "no selection" (or
    /// "selection deleted") case, which reads as a plain "Start Timer" that starts the user's
    /// default configuration — a sensible, safe fallback the app validates.
    public static func content(timerName: String?) -> QuickStartControlContent {
        let trimmed = timerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = trimmed, !name.isEmpty {
            return QuickStartControlContent(
                title: name,
                symbolName: "play.fill",
                accessibilityLabel: "Start \(name) Timer",
                hasSelection: true)
        }
        return QuickStartControlContent(
            title: "Start Timer",
            symbolName: "play.fill",
            accessibilityLabel: "Start Focus Timer",
            hasSelection: false)
    }
}
