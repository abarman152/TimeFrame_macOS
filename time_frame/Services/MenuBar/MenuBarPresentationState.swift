//
//  MenuBarPresentationState.swift
//  time_frame
//
//  A pure, value-typed projection of the authoritative session state for the menu bar
//  (§48). It carries everything the status item and its popover need to render — task,
//  configuration, phase, remaining time, focus progress and the next interval — WITHOUT
//  the menu bar ever reaching back into the engine or owning any state of its own.
//
//  This is the single most important guarantee of Milestone 8: the menu bar can never
//  become a second timer, because it holds no timer state. Every field here is computed
//  from the one authoritative `TimerEngine` (via `SessionCoordinator`) each time the
//  projection is built; rebuilding it is cheap in-memory timestamp math (no SwiftData
//  query, ADR-046/§89). The countdown "ticks" only because a `TimelineView` rebuilds
//  this projection ~once a second while running — the truth still lives in the engine.
//

import Foundation

/// A snapshot of what the menu bar should show right now.
///
/// Pure (`Sendable`, `Equatable`) so it is trivially testable and can never hold a
/// reference that mutates the timer. Built from authoritative state by
/// `init(coordinator:)`; the memberwise initializer is used by unit tests.
nonisolated struct MenuBarPresentationState: Sendable, Equatable {

    /// The coarse situation the popover switches on. Finer detail (focus vs break)
    /// lives in `phase`; this drives the top-level layout and the status icon.
    enum Situation: String, Sendable, Equatable {
        /// No active or recently-finished session — the idle "Ready to focus" state.
        case empty
        /// A session is running (focus or break).
        case running
        /// A session is active but frozen.
        case paused
        /// Every interval finished normally; nothing is counting down.
        case completed
        /// Relaunch recovery found a session it could not safely resume.
        case interrupted
    }

    /// The coarse situation.
    let situation: Situation
    /// Whether a session is live (running or paused). `false` for empty/completed/interrupted.
    let hasActiveSession: Bool
    /// The task name of the described session, if any (may be empty).
    let taskName: String?
    /// The frozen configuration name of the described session (ADR-053-style independence:
    /// this is the session's own snapshot, never the live configuration — §53).
    let configurationName: String?
    /// The current interval's phase, if there is one.
    let phase: TimerPhase?
    /// The authoritative engine state.
    let state: TimerState
    /// Seconds remaining in the current interval at the instant this projection was built
    /// (frozen while paused; derived from the timeline while running). Never negative.
    let remaining: TimeInterval
    /// The 1-based focus-session number in progress, or `nil` when not active.
    let currentFocusNumber: Int?
    /// The total number of focus sessions in the plan, or `nil` when not active/finished.
    let totalFocusSessions: Int?
    /// How many focus sessions have fully completed (for the progress dots).
    let completedFocusCount: Int
    /// The phase of the next interval, if the plan has one after the current index.
    let nextPhase: TimerPhase?
    /// The planned duration of the next interval, if any.
    let nextDuration: TimeInterval?
    /// The most recent relaunch-recovery outcome (so the popover can show a restored /
    /// interrupted notice consistent with the main window).
    let recovery: RecoveryOutcome

    /// Whether the current interval is a focus interval (used by the progress dots).
    var currentPhaseIsFocus: Bool { phase?.isFocus == true }
}

@MainActor
extension MenuBarPresentationState {
    /// Builds the projection from the one authoritative coordinator/engine.
    ///
    /// Reads only in-memory engine and model state — no persistence access — so it is
    /// safe to call on every `TimelineView` redraw (§87/§89). SwiftUI's Observation
    /// records the engine property reads made here, so any view that consumes the
    /// projection re-renders the moment the engine changes (§33).
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
            situation = (recovery == .interrupted) ? .interrupted : .empty
        }

        // Which persisted session this projection describes.
        let described: FocusSession?
        switch situation {
        case .running, .paused, .completed: described = coordinator.activeSession
        case .interrupted: described = coordinator.interruptedSession
        case .empty: described = nil
        }

        let active = state.isActive
        let completedFocus = engine.completedIntervals
            .filter { $0.phase == .focus && $0.outcome == .completed }
            .count
        let next = engine.plan.interval(at: engine.currentIndex + 1)

        self.init(
            situation: situation,
            hasActiveSession: active,
            taskName: described?.taskName,
            configurationName: described?.displayConfigurationName,
            phase: active ? engine.currentPhase : nil,
            state: state,
            remaining: active ? max(0, engine.remaining) : 0,
            currentFocusNumber: active ? engine.currentFocusNumber : nil,
            totalFocusSessions: (active || situation == .completed) ? engine.totalFocusSessions : nil,
            completedFocusCount: completedFocus,
            nextPhase: active ? next?.phase : nil,
            nextDuration: active ? next?.duration : nil,
            recovery: recovery
        )
    }
}
