//
//  CalendarAuthorizationStatus.swift
//  time_frame
//
//  A framework-independent mirror of EventKit's authorization states, so the app
//  (UI, coordinator, tests) reasons about Calendar permission without importing
//  EventKit anywhere but the single adapter. See docs/15-CALENDAR-INTEGRATION.md.
//

import Foundation

/// The app's own view of Calendar authorization, decoupled from `EKAuthorizationStatus`.
///
/// EventKit (macOS 14+/macOS 27) distinguishes *full* access (read + write) from
/// *write-only* access. Time Frame needs full access because updating and deleting
/// an event requires reading it back by identifier, so `.writeOnly` is treated as
/// "authorized but insufficient" and surfaced to the user like a limited grant.
nonisolated enum CalendarAuthorizationStatus: String, Sendable, Equatable {
    /// The user has not yet been asked.
    case notDetermined
    /// Access is disallowed by policy (e.g. parental controls / MDM). The user
    /// cannot grant it themselves.
    case restricted
    /// The user explicitly declined.
    case denied
    /// Write-only access was granted — Time Frame can create events but cannot read
    /// them back, so update/delete are unavailable. Treated as insufficient.
    case writeOnly
    /// Full read/write access — the state Time Frame needs.
    case fullAccess

    /// Whether Time Frame can create *and* manage (update/delete) events.
    var isSufficient: Bool { self == .fullAccess }

    /// Whether it is worth prompting the user (only when they have not chosen yet).
    var canRequest: Bool { self == .notDetermined }

    /// Whether the only remedy is System Settings (an explicit denial or a
    /// write-only grant the user must widen).
    var requiresSystemSettings: Bool { self == .denied || self == .writeOnly }
}
