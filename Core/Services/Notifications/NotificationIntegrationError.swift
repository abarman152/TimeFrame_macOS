//
//  NotificationIntegrationError.swift
//  time_frame
//
//  Structured, user-safe failures for the notification integration. Raw
//  UserNotifications / Cocoa errors are mapped to these inside the adapter before
//  they ever reach the coordinator or UI, so the app never surfaces a technical
//  `UNError` — and, crucially, none of these ever propagate into the timer (§50).
//

import Foundation

/// The failures the notification integration can report.
///
/// The `NotificationCoordinator` catches every one, logs it, and updates a
/// non-blocking status; the running session is never affected (ADR-042).
nonisolated enum NotificationIntegrationError: Error, Equatable, Sendable, LocalizedError {
    /// No notification permission (denied or not yet granted).
    case notAuthorized
    /// Scheduling a notification request failed.
    case schedulingFailed
    /// Cancelling pending notifications failed.
    case cancellationFailed
    /// The notification settings could not be read.
    case settingsUnavailable
    /// A descriptor could not be turned into a valid request.
    case invalidRequest
    /// Handling a received notification action failed.
    case actionHandlingFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Time Frame doesn't have permission to send notifications."
        case .schedulingFailed:
            return "Couldn't schedule a notification."
        case .cancellationFailed:
            return "Couldn't update Time Frame's notifications."
        case .settingsUnavailable:
            return "Notification settings are temporarily unavailable."
        case .invalidRequest:
            return "That notification couldn't be prepared."
        case .actionHandlingFailed:
            return "Couldn't complete that notification action."
        }
    }

    /// A short status label for a compact indicator (never technical).
    var shortStatus: String {
        switch self {
        case .notAuthorized: return "Permission needed"
        case .settingsUnavailable: return "Notifications unavailable"
        default: return "Notification failed"
        }
    }
}
