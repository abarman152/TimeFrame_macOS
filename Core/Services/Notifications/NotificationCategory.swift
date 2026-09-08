//
//  NotificationCategory.swift
//  time_frame
//
//  The semantic kinds of notification Time Frame delivers. Framework-independent
//  (no UserNotifications import): the pure domain reasons about *what* a notification
//  means, and the single `UserNotificationService` adapter maps it to a
//  `UNNotificationCategory` identifier. See docs/16-NOTIFICATIONS.md.
//

import Foundation

/// A meaningful session transition worth notifying the user about.
///
/// Deliberately decoupled from `UserNotifications` (§11): the coordinator, content
/// generator, scheduler, and tests all speak in these cases, and only the adapter
/// knows the corresponding `UNNotificationCategory`.
nonisolated enum NotificationCategory: String, Codable, Sendable, CaseIterable, Hashable {
    /// A focus interval is beginning.
    case focusStarted
    /// A short break is beginning.
    case shortBreakStarted
    /// A long break is beginning.
    case longBreakStarted
    /// Every planned interval finished normally.
    case sessionCompleted

    /// The stable identifier the adapter registers this category under with
    /// `UNUserNotificationCenter`. Namespaced so it never collides with other apps.
    var identifier: String { "com.timeframe.category.\(rawValue)" }

    /// Whether the timer will be *running* when a notification of this category
    /// fires. Running-phase categories carry active controls (Pause/Skip); the
    /// completion category is informational only.
    var isRunningPhase: Bool {
        switch self {
        case .focusStarted, .shortBreakStarted, .longBreakStarted: return true
        case .sessionCompleted: return false
        }
    }

    /// The transition-type suffix used to build a stable notification identifier
    /// (§34). Never derived from the title.
    var identifierSuffix: String {
        switch self {
        case .focusStarted, .shortBreakStarted, .longBreakStarted: return "transition"
        case .sessionCompleted: return "completion"
        }
    }
}
