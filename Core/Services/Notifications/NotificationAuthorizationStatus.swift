//
//  NotificationAuthorizationStatus.swift
//  time_frame
//
//  A framework-independent mirror of UserNotifications' authorization states, so the
//  app (UI, coordinator, tests) reasons about notification permission without
//  importing UserNotifications anywhere but the single adapter. See
//  docs/16-NOTIFICATIONS.md.
//

import Foundation

/// The app's own view of notification authorization, decoupled from
/// `UNAuthorizationStatus`.
///
/// macOS 27 exposes `notDetermined`, `denied`, `authorized`, and `provisional`
/// (quiet delivery). `ephemeral` is an App Clip concept that does not apply to a Mac
/// app, so it is intentionally not modelled (§19 — do not invent unsupported states).
nonisolated enum NotificationAuthorizationStatus: String, Sendable, Equatable {
    /// The user has not been asked yet.
    case notDetermined
    /// The user explicitly declined, or notifications are otherwise unavailable.
    case denied
    /// Full permission to deliver alerting notifications.
    case authorized
    /// Provisional (quiet) delivery was granted — notifications post silently to the
    /// list. Treated as sufficient to schedule (they still deliver).
    case provisional

    /// Whether Time Frame may schedule notifications at all.
    var isAuthorized: Bool { self == .authorized || self == .provisional }

    /// Whether it is worth prompting the user (only when undecided).
    var canRequest: Bool { self == .notDetermined }

    /// Whether the only remedy is System Settings (an explicit denial).
    var requiresSystemSettings: Bool { self == .denied }
}
