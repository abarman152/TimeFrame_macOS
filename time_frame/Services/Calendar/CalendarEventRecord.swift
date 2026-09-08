//
//  CalendarEventRecord.swift
//  time_frame
//
//  The stored association between a Time Frame entity (a plan or a session) and the
//  calendar event(s) it created. This is the stable identity that prevents
//  duplicate events and enables update/delete (§24/§25/§59). It is a pure Codable
//  value kept in UserDefaults, so the core timer models stay free of any
//  Calendar/EventKit state (ADR-037). It never stores an EKEvent/EKCalendar.
//

import Foundation
import Observation

/// A persisted link between one Time Frame owner and its calendar event(s).
///
/// Identity is the Time Frame `ownerID` (a `SessionPlan` id or a `FocusSession`
/// id) — never the event title (§25). A single-event style yields one reference; a
/// per-interval style yields one per interval, all under the same owner.
nonisolated struct CalendarEventRecord: Codable, Equatable, Sendable, Identifiable {

    /// Which kind of Time Frame entity owns the event(s).
    nonisolated enum Owner: String, Codable, Sendable {
        case plan
        case session
    }

    let id: UUID
    let ownerType: Owner
    /// The stable id of the owning `SessionPlan` or `FocusSession`.
    let ownerID: UUID
    /// The granularity the events were created at.
    var style: CalendarEventStyle
    /// The created events (one for `.singlePlan`, N for `.perInterval`).
    var references: [CalendarEventReference]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerType: Owner,
        ownerID: UUID,
        style: CalendarEventStyle,
        references: [CalendarEventReference],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerType = ownerType
        self.ownerID = ownerID
        self.style = style
        self.references = references
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// An observable, UserDefaults-backed store of `CalendarEventRecord`s, keyed by
/// owner id for O(1) lookup. Injecting a `UserDefaults` keeps it test-isolated.
@MainActor
@Observable
final class CalendarEventRecordStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let key = "calendar.eventRecords.v1"

    /// All records, keyed by `ownerID`.
    private(set) var recordsByOwner: [UUID: CalendarEventRecord]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([CalendarEventRecord].self, from: data) {
            self.recordsByOwner = Dictionary(
                decoded.map { ($0.ownerID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            self.recordsByOwner = [:]
        }
    }

    /// The record for an owner, if any.
    func record(for ownerID: UUID) -> CalendarEventRecord? {
        recordsByOwner[ownerID]
    }

    /// All records (unordered).
    var all: [CalendarEventRecord] { Array(recordsByOwner.values) }

    /// Inserts or replaces the record for its owner.
    func upsert(_ record: CalendarEventRecord) {
        recordsByOwner[record.ownerID] = record
        persist()
    }

    /// Removes the record for an owner (idempotent).
    func remove(ownerID: UUID) {
        guard recordsByOwner.removeValue(forKey: ownerID) != nil else { return }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(recordsByOwner.values)) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
