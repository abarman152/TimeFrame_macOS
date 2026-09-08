//
//  EventKitCalendarService.swift
//  time_frame
//
//  The **only** file in Time Frame that imports EventKit. It adapts the app's pure
//  Calendar vocabulary (drafts, references, descriptors, statuses) to `EKEventStore`
//  and back. No `EKEvent`/`EKCalendar`/`EKEventStore` ever escapes this type
//  (ADR-032). Raw EventKit errors are mapped to `CalendarIntegrationError` so the
//  UI never sees a technical error (§40).
//

import Foundation
import EventKit
import os
#if canImport(AppKit)
import AppKit
#endif

/// Production `CalendarService` backed by the system `EKEventStore`.
///
/// A single `EKEventStore` is created and reused for the app's lifetime (§81 — do
/// not repeatedly instantiate stores). All work happens on the main actor; the
/// operations are small and infrequent (only on meaningful transitions — §53), so
/// this does not block meaningful UI work.
@MainActor
final class EventKitCalendarService: CalendarService {

    private let store = EKEventStore()

    // MARK: Authorization

    func authorizationStatus() -> CalendarAuthorizationStatus {
        Self.map(EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccess() async -> CalendarAuthorizationStatus {
        // Only the *first* request prompts; a later call with a decided status just
        // returns it, so callers may call this freely without re-prompting (§16).
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            do {
                _ = try await store.requestFullAccessToEvents()
            } catch {
                AppLog.calendar.error("Calendar access request failed: \(String(describing: error), privacy: .public)")
            }
        }
        let status = Self.map(EKEventStore.authorizationStatus(for: .event))
        AppLog.calendar.info("Calendar authorization status: \(status.rawValue, privacy: .public).")
        return status
    }

    // MARK: Calendars

    func writableCalendars() throws -> [CalendarDescriptor] {
        try requireAccess()
        let calendars = store.calendars(for: .event).filter { $0.allowsContentModifications }
        return calendars
            .map(Self.descriptor(from:))
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func defaultCalendarIdentifier() -> String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    // MARK: Event lifecycle

    func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEventReference {
        try requireAccess()
        let calendar = try resolveCalendar(draft.calendarIdentifier)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        apply(draft, to: event)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            AppLog.calendar.error("Event save failed: \(String(describing: error), privacy: .public)")
            throw CalendarIntegrationError.saveFailed
        }
        guard let identifier = event.eventIdentifier else { throw CalendarIntegrationError.saveFailed }
        AppLog.calendar.info("Created calendar event.")
        return CalendarEventReference(
            eventIdentifier: identifier,
            calendarIdentifier: calendar.calendarIdentifier
        )
    }

    func updateEvent(_ reference: CalendarEventReference, with draft: CalendarEventDraft) throws {
        try requireAccess()
        guard let event = store.event(withIdentifier: reference.eventIdentifier) else {
            throw CalendarIntegrationError.eventNotFound
        }
        apply(draft, to: event)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            AppLog.calendar.error("Event update failed: \(String(describing: error), privacy: .public)")
            throw CalendarIntegrationError.updateFailed
        }
        AppLog.calendar.info("Updated calendar event.")
    }

    func adjustEventEnd(_ reference: CalendarEventReference, to endDate: Date) throws {
        try requireAccess()
        guard let event = store.event(withIdentifier: reference.eventIdentifier) else {
            throw CalendarIntegrationError.eventNotFound
        }
        // Only the end date — user-owned title/notes/location/calendar untouched.
        event.endDate = max(endDate, event.startDate)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            AppLog.calendar.error("Event end adjust failed: \(String(describing: error), privacy: .public)")
            throw CalendarIntegrationError.updateFailed
        }
        AppLog.calendar.info("Adjusted calendar event end.")
    }

    func deleteEvent(_ reference: CalendarEventReference) throws {
        try requireAccess()
        guard let event = store.event(withIdentifier: reference.eventIdentifier) else {
            // Already gone — deletion is idempotent (§70).
            return
        }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
        } catch {
            AppLog.calendar.error("Event delete failed: \(String(describing: error), privacy: .public)")
            throw CalendarIntegrationError.deleteFailed
        }
        AppLog.calendar.info("Deleted calendar event.")
    }

    func eventExists(_ reference: CalendarEventReference) -> Bool {
        store.event(withIdentifier: reference.eventIdentifier) != nil
    }

    // MARK: Helpers

    /// Ensures full access before any store mutation/read.
    private func requireAccess() throws {
        switch authorizationStatus() {
        case .fullAccess: return
        case .restricted: throw CalendarIntegrationError.accessRestricted
        default: throw CalendarIntegrationError.notAuthorized
        }
    }

    /// Resolves a draft's target calendar, falling back to the system default and
    /// validating that it can hold events.
    private func resolveCalendar(_ identifier: String?) throws -> EKCalendar {
        let calendar: EKCalendar?
        if let identifier {
            calendar = store.calendar(withIdentifier: identifier)
            // A stored identifier that no longer resolves is a distinct failure so
            // the UI can ask the user to pick another calendar (§20/§55).
            guard calendar != nil else { throw CalendarIntegrationError.calendarUnavailable }
        } else {
            calendar = store.defaultCalendarForNewEvents
        }
        guard let resolved = calendar else { throw CalendarIntegrationError.noWritableCalendars }
        guard resolved.allowsContentModifications else { throw CalendarIntegrationError.invalidCalendar }
        return resolved
    }

    private func apply(_ draft: CalendarEventDraft, to event: EKEvent) {
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = max(draft.endDate, draft.startDate)
        event.notes = draft.notes
        event.location = draft.location
    }

    private static func descriptor(from calendar: EKCalendar) -> CalendarDescriptor {
        CalendarDescriptor(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: hexString(from: calendar.cgColor),
            allowsEventCreation: calendar.allowsContentModifications
        )
    }

    /// A `#RRGGBB` string for a calendar colour, or nil if it can't be resolved.
    private static func hexString(from cgColor: CGColor?) -> String? {
        #if canImport(AppKit)
        guard let cgColor, let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return nil }
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        return nil
        #endif
    }

    private static func map(_ status: EKAuthorizationStatus) -> CalendarAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .fullAccess: return .fullAccess
        case .writeOnly: return .writeOnly
        @unknown default: return .denied
        }
    }
}
