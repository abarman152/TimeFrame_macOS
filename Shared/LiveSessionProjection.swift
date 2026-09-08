//
//  LiveSessionProjection.swift
//  Time Frame — shared live-session projection (Milestone 16)
//
//  The PURE, Foundation-only value model for a live Time Frame session surface. It is a
//  *projection* of the one authoritative `TimerEngine`/`SessionCoordinator` state — never a second
//  source of truth (ADR-072). A live surface renders from this immutable snapshot; it owns no
//  timer, decrements no counter, and reconstructs no Pomodoro sequencing.
//
//  PLATFORM NOTE (ADR-076): ActivityKit / Live Activities are `@available(macOS, unavailable)` —
//  the framework ships in the macOS SDK only for Mac Catalyst. Time Frame is a *native* macOS app,
//  so it cannot host a Live Activity. These types are therefore the platform-neutral CORE, built
//  and tested now as architectural preparation: a future iOS/iPadOS companion target adds the tiny
//  ActivityKit layer by declaring
//
//      struct TimeFrameLiveActivityAttributes: ActivityAttributes {
//          typealias ContentState = TimeFrameLiveActivityContent   // ← this file
//          let sessionID: UUID; let taskName: String
//          let configurationName: String; let sessionStartedAt: Date
//      }
//
//  and reusing everything here unchanged. See `docs/25-LIVE-ACTIVITIES.md`.
//
//  Timestamps (`phaseStartedAt`/`phaseTargetEndAt`) are frozen at write time so a live surface can
//  render a countdown with `Text(timerInterval:)` *without* running a clock of its own.
//  `pausedRemainingSeconds` carries the frozen remaining while paused so the surface never
//  pretends a paused interval is advancing (matching the widget, ADR-055).
//
//  Compiled into BOTH the app target and the widget extension. Foundation-only: it imports no
//  ActivityKit, WidgetKit, SwiftUI, SwiftData, or domain.
//

import Foundation

/// The coarse run-state a live session surface switches on. Deliberately smaller than the
/// widget's `WidgetSessionState`: such a surface only exists while (or just after) a session runs,
/// so there is no `idle`/`unavailable` case — an absent surface models those.
public nonisolated enum LiveActivityRunState: String, Codable, Sendable, CaseIterable, Hashable {
    /// The session is running (focus or break) and its interval is counting down.
    case running
    /// The session is active but frozen on its current interval.
    case paused
    /// Every planned interval finished normally.
    case completed
    /// The session ended without completing (stopped by the user, or interrupted).
    case interrupted

    /// Whether a session is live (running or paused).
    public var isActive: Bool { self == .running || self == .paused }

    /// Whether this is a terminal state the surface should wind down from.
    public var isTerminal: Bool { self == .completed || self == .interrupted }

    /// Decodes defensively: an unknown string resolves to `.running` so a forward-incompatible
    /// payload keeps showing the session rather than crashing the surface.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LiveActivityRunState(rawValue: raw) ?? .running
    }
}

/// The immutable dynamic state a live surface renders right now — intended to be used directly as
/// a future `ActivityAttributes.ContentState`. A pure value copy the app writes; never a shared
/// reference to live timer state. Reuses the shared `WidgetPhase` vocabulary so the read-only
/// surfaces speak the same language.
public nonisolated struct TimeFrameLiveActivityContent: Codable, Sendable, Hashable {

    /// The coarse situation the surface switches on.
    public var runState: LiveActivityRunState
    /// The current interval's phase (`.none` only in a terminal state).
    public var phase: WidgetPhase
    /// The current interval's start instant (frozen). Anchors a live `Text(timerInterval:)`.
    public var phaseStartedAt: Date?
    /// The current interval's planned end instant (frozen). The countdown target.
    public var phaseTargetEndAt: Date?
    /// The frozen remaining seconds while paused (never negative). `nil` unless paused.
    public var pausedRemainingSeconds: TimeInterval?

    /// The 1-based focus-session number in progress (0 when in a break with no number to show).
    public var sessionIndex: Int
    /// The total number of focus sessions in the plan.
    public var totalFocusSessions: Int
    /// How many focus sessions have fully completed (for progress indication).
    public var completedFocusCount: Int

    /// The phase that follows the current one (`.none` when nothing follows).
    public var nextPhase: WidgetPhase
    /// The projected planned end of the *next* phase (frozen), or `nil` when unknown/terminal.
    public var nextPhaseTargetEndAt: Date?

    public init(
        runState: LiveActivityRunState,
        phase: WidgetPhase,
        phaseStartedAt: Date? = nil,
        phaseTargetEndAt: Date? = nil,
        pausedRemainingSeconds: TimeInterval? = nil,
        sessionIndex: Int = 0,
        totalFocusSessions: Int = 0,
        completedFocusCount: Int = 0,
        nextPhase: WidgetPhase = .none,
        nextPhaseTargetEndAt: Date? = nil
    ) {
        self.runState = runState
        self.phase = phase
        self.phaseStartedAt = phaseStartedAt
        self.phaseTargetEndAt = phaseTargetEndAt
        self.pausedRemainingSeconds = pausedRemainingSeconds
        self.sessionIndex = sessionIndex
        self.totalFocusSessions = totalFocusSessions
        self.completedFocusCount = completedFocusCount
        self.nextPhase = nextPhase
        self.nextPhaseTargetEndAt = nextPhaseTargetEndAt
    }

    /// Whether the session is currently paused (drives the static-vs-countdown rendering).
    public var isPaused: Bool { runState == .paused }
}

/// The immutable, per-session *static* identity — the part a future `ActivityAttributes` freezes
/// for the whole life of one activity. `sessionID` is the stable association key: surface identity
/// is derived from the Time Frame session identity, never from the task or configuration name
/// (ADR-073).
public nonisolated struct LiveActivityIdentity: Codable, Sendable, Hashable {
    /// The authoritative `FocusSession.id`. The one and only surface-identity key.
    public var sessionID: UUID
    /// The session's task label at start (may be empty).
    public var taskName: String
    /// The session's frozen configuration/plan name.
    public var configurationName: String
    /// When the session started (the app's clock, frozen).
    public var sessionStartedAt: Date

    public init(sessionID: UUID, taskName: String, configurationName: String, sessionStartedAt: Date) {
        self.sessionID = sessionID
        self.taskName = taskName
        self.configurationName = configurationName
        self.sessionStartedAt = sessionStartedAt
    }
}

/// A complete live-session projection: the frozen identity plus the current dynamic content. The
/// app maps authoritative state into this pure value; a future ActivityKit adapter turns it into
/// `Activity.request`/`update`/`end` calls. Fully constructible and comparable without any
/// ActivityKit runtime, so all lifecycle logic is deterministically testable today.
public nonisolated struct LiveActivitySnapshot: Sendable, Hashable {
    public var identity: LiveActivityIdentity
    public var content: TimeFrameLiveActivityContent

    public init(identity: LiveActivityIdentity, content: TimeFrameLiveActivityContent) {
        self.identity = identity
        self.content = content
    }

    /// The stable identity key, surfaced for convenience.
    public var sessionID: UUID { identity.sessionID }
}
