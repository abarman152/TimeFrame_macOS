//
//  NotificationActionResolver.swift
//  time_frame
//
//  The pure decision layer for a received notification action. Given the action, the
//  session it targeted, and the *current* authoritative timer state, it decides what
//  should happen — without importing UserNotifications and without touching the engine.
//  This keeps the safety rules of §40 fully unit-testable: an action for a session that
//  no longer exists, or a completed session, is ignored gracefully rather than crashing.
//

import Foundation

/// What the coordinator should do with a received notification action.
nonisolated enum ResolvedNotificationAction: Equatable, Sendable {
    /// Route this timer control through `SessionCoordinator`.
    case perform(NotificationAction)
    /// Bring the app forward (the `open` action / default tap).
    case activateApp
    /// Do nothing but log why (§40).
    case ignore(reason: String)
}

/// Decides the outcome of a received action against the current session state.
nonisolated enum NotificationActionResolver {

    /// - Parameters:
    ///   - received: the parsed response (action + optional session id).
    ///   - activeSessionID: the id of the session the coordinator currently drives, or
    ///     nil if none is active.
    ///   - state: the engine's current state.
    static func resolve(
        _ received: ReceivedNotificationAction,
        activeSessionID: UUID?,
        state: TimerState
    ) -> ResolvedNotificationAction {
        // Opening the app is always safe and independent of session state.
        if received.action == .open { return .activateApp }

        // A timer control needs a matching, still-active session.
        guard let activeSessionID else {
            return .ignore(reason: "no active session")
        }
        if let target = received.sessionID, target != activeSessionID {
            return .ignore(reason: "action for a different session")
        }
        guard state.isActive else {
            return .ignore(reason: "session is not active")
        }

        switch received.action {
        case .pause:
            return state == .running ? .perform(.pause) : .ignore(reason: "not running")
        case .resume:
            return state == .paused ? .perform(.resume) : .ignore(reason: "not paused")
        case .skip:
            return .perform(.skip)
        case .stop:
            return .perform(.stop)
        case .open:
            return .activateApp // unreachable (handled above)
        }
    }
}
