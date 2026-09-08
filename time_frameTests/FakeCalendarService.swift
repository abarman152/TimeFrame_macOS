//
//  FakeCalendarService.swift
//  time_frameTests
//
//  A deterministic, in-memory CalendarService for tests. No EventKit, no real
//  Calendar, no permissions prompt (§43/§75). Authorization status, available
//  calendars, and per-operation failures are all configurable so every branch
//  (including EventKit failure and permission denial) can be exercised.
//

import Foundation
@testable import time_frame

@MainActor
final class FakeCalendarService: CalendarService {

    // MARK: Configurable state

    var status: CalendarAuthorizationStatus
    /// The status a `requestAccess()` resolves to when currently `.notDetermined`.
    var grantsOnRequest: CalendarAuthorizationStatus
    var calendars: [CalendarDescriptor]

    /// Inject a failure into the matching operation (nil = succeed).
    var failCreate: CalendarIntegrationError?
    var failUpdate: CalendarIntegrationError?
    var failAdjust: CalendarIntegrationError?
    var failDelete: CalendarIntegrationError?
    var failCalendars: CalendarIntegrationError?

    // MARK: Observed effects

    private(set) var storedEvents: [String: CalendarEventDraft] = [:]
    private(set) var createCount = 0
    private(set) var updateCount = 0
    private(set) var adjustCount = 0
    private(set) var deleteCount = 0
    private(set) var requestCount = 0

    init(
        status: CalendarAuthorizationStatus = .fullAccess,
        grantsOnRequest: CalendarAuthorizationStatus = .fullAccess,
        calendars: [CalendarDescriptor] = FakeCalendarService.defaultCalendars
    ) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
        self.calendars = calendars
    }

    nonisolated static let defaultCalendars: [CalendarDescriptor] = [
        CalendarDescriptor(id: "cal-personal", title: "Personal", colorHex: "#FF0000", allowsEventCreation: true),
        CalendarDescriptor(id: "cal-work", title: "Work", colorHex: "#0000FF", allowsEventCreation: true)
    ]

    // MARK: CalendarService

    func authorizationStatus() -> CalendarAuthorizationStatus { status }

    func requestAccess() async -> CalendarAuthorizationStatus {
        requestCount += 1
        if status == .notDetermined { status = grantsOnRequest }
        return status
    }

    func writableCalendars() throws -> [CalendarDescriptor] {
        if let failCalendars { throw failCalendars }
        guard status.isSufficient else { throw CalendarIntegrationError.notAuthorized }
        return calendars.filter(\.allowsEventCreation)
    }

    func defaultCalendarIdentifier() -> String? { calendars.first?.id }

    func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEventReference {
        if let failCreate { throw failCreate }
        guard status.isSufficient else { throw CalendarIntegrationError.notAuthorized }
        createCount += 1
        let identifier = "event-\(createCount)-\(UUID().uuidString)"
        storedEvents[identifier] = draft
        let calendarID = draft.calendarIdentifier ?? defaultCalendarIdentifier() ?? "cal-default"
        return CalendarEventReference(eventIdentifier: identifier, calendarIdentifier: calendarID)
    }

    func updateEvent(_ reference: CalendarEventReference, with draft: CalendarEventDraft) throws {
        if let failUpdate { throw failUpdate }
        guard status.isSufficient else { throw CalendarIntegrationError.notAuthorized }
        guard storedEvents[reference.eventIdentifier] != nil else { throw CalendarIntegrationError.eventNotFound }
        updateCount += 1
        storedEvents[reference.eventIdentifier] = draft
    }

    func adjustEventEnd(_ reference: CalendarEventReference, to endDate: Date) throws {
        if let failAdjust { throw failAdjust }
        guard status.isSufficient else { throw CalendarIntegrationError.notAuthorized }
        guard var draft = storedEvents[reference.eventIdentifier] else { throw CalendarIntegrationError.eventNotFound }
        adjustCount += 1
        draft.endDate = max(endDate, draft.startDate)
        storedEvents[reference.eventIdentifier] = draft
    }

    func deleteEvent(_ reference: CalendarEventReference) throws {
        if let failDelete { throw failDelete }
        guard status.isSufficient else { throw CalendarIntegrationError.notAuthorized }
        deleteCount += 1
        storedEvents[reference.eventIdentifier] = nil
    }

    func eventExists(_ reference: CalendarEventReference) -> Bool {
        storedEvents[reference.eventIdentifier] != nil
    }

    // MARK: Test helpers

    /// Simulates the user deleting an event in Apple Calendar directly.
    func removeExternally(_ reference: CalendarEventReference) {
        storedEvents[reference.eventIdentifier] = nil
    }

    var savedEventCount: Int { storedEvents.count }
}

/// A scratch `UserDefaults` suite that never touches the real preferences.
@MainActor
func makeScratchDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "test.\(name)")!
    defaults.removePersistentDomain(forName: "test.\(name)")
    return defaults
}
