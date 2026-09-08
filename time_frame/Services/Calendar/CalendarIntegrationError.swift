//
//  CalendarIntegrationError.swift
//  time_frame
//
//  Structured, user-safe failures for the Calendar integration. Raw EventKit /
//  Cocoa errors are mapped to these before they ever reach the UI, so the app
//  never shows a technical `EKError` and never leaks calendar internals.
//

import Foundation

/// The failures the Calendar integration can report.
///
/// Every case carries a friendly, non-technical `errorDescription`. Crucially,
/// **none of these ever propagate into the timer** — the `CalendarCoordinator`
/// catches them, logs, and surfaces a non-blocking status; the running session is
/// unaffected (ADR-035).
nonisolated enum CalendarIntegrationError: Error, Equatable, Sendable, LocalizedError {
    /// No (or insufficient) Calendar permission.
    case notAuthorized
    /// Permission is restricted by policy and cannot be granted by the user.
    case accessRestricted
    /// The event store itself could not be reached.
    case eventStoreUnavailable
    /// The stored calendar identifier no longer resolves to a writable calendar.
    case calendarUnavailable
    /// No writable calendar is available to create events in.
    case noWritableCalendars
    /// A previously created event can no longer be found (deleted externally).
    case eventNotFound
    /// Saving a new event failed.
    case saveFailed
    /// Updating an existing event failed.
    case updateFailed
    /// Deleting an event failed.
    case deleteFailed
    /// The chosen calendar is read-only or otherwise invalid for event creation.
    case invalidCalendar

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Time Frame doesn't have permission to use your calendar."
        case .accessRestricted:
            return "Calendar access is restricted on this Mac."
        case .eventStoreUnavailable:
            return "Your calendar is temporarily unavailable."
        case .calendarUnavailable:
            return "The selected calendar is no longer available."
        case .noWritableCalendars:
            return "No calendar is available to add events to."
        case .eventNotFound:
            return "That calendar event no longer exists."
        case .saveFailed:
            return "Couldn't add the event to your calendar."
        case .updateFailed:
            return "Couldn't update your calendar."
        case .deleteFailed:
            return "Couldn't remove the calendar event."
        case .invalidCalendar:
            return "That calendar can't hold Time Frame events."
        }
    }

    /// A short status label for the compact sync indicator (never technical).
    var shortStatus: String {
        switch self {
        case .notAuthorized, .accessRestricted: return "Permission needed"
        case .calendarUnavailable, .invalidCalendar, .noWritableCalendars: return "Calendar unavailable"
        case .eventNotFound: return "Event missing"
        case .eventStoreUnavailable, .saveFailed, .updateFailed, .deleteFailed: return "Sync failed"
        }
    }
}
