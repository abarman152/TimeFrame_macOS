//
//  AppLog.swift
//  time_frame
//
//  Central os.Logger definitions for the app's subsystems.
//

import Foundation
import os

/// Unified-logging channels for Time Frame.
///
/// Uses Apple's `os.Logger` so diagnostics are structured, low-overhead, and
/// visible in Console/Instruments. Log **identifiers and counts, never user
/// content** (e.g. task names): a task name is potentially sensitive and must
/// not be written to the log.
/// `nonisolated` so the persistence layer's pure, non-main-actor types can log too
/// (Milestone 31). `Logger` is `Sendable`; existing main-actor callers are unaffected.
nonisolated enum AppLog {
    /// The app's logging subsystem (reverse-DNS).
    static let subsystem = "com.timeframe.app"

    /// Persistence / SwiftData store lifecycle.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")

    /// Session lifecycle and recovery.
    static let session = Logger(subsystem: subsystem, category: "session")

    /// Calendar / EventKit integration (authorization, event create/update/delete,
    /// EventKit failures). Logs identifiers, counts, and statuses only — never
    /// calendar event notes or task names (§41).
    static let calendar = Logger(subsystem: subsystem, category: "calendar")

    /// Notifications / UserNotifications integration (authorization, scheduling,
    /// cancellation, received actions, failures). Logs categories, counts, and
    /// statuses only — never notification titles or bodies or task names (§51).
    static let notifications = Logger(subsystem: subsystem, category: "notifications")

    /// Live Activity / ActivityKit integration on iOS/iPadOS (request/update/end,
    /// authorization, failures). Logs identifiers, counts, and statuses only —
    /// never task names or session content (Milestone 18).
    static let liveActivity = Logger(subsystem: subsystem, category: "liveActivity")

    /// Window management and the "Open at Login" registration (Milestone 32). Logs statuses
    /// and decisions only — never window titles, task names, or session content.
    static let appLifecycle = Logger(subsystem: subsystem, category: "appLifecycle")
}
