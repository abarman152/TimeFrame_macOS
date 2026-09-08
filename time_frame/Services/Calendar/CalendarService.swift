//
//  CalendarService.swift
//  time_frame
//
//  The boundary protocol between Time Frame and any calendar backend. It trades
//  only in pure value types (drafts, references, descriptors, statuses) — never an
//  `EKEvent`, `EKCalendar`, or `EKEventStore`. `EventKitCalendarService` is the
//  production adapter; `FakeCalendarService` (test target) drives deterministic
//  tests without touching the user's real Calendar (ADR-032, §43/§44).
//

import Foundation

/// A calendar backend Time Frame can create and manage events through.
///
/// `@MainActor` because EventKit model objects are not safely shared across actors
/// and the app performs the (small, infrequent) calendar work on meaningful
/// transitions only — never on a timer tick (§53). All throwing methods throw
/// `CalendarIntegrationError`, never a raw EventKit error.
@MainActor
protocol CalendarService: AnyObject {

    /// The current authorization status (no prompt).
    func authorizationStatus() -> CalendarAuthorizationStatus

    /// Requests access if it has not been decided yet, returning the resulting
    /// status. Requesting after a denial does not re-prompt (the system returns the
    /// existing status), so callers may call this freely.
    func requestAccess() async -> CalendarAuthorizationStatus

    /// The calendars new events may be created in.
    func writableCalendars() throws -> [CalendarDescriptor]

    /// The identifier of the system default calendar for new events, if any.
    func defaultCalendarIdentifier() -> String?

    /// Creates an event from a draft and returns a stable reference to it.
    func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEventReference

    /// Updates the referenced event to match the draft. Throws `.eventNotFound`
    /// if the event no longer exists (deleted externally). Used for an explicit,
    /// user-initiated re-sync of a Time Frame-owned event (e.g. a plan re-add).
    func updateEvent(_ reference: CalendarEventReference, with draft: CalendarEventDraft) throws

    /// Adjusts **only** the end date of an existing event. Used to keep a live
    /// session's event in step with the authoritative timer (pause/resume/stop/
    /// completion) without ever overwriting user-owned fields like title, notes,
    /// location, or calendar (the ownership model of ADR-036, §37/§38). Throws
    /// `.eventNotFound` if the event was deleted externally.
    func adjustEventEnd(_ reference: CalendarEventReference, to endDate: Date) throws

    /// Deletes the referenced event. A missing event is treated as already gone
    /// (no error), so deletion is idempotent.
    func deleteEvent(_ reference: CalendarEventReference) throws

    /// Whether the referenced event still exists in the store.
    func eventExists(_ reference: CalendarEventReference) -> Bool
}
