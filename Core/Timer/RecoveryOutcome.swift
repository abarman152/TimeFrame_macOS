//
//  RecoveryOutcome.swift
//  time_frame
//
//  The result of the app's relaunch recovery attempt, surfaced to the UI.
//

import Foundation

/// What happened when the coordinator tried to restore a session on launch.
///
/// Kept deliberately small and value-typed so the Timer screen can react to it
/// (show a restored session, or a calm "couldn't restore" notice) without
/// reaching into persistence. See `SessionCoordinator.recover()` and ADR-012.
nonisolated enum RecoveryOutcome: Equatable, Sendable, Hashable {
    /// No recoverable session existed, or recovery has been acknowledged.
    case none

    /// A live session was restored (running or paused) and is now active.
    case restored

    /// A session was found but was too inconsistent to resume; it was marked
    /// `interrupted` and not restored.
    case interrupted
}
