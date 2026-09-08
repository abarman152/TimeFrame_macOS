//
//  WidgetProjection.swift
//  Time Frame — shared widget projection (Milestone 11)
//
//  The single, read-only value the app writes and the widget reads. It is a *projection*
//  of the one authoritative `TimerEngine`/`SessionCoordinator` state — never a second
//  source of truth (ADR-055). The widget renders from this snapshot and from
//  WidgetKit-supported date-relative text; it owns no timer, decrements no counter, and
//  reconstructs no Pomodoro sequencing.
//
//  Timestamps (`intervalStartedAt`/`intervalPlannedEndAt`) are frozen at write time so the
//  widget can render a live countdown with `Text(_:style:.timer)` *without* running a
//  clock of its own. `pausedRemainingSeconds` carries the frozen remaining while paused so
//  the widget never pretends a paused interval is advancing.
//
//  Compiled into BOTH the app target and the widget extension. Foundation-only:
//  `Sendable`, `Equatable`, `Codable`. It imports no SwiftData, WidgetKit, or TimerEngine.
//

import Foundation

/// An immutable snapshot of what the Time Frame widgets should show right now.
public struct WidgetProjection: Codable, Sendable, Equatable {

    /// The projection schema version. Bumped only on a breaking shape change; the reader
    /// treats an unrecognised (newer/older) version as untrustworthy and falls back.
    public static let currentSchemaVersion = 1

    /// The `UserDefaults`/App-Group key the app writes and the widget reads.
    public static let storageKey = "com.time-frame.widget.projection.v1"

    // MARK: Envelope

    /// The schema version this payload was written with.
    public var schemaVersion: Int
    /// When the app built this projection (the app's clock, frozen).
    public var generatedAt: Date

    // MARK: Session state

    /// The coarse situation the widget switches on.
    public var state: WidgetSessionState
    /// The current interval's phase (`.none` when nothing is counting down).
    public var phase: WidgetPhase
    /// The described session's task label, if any (may be empty).
    public var title: String?
    /// The described session's frozen configuration name, if any.
    public var configurationName: String?

    // MARK: Interval progress

    /// The 1-based focus-session number in progress, or `nil` when not active.
    public var currentIntervalIndex: Int?
    /// The total number of focus sessions in the plan, or `nil` when not active/finished.
    public var totalIntervals: Int?
    /// How many focus sessions have fully completed (for progress dots).
    public var completedFocusCount: Int
    /// The current interval's start instant (frozen). Anchors a live `.timer` countdown.
    public var intervalStartedAt: Date?
    /// The current interval's planned end instant (frozen). The countdown target and the
    /// timeline's meaningful boundary.
    public var intervalPlannedEndAt: Date?
    /// The frozen remaining seconds while paused (never negative). `nil` unless paused.
    public var pausedRemainingSeconds: TimeInterval?

    // MARK: Today summary

    /// Focus seconds completed today, if the app computed it. `nil` when unavailable.
    public var focusSecondsToday: TimeInterval?
    /// Sessions completed today, if the app computed it. `nil` when unavailable.
    public var completedSessionsToday: Int?
    /// Focus intervals completed today, if the app computed it. `nil` when unavailable.
    /// Additive in Milestone 14 for the Today/Statistics widget modes; an older payload
    /// that omits it simply reads `nil` (schema version is unchanged — additive optional).
    public var completedFocusIntervalsToday: Int?
    /// Today's focus direction versus the equivalent prior day, if the app computed it.
    /// Additive in Milestone 14 for the Statistics widget mode; `nil` when unavailable.
    public var focusTrendToday: WidgetFocusTrend?

    // MARK: Diagnostics

    /// A short reason the projection is `.unavailable`, for diagnostics/accessibility.
    public var failureReason: String?

    public init(
        schemaVersion: Int = WidgetProjection.currentSchemaVersion,
        generatedAt: Date,
        state: WidgetSessionState,
        phase: WidgetPhase,
        title: String? = nil,
        configurationName: String? = nil,
        currentIntervalIndex: Int? = nil,
        totalIntervals: Int? = nil,
        completedFocusCount: Int = 0,
        intervalStartedAt: Date? = nil,
        intervalPlannedEndAt: Date? = nil,
        pausedRemainingSeconds: TimeInterval? = nil,
        focusSecondsToday: TimeInterval? = nil,
        completedSessionsToday: Int? = nil,
        completedFocusIntervalsToday: Int? = nil,
        focusTrendToday: WidgetFocusTrend? = nil,
        failureReason: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.state = state
        self.phase = phase
        self.title = title
        self.configurationName = configurationName
        self.currentIntervalIndex = currentIntervalIndex
        self.totalIntervals = totalIntervals
        self.completedFocusCount = completedFocusCount
        self.intervalStartedAt = intervalStartedAt
        self.intervalPlannedEndAt = intervalPlannedEndAt
        self.pausedRemainingSeconds = pausedRemainingSeconds
        self.focusSecondsToday = focusSecondsToday
        self.completedSessionsToday = completedSessionsToday
        self.completedFocusIntervalsToday = completedFocusIntervalsToday
        self.focusTrendToday = focusTrendToday
        self.failureReason = failureReason
    }

    // MARK: Convenience constructors

    /// The calm idle projection ("Ready to focus"), optionally carrying a today summary.
    public static func idle(
        at date: Date,
        focusSecondsToday: TimeInterval? = nil,
        completedSessionsToday: Int? = nil,
        completedFocusIntervalsToday: Int? = nil,
        focusTrendToday: WidgetFocusTrend? = nil
    ) -> WidgetProjection {
        WidgetProjection(
            generatedAt: date,
            state: .idle,
            phase: .none,
            completedFocusCount: 0,
            focusSecondsToday: focusSecondsToday,
            completedSessionsToday: completedSessionsToday,
            completedFocusIntervalsToday: completedFocusIntervalsToday,
            focusTrendToday: focusTrendToday
        )
    }

    /// A stable fallback used when no trustworthy projection could be read. Never crashes
    /// the widget; the views render a neutral "Time Frame" placeholder from it.
    public static func unavailable(reason: String, at date: Date = Date()) -> WidgetProjection {
        WidgetProjection(
            generatedAt: date,
            state: .unavailable,
            phase: .none,
            completedFocusCount: 0,
            failureReason: reason
        )
    }

    /// Whether this payload's schema version is one this build understands.
    public var isSchemaCompatible: Bool {
        schemaVersion == WidgetProjection.currentSchemaVersion
    }
}
