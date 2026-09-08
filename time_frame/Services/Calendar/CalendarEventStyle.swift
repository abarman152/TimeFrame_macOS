//
//  CalendarEventStyle.swift
//  time_frame
//
//  The two granularities at which Time Frame represents a plan/session in Apple
//  Calendar, and the trigger that decides when events are created. Pure value
//  vocabulary, persisted only as their raw strings.
//

import Foundation

/// How a plan or session is projected onto the calendar.
nonisolated enum CalendarEventStyle: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    /// One event spanning the whole plan/session (e.g. 10:00–11:55 "Research").
    case singlePlan
    /// One event per interval (Focus / Short Break / Long Break), back to back.
    case perInterval

    var id: String { rawValue }

    /// A short label for pickers.
    var displayLabel: String {
        switch self {
        case .singlePlan: return "One event for plan"
        case .perInterval: return "One event per interval"
        }
    }
}

/// When Time Frame creates calendar events.
///
/// Manual only ever means "the user pressed Add to Calendar"; the session-start
/// trigger additionally creates an event the moment a live timer starts.
nonisolated enum CalendarCreationTrigger: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    /// Only when the user explicitly adds a plan to the calendar.
    case manual
    /// Only automatically, when a session starts.
    case sessionStart
    /// Both of the above.
    case both

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .manual: return "I manually add a plan"
        case .sessionStart: return "A session starts"
        case .both: return "Manual + session start"
        }
    }

    /// Whether a live session start should create an event under this trigger.
    var createsOnSessionStart: Bool { self == .sessionStart || self == .both }

    /// Whether the manual "Add to Calendar" affordance should be offered.
    var allowsManual: Bool { self == .manual || self == .both }
}
