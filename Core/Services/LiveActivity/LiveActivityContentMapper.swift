//
//  LiveActivityContentMapper.swift
//  time_frame (Milestone 16)
//
//  The single place that turns the authoritative `SessionCoordinator`/`TimerEngine` state into a
//  read-only `LiveActivitySnapshot`. It mirrors `WidgetProjectionMapper` exactly — same source of
//  truth, same in-memory timestamp math, no persistence access, no clock of its own — but emits
//  the Live Activity's pure content instead of the widget projection (ADR-072).
//
//  It reads domain types (so it lives in the app target) and writes/ mutates nothing. Given the
//  engine's frozen anchors it produces an immutable value; the coordinator decides what to do
//  with it. Foundation-only: no ActivityKit, so it is fully unit-testable without a runtime.
//

import Foundation

/// Builds a `LiveActivitySnapshot` from authoritative app state, or `nil` when there is no
/// session worth surfacing on a Live Activity (idle with no described session).
@MainActor
enum LiveActivityContentMapper {

    /// Maps the coordinator's current authoritative state into a Live Activity snapshot.
    ///
    /// - Returns: a snapshot for a running / paused / just-completed / interrupted session, or
    ///   `nil` when idle (nothing to show — the coordinator ends any activity instead).
    static func snapshot(from coordinator: SessionCoordinator, now: Date) -> LiveActivitySnapshot? {
        let engine = coordinator.engine
        let state = engine.state
        let recovery = coordinator.recoveryOutcome

        // Resolve the coarse run-state and which persisted session this describes.
        let runState: LiveActivityRunState
        let described: FocusSession?
        switch state {
        case .running:
            runState = .running; described = coordinator.activeSession
        case .paused:
            runState = .paused; described = coordinator.activeSession
        case .completed:
            runState = .completed; described = coordinator.activeSession
        case .idle, .cancelled:
            if recovery == .interrupted, let interrupted = coordinator.interruptedSession {
                runState = .interrupted; described = interrupted
            } else {
                return nil // idle: no live session to surface
            }
        }

        guard let session = described else { return nil }

        let active = state.isActive
        let completedFocus = engine.completedIntervals
            .filter { $0.phase == .focus && $0.outcome == .completed }
            .count

        // Next phase (and its projected end) derived purely from the engine's plan — never a
        // second clock. Known only while an interval is actually counting down.
        let nextPlanned = engine.plan.interval(at: engine.currentIndex + 1)
        let phaseTargetEnd: Date? = (state == .running) ? engine.currentIntervalEnd : nil
        let nextPhaseEnd: Date?
        if state == .running, let end = phaseTargetEnd, let next = nextPlanned {
            nextPhaseEnd = end.addingTimeInterval(next.duration)
        } else {
            nextPhaseEnd = nil
        }

        let content = TimeFrameLiveActivityContent(
            runState: runState,
            phase: active ? widgetPhase(engine.currentPhase) : .none,
            phaseStartedAt: (state == .running) ? engine.currentIntervalStart : nil,
            phaseTargetEndAt: phaseTargetEnd,
            pausedRemainingSeconds: (state == .paused) ? max(0, engine.remaining) : nil,
            sessionIndex: active ? engine.currentFocusNumber : 0,
            totalFocusSessions: engine.totalFocusSessions,
            completedFocusCount: completedFocus,
            nextPhase: active ? widgetPhase(nextPlanned?.phase) : .none,
            nextPhaseTargetEndAt: nextPhaseEnd
        )

        let identity = LiveActivityIdentity(
            sessionID: session.id,
            taskName: session.taskName,
            configurationName: session.displayConfigurationName,
            sessionStartedAt: session.startedAt ?? now
        )

        return LiveActivitySnapshot(identity: identity, content: content)
    }

    /// Bridges the domain `TimerPhase` to the neutral shared `WidgetPhase`.
    private static func widgetPhase(_ phase: TimerPhase?) -> WidgetPhase {
        switch phase {
        case .focus: return .focus
        case .shortBreak: return .shortBreak
        case .longBreak: return .longBreak
        case nil: return .none
        }
    }
}
