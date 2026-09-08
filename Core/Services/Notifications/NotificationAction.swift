//
//  NotificationAction.swift
//  time_frame
//
//  The controls a delivered notification can offer, plus the pure value describing a
//  received response. Framework-independent: the adapter maps these to
//  `UNNotificationAction`s and parses a `UNNotificationResponse` into a
//  `ReceivedNotificationAction`. Every timer-affecting action is routed back through
//  `SessionCoordinator` — never applied to the engine directly (§37).
//

import Foundation

/// A control a notification can carry, or the response of tapping the notification
/// body itself (`open`).
nonisolated enum NotificationAction: String, Codable, Sendable, CaseIterable, Hashable {
    case pause
    case resume
    case skip
    case stop
    /// The default action — the user tapped the notification (no button).
    case open

    /// The stable identifier the adapter registers/parses this action under.
    var identifier: String { "com.timeframe.action.\(rawValue)" }

    /// A short button title.
    var title: String {
        switch self {
        case .pause: return "Pause"
        case .resume: return "Resume"
        case .skip: return "Skip"
        case .stop: return "Stop"
        case .open: return "Open Time Frame"
        }
    }

    /// Whether triggering this action should destroy nothing but does end the run
    /// (used by the adapter to mark the action destructive in the UI).
    var isDestructive: Bool { self == .stop }
}

/// A pure description of a notification response, produced by the adapter and
/// consumed by the coordinator. Carries no UserNotifications type.
nonisolated struct ReceivedNotificationAction: Sendable, Equatable {
    let action: NotificationAction
    /// The session the notification belonged to, if it carried one.
    let sessionID: UUID?
}
