//
//  CalendarDescriptor.swift
//  time_frame
//
//  The UI-facing description of a writable calendar. Exposes only what a picker
//  needs; `EKCalendar` never leaks into SwiftUI (ADR-032).
//

import Foundation

/// A lightweight, `Sendable` description of a calendar the user could write to.
///
/// The `id` is the EventKit `calendarIdentifier` — the value Time Frame persists as
/// the default calendar, because two calendars can share a title (§20 of the
/// milestone). `colorHex` is an optional presentation hint (a `#RRGGBB` string),
/// kept as a plain string so no AppKit/color type crosses this boundary.
nonisolated struct CalendarDescriptor: Identifiable, Equatable, Sendable, Hashable {
    /// The stable EventKit calendar identifier.
    let id: String
    /// The calendar's display title.
    let title: String
    /// Optional `#RRGGBB` colour hint for the UI, or nil if unavailable.
    let colorHex: String?
    /// Whether new events may be created in this calendar.
    let allowsEventCreation: Bool
}
