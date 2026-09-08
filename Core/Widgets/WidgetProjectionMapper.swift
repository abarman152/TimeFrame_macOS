//
//  WidgetProjectionMapper.swift
//  time_frame (Milestone 11)
//
//  The single place that turns the authoritative `SessionCoordinator`/`TimerEngine` state
//  into a read-only `WidgetProjection`. It mirrors the menu bar's `MenuBarPresentationState`
//  mapping (§48) — same source of truth, same in-memory timestamp math, no persistence
//  access — but emits a `Codable` value the widget process can read instead of a live
//  SwiftUI projection (ADR-055).
//
//  This mapper lives in the APP target (it reads domain types the widget never sees). It
//  writes nothing and mutates nothing: given the engine's frozen anchors it produces an
//  immutable snapshot. The widget never runs this code — it only reads the result.
//

import Foundation

/// Builds a `WidgetProjection` from authoritative app state. Pure w.r.t. the store: it
/// reads the engine/coordinator and returns a value; the writer decides when to persist.
@MainActor
enum WidgetProjectionMapper {

    /// Maps the coordinator's current authoritative state into a projection.
    ///
    /// - Parameters:
    ///   - coordinator: the one shared coordinator (read-only here).
    ///   - now: the app clock instant to stamp the projection with.
    ///   - today: an optional pre-computed today summary (focus seconds, completed
    ///     sessions). Passed in so the mapper stays free of any statistics fetch.
    static func projection(
        from coordinator: SessionCoordinator,
        now: Date,
        today: TodaySummary? = nil
    ) -> WidgetProjection {
        let engine = coordinator.engine
        let state = engine.state
        let recovery = coordinator.recoveryOutcome

        // Resolve the coarse widget state from the engine state (+ recovery outcome).
        let widgetState: WidgetSessionState
        switch state {
        case .running: widgetState = .running
        case .paused: widgetState = .paused
        case .completed: widgetState = .completed
        case .idle, .cancelled:
            widgetState = (recovery == .interrupted) ? .interrupted : .idle
        }

        // Which persisted session this projection describes (mirrors the menu bar).
        let described: FocusSession?
        switch widgetState {
        case .running, .paused, .completed: described = coordinator.activeSession
        case .interrupted: described = coordinator.interruptedSession
        case .idle, .unavailable: described = nil
        }

        let active = state.isActive
        let completedFocus = engine.completedIntervals
            .filter { $0.phase == .focus && $0.outcome == .completed }
            .count

        return WidgetProjection(
            generatedAt: now,
            state: widgetState,
            phase: active ? widgetPhase(engine.currentPhase) : .none,
            title: described?.taskName,
            configurationName: described?.displayConfigurationName,
            currentIntervalIndex: active ? engine.currentFocusNumber : nil,
            totalIntervals: (active || widgetState == .completed) ? engine.totalFocusSessions : nil,
            completedFocusCount: completedFocus,
            intervalStartedAt: (state == .running) ? engine.currentIntervalStart : nil,
            intervalPlannedEndAt: (state == .running) ? engine.currentIntervalEnd : nil,
            pausedRemainingSeconds: (state == .paused) ? max(0, engine.remaining) : nil,
            focusSecondsToday: today?.focusSeconds,
            completedSessionsToday: today?.completedSessions,
            completedFocusIntervalsToday: today?.completedFocusIntervals,
            focusTrendToday: today?.focusTrend
        )
    }

    /// Bridges the domain `TimerPhase` to the neutral `WidgetPhase`.
    private static func widgetPhase(_ phase: TimerPhase?) -> WidgetPhase {
        switch phase {
        case .focus: return .focus
        case .shortBreak: return .shortBreak
        case .longBreak: return .longBreak
        case nil: return .none
        }
    }
}

/// A tiny value carrying the "today" numbers the widget shows (focus time, completed
/// sessions, completed focus intervals, and a focus trend versus the prior day). Computed by
/// the app from the SAME `StatisticsAggregator` the dashboard uses and handed to the mapper,
/// so the mapper performs no fetch of its own and the widget never aggregates anything
/// (Milestone 14). The trend is a pure `WidgetFocusTrend` — the widget only renders it.
struct TodaySummary: Sendable, Equatable {
    let focusSeconds: TimeInterval
    let completedSessions: Int
    let completedFocusIntervals: Int
    let focusTrend: WidgetFocusTrend

    init(
        focusSeconds: TimeInterval,
        completedSessions: Int,
        completedFocusIntervals: Int = 0,
        focusTrend: WidgetFocusTrend = .steady
    ) {
        self.focusSeconds = focusSeconds
        self.completedSessions = completedSessions
        self.completedFocusIntervals = completedFocusIntervals
        self.focusTrend = focusTrend
    }
}
