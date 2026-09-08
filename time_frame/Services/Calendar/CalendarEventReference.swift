//
//  CalendarEventReference.swift
//  time_frame
//
//  A persistence-safe pointer to a created calendar event. Deliberately holds only
//  identifiers — never an `EKEvent`, `EKCalendar`, or `EKEventStore` — so the
//  association can be stored and moved across boundaries without dragging EventKit
//  along (ADR-033/034).
//

import Foundation

/// A stable, `Codable` reference to one event Time Frame created in Apple Calendar.
///
/// The `eventIdentifier` is EventKit's own stable id for the saved event; the
/// `calendarIdentifier` records which calendar it lives in so a later update/delete
/// can detect if that calendar has since disappeared.
nonisolated struct CalendarEventReference: Codable, Equatable, Sendable, Hashable {
    let eventIdentifier: String
    let calendarIdentifier: String
}
