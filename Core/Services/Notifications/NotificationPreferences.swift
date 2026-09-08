//
//  NotificationPreferences.swift
//  time_frame
//
//  User preferences for the notification integration, plus a small UserDefaults-backed
//  store. Lightweight, non-relational preferences, so they live in UserDefaults rather
//  than SwiftData — no schema change, no migration (ADR-044, §46/§79). Only value data
//  is ever persisted; no UserNotifications type is stored (§46).
//

import Foundation
import Observation

/// The persisted notification preferences.
///
/// A pure value type (`Codable`, `Sendable`) with only primitive fields (§45). The
/// master `isEnabled` gates everything; the per-category flags let the user silence a
/// specific transition without turning the integration off.
nonisolated struct NotificationPreferences: Codable, Equatable, Sendable {
    /// The master switch. Off until the user explicitly enables it (§70) — Time Frame
    /// never requests notification permission on first launch.
    var isEnabled: Bool
    /// Notify when a focus interval begins.
    var focusStarted: Bool
    /// Notify when a short break begins.
    var shortBreakStarted: Bool
    /// Notify when a long break begins.
    var longBreakStarted: Bool
    /// Notify when the whole session completes.
    var sessionCompleted: Bool
    /// Whether notifications play a sound.
    var soundEnabled: Bool
    /// Whether delivered notifications carry action buttons (Pause / Skip / Open).
    var actionsEnabled: Bool

    /// Shipping defaults (§70): integration off; every category on and sound + actions
    /// on, so once the user enables notifications the experience is complete without
    /// further configuration.
    static let `default` = NotificationPreferences(
        isEnabled: false,
        focusStarted: true,
        shortBreakStarted: true,
        longBreakStarted: true,
        sessionCompleted: true,
        soundEnabled: true,
        actionsEnabled: true
    )

    /// Whether a notification of the given category is permitted by the per-category
    /// toggles (independent of the master switch and authorization).
    func allows(_ category: NotificationCategory) -> Bool {
        switch category {
        case .focusStarted: return focusStarted
        case .shortBreakStarted: return shortBreakStarted
        case .longBreakStarted: return longBreakStarted
        case .sessionCompleted: return sessionCompleted
        }
    }

    /// The sound to use given the toggle.
    var sound: NotificationSound { soundEnabled ? .default : .none }
}

/// An observable, UserDefaults-backed store for `NotificationPreferences`.
///
/// Injecting a `UserDefaults` (e.g. a scratch suite) keeps this fully testable
/// without touching the user's real preferences (mirrors `CalendarPreferencesStore`).
@MainActor
@Observable
final class NotificationPreferencesStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let key = "notifications.settings.v1"

    private(set) var settings: NotificationPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
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

    var focusStarted: Bool {
        get { settings.focusStarted }
        set { update { $0.focusStarted = newValue } }
    }

    var shortBreakStarted: Bool {
        get { settings.shortBreakStarted }
        set { update { $0.shortBreakStarted = newValue } }
    }

    var longBreakStarted: Bool {
        get { settings.longBreakStarted }
        set { update { $0.longBreakStarted = newValue } }
    }

    var sessionCompleted: Bool {
        get { settings.sessionCompleted }
        set { update { $0.sessionCompleted = newValue } }
    }

    var soundEnabled: Bool {
        get { settings.soundEnabled }
        set { update { $0.soundEnabled = newValue } }
    }

    var actionsEnabled: Bool {
        get { settings.actionsEnabled }
        set { update { $0.actionsEnabled = newValue } }
    }

    /// Applies a mutation and writes it through to UserDefaults.
    func update(_ transform: (inout NotificationPreferences) -> Void) {
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
