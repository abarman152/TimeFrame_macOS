//
//  CalendarSettings.swift
//  time_frame
//
//  User preferences for the Calendar integration, plus a small UserDefaults-backed
//  store. These are lightweight, non-relational preferences, so they live in
//  UserDefaults rather than SwiftData — no schema change, no migration (ADR-037,
//  §46). No EventKit object is ever persisted; the default calendar is stored by
//  its stable identifier only (§20/§46).
//

import Foundation
import Observation

/// The persisted Calendar preferences.
nonisolated struct CalendarSettings: Codable, Equatable, Sendable {
    /// Whether the integration is on. Off until the user explicitly enables it
    /// (§47) — Time Frame never requests Calendar access on first launch.
    var isEnabled: Bool
    /// The chosen default calendar's stable identifier, or nil for the system
    /// default. Stored by identifier, never by title (§20).
    var defaultCalendarIdentifier: String?
    /// Whole-plan vs per-interval events.
    var eventStyle: CalendarEventStyle
    /// When events are created.
    var creationTrigger: CalendarCreationTrigger

    /// The shipping defaults (§47): integration off, single-event, both triggers so
    /// that once enabled a live timer start is reflected on the calendar (the user's
    /// stated goal) while manual add stays available.
    static let `default` = CalendarSettings(
        isEnabled: false,
        defaultCalendarIdentifier: nil,
        eventStyle: .singlePlan,
        creationTrigger: .both
    )
}

/// An observable, UserDefaults-backed store for `CalendarSettings`.
///
/// Injecting a `UserDefaults` (e.g. a scratch suite) keeps this fully testable
/// without touching the user's real preferences.
@MainActor
@Observable
final class CalendarPreferencesStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let key = "calendar.settings.v1"

    /// The current settings. Mutating through the helpers below persists.
    private(set) var settings: CalendarSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(CalendarSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    // MARK: Convenience accessors (each persists)

    var isEnabled: Bool {
        get { settings.isEnabled }
        set { update { $0.isEnabled = newValue } }
    }

    var defaultCalendarIdentifier: String? {
        get { settings.defaultCalendarIdentifier }
        set { update { $0.defaultCalendarIdentifier = newValue } }
    }

    var eventStyle: CalendarEventStyle {
        get { settings.eventStyle }
        set { update { $0.eventStyle = newValue } }
    }

    var creationTrigger: CalendarCreationTrigger {
        get { settings.creationTrigger }
        set { update { $0.creationTrigger = newValue } }
    }

    /// Applies a mutation and writes it through to UserDefaults.
    func update(_ transform: (inout CalendarSettings) -> Void) {
        var copy = settings
        transform(&copy)
        guard copy != settings else { return }
        settings = copy
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
