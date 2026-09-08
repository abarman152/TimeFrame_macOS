//
//  CalendarEventDraft.swift
//  time_frame
//
//  The core, framework-independent representation of a calendar event Time Frame
//  wants to create or update. It is deliberately free of EventKit: the adapter is
//  the only place a draft becomes an `EKEvent` (ADR-033). Because the fields are
//  `var`, the preview UI can let the user customise title/notes before creation.
//

import Foundation

/// A pure value describing one calendar event to create or update.
///
/// Contains **no** `EKEvent`, `EKCalendar`, or `EKEventStore`. The generator builds
/// drafts from plan/session data; the `EventKitCalendarService` is the sole
/// translator into and out of EventKit.
nonisolated struct CalendarEventDraft: Equatable, Sendable {
    var title: String
    var startDate: Date
    var endDate: Date
    var notes: String?
    var location: String?
    /// The calendar to create the event in. `nil` means "the default writable
    /// calendar", resolved by the adapter at save time.
    var calendarIdentifier: String?

    init(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String? = nil,
        location: String? = nil,
        calendarIdentifier: String? = nil
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.location = location
        self.calendarIdentifier = calendarIdentifier
    }

    /// The event's duration in seconds (never negative for a well-formed draft).
    var duration: TimeInterval { max(0, endDate.timeIntervalSince(startDate)) }
}
