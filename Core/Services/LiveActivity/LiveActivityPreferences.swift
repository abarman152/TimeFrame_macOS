//
//  LiveActivityPreferences.swift
//  time_frame (Milestone 16)
//
//  User preferences for the Live Activity surface, plus a small UserDefaults-backed store. The
//  Live Activity is a presentation surface, not persisted domain state — the only things worth
//  remembering are whether the user wants it and what it shows. Lightweight, non-relational
//  preferences, so they live in UserDefaults rather than SwiftData — no schema change, no
//  migration, the schema stays V6 (ADR-075). Mirrors `MenuBarPreferencesStore`.
//

import Foundation
import Observation

/// The persisted Live Activity preferences. A pure value type (`Codable`, `Sendable`) with only
/// primitive fields; none of them ever affects timer behaviour (the timer never reads them).
nonisolated struct LiveActivityPreferences: Codable, Equatable, Sendable {
    /// Whether a Live Activity is started for running sessions. On by default.
    var enabled: Bool
    /// Whether the task name appears on the activity. Applied when an activity starts (the task
    /// name is a frozen static attribute, so a mid-run change takes effect on the next session).
    var showsTaskName: Bool
    /// Whether the configuration/plan name appears on the activity. Applied at start (as above).
    var showsConfiguration: Bool

    /// Shipping defaults: enabled, showing task and configuration.
    static let `default` = LiveActivityPreferences(
        enabled: true,
        showsTaskName: true,
        showsConfiguration: true
    )
}

/// An observable, UserDefaults-backed store for `LiveActivityPreferences`. Injecting a
/// `UserDefaults` (e.g. a scratch suite) keeps this fully testable without touching the user's
/// real preferences (mirrors `MenuBarPreferencesStore`/`NotificationPreferencesStore`).
@MainActor
@Observable
final class LiveActivityPreferencesStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let key = "liveactivity.settings.v1"

    private(set) var settings: LiveActivityPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(LiveActivityPreferences.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    var enabled: Bool {
        get { settings.enabled }
        set { update { $0.enabled = newValue } }
    }

    var showsTaskName: Bool {
        get { settings.showsTaskName }
        set { update { $0.showsTaskName = newValue } }
    }

    var showsConfiguration: Bool {
        get { settings.showsConfiguration }
        set { update { $0.showsConfiguration = newValue } }
    }

    /// Applies a mutation and writes it through to UserDefaults.
    func update(_ transform: (inout LiveActivityPreferences) -> Void) {
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
