//
//  CalendarPersistenceTests.swift
//  time_frameTests
//
//  Round-trip tests for the UserDefaults-backed Calendar settings and event-record
//  stores. These persist associations and preferences without any SwiftData schema
//  change (ADR-037). Every test uses a scratch defaults suite.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Calendar persistence")
struct CalendarPersistenceTests {

    @Test("Settings default to off with sensible values")
    func settingsDefaults() {
        let store = CalendarPreferencesStore(defaults: makeScratchDefaults())
        #expect(store.isEnabled == false)
        #expect(store.eventStyle == .singlePlan)
        #expect(store.creationTrigger == .both)
        #expect(store.defaultCalendarIdentifier == nil)
    }

    @Test("Settings persist across store instances")
    func settingsRoundTrip() {
        let defaults = makeScratchDefaults()
        let store = CalendarPreferencesStore(defaults: defaults)
        store.isEnabled = true
        store.eventStyle = .perInterval
        store.creationTrigger = .sessionStart
        store.defaultCalendarIdentifier = "cal-work"

        let reloaded = CalendarPreferencesStore(defaults: defaults)
        #expect(reloaded.isEnabled == true)
        #expect(reloaded.eventStyle == .perInterval)
        #expect(reloaded.creationTrigger == .sessionStart)
        #expect(reloaded.defaultCalendarIdentifier == "cal-work")
    }

    @Test("Event records are stored, fetched, and removed by owner")
    func recordCRUD() {
        let defaults = makeScratchDefaults()
        let store = CalendarEventRecordStore(defaults: defaults)
        let ownerID = UUID()
        let record = CalendarEventRecord(
            ownerType: .plan,
            ownerID: ownerID,
            style: .singlePlan,
            references: [CalendarEventReference(eventIdentifier: "e1", calendarIdentifier: "cal-work")]
        )
        store.upsert(record)
        #expect(store.record(for: ownerID)?.references.first?.eventIdentifier == "e1")

        // Persist across instances.
        let reloaded = CalendarEventRecordStore(defaults: defaults)
        #expect(reloaded.record(for: ownerID) != nil)

        reloaded.remove(ownerID: ownerID)
        #expect(reloaded.record(for: ownerID) == nil)
        #expect(CalendarEventRecordStore(defaults: defaults).record(for: ownerID) == nil)
    }

    @Test("Upsert replaces the record for an owner rather than duplicating")
    func upsertReplaces() {
        let store = CalendarEventRecordStore(defaults: makeScratchDefaults())
        let ownerID = UUID()
        store.upsert(CalendarEventRecord(ownerType: .session, ownerID: ownerID, style: .singlePlan,
                                         references: [CalendarEventReference(eventIdentifier: "a", calendarIdentifier: "c")]))
        store.upsert(CalendarEventRecord(ownerType: .session, ownerID: ownerID, style: .perInterval,
                                         references: [CalendarEventReference(eventIdentifier: "b", calendarIdentifier: "c")]))
        #expect(store.all.count == 1)
        #expect(store.record(for: ownerID)?.style == .perInterval)
    }
}
