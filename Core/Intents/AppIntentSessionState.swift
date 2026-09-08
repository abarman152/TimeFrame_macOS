//
//  AppIntentSessionState.swift
//  time_frame (Milestone 12)
//
//  A pure, value-typed projection of the authoritative session state for the App Intents
//  layer (ADR-058). It carries everything an intent needs to answer a query or phrase a
//  spoken result — task, configuration, phase, remaining time, focus progress and the next
//  interval — WITHOUT an intent ever reaching back into the engine or owning any state.
//
//  This mirrors the menu bar's `MenuBarPresentationState` (§48) and the widget's
//  `WidgetProjectionMapper` (ADR-055): same one source of truth, same in-memory timestamp
//  math, no persistence access. It exists so App Intents can never become a second timer —
//  they read a frozen snapshot and phrase it; the countdown truth stays in `TimerEngine`.
//

import Foundation

/// A read-only snapshot of what Time Frame is doing right now, for the App Intents layer.
///
/// Pure (`Sendable`, `Equatable`, Foundation-only) so it is trivially testable and can
/// never hold a reference that mutates the timer. Built from authoritative state by
/// `init(coordinator:)`; the memberwise initializer is used by unit tests.
nonisolated struct AppIntentSessionState: Sendable, Equatable {

    /// The coarse situation an intent switches on when phrasing a result.
    enum Situation: String, Sendable, Equatable {
        /// No active or recently-finished session — nothing is counting down.
        case idle
        /// A session is running (focus or break).
        case running
        /// A session is active but frozen.
        case paused
        /// Every interval finished normally.
        case completed
        /// Relaunch recovery found a session it could not safely resume.
        case interrupted
    }

    /// The coarse situation.
    let situation: Situation
    /// The authoritative engine state.
    let state: TimerState
    /// The current interval's phase, if there is one.
    let phase: TimerPhase?
    /// The task name of the described session, if any (may be empty).
    let taskName: String?
    /// The frozen configuration name of the described session (the session's own
    /// snapshot, never the live configuration — matches the menu bar / widget).
    let configurationName: String?
    /// Seconds remaining in the current interval at the instant this projection was built
    /// (frozen while paused; derived from the timeline while running). Never negative.
    let remaining: TimeInterval
    /// The 1-based focus-session number in progress, or `nil` when not active.
    let sessionIndex: Int?
    /// The total number of focus sessions in the plan, or `nil` when not active/finished.
    let totalSessions: Int?
    /// The phase of the next interval, if the plan has one after the current index.
    let nextPhase: TimerPhase?

    /// Whether a session is live (running or paused).
    var isActive: Bool { state.isActive }

    /// Whether there is a session an intent can query/describe at all.
    var hasSession: Bool { situation != .idle }
}

@MainActor
extension AppIntentSessionState {
    /// Builds the projection from the one authoritative coordinator/engine.
    ///
    /// Reads only in-memory engine and model state — no persistence access — so it is
    /// cheap and side-effect free. Mirrors `MenuBarPresentationState.init(coordinator:)`
    /// and `WidgetProjectionMapper` exactly, so all three surfaces describe the same truth.
    init(coordinator: SessionCoordinator) {
        let engine = coordinator.engine
        let state = engine.state
        let recovery = coordinator.recoveryOutcome

        let situation: Situation
        switch state {
        case .running: situation = .running
        case .paused: situation = .paused
        case .completed: situation = .completed
        case .idle, .cancelled:
            situation = (recovery == .interrupted) ? .interrupted : .idle
        }

        // Which persisted session this projection describes (mirrors the menu bar / widget).
        let described: FocusSession?
        switch situation {
        case .running, .paused, .completed: described = coordinator.activeSession
        case .interrupted: described = coordinator.interruptedSession
        case .idle: described = nil
        }

        let active = state.isActive
        let next = engine.plan.interval(at: engine.currentIndex + 1)

        self.init(
            situation: situation,
            state: state,
            phase: active ? engine.currentPhase : nil,
            taskName: described?.taskName,
            configurationName: described?.displayConfigurationName,
            remaining: active ? max(0, engine.remaining) : 0,
            sessionIndex: active ? engine.currentFocusNumber : nil,
            totalSessions: (active || situation == .completed) ? engine.totalFocusSessions : nil,
            nextPhase: active ? next?.phase : nil
        )
    }
}
