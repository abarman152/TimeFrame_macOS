//
//  MenuBarPreferences.swift
//  time_frame
//
//  User preferences for the menu-bar surface, plus a small UserDefaults-backed store.
//  The menu bar is a UI surface, not persisted state — the only thing worth remembering
//  is whether the user wants it shown (and whether the countdown appears in the status
//  title). Lightweight, non-relational preferences, so they live in UserDefaults rather
//  than SwiftData — no schema change, no migration (ADR-048, §46/§63/§64). Mirrors
//  `NotificationPreferencesStore`.
//

import Foundation
import Observation

/// The persisted menu-bar preferences.
///
/// A pure value type (`Codable`, `Sendable`) with only primitive fields. `showInMenuBar`
/// gates whether the `MenuBarExtra` is inserted at all; `showCountdownInLabel` controls
/// whether the live countdown appears in the compact status-bar title (§8/§65). Neither
/// ever affects timer behaviour (§26).
nonisolated struct MenuBarPreferences: Codable, Equatable, Sendable {
    /// Whether the menu-bar item is shown. On by default (§26/§65).
    var showInMenuBar: Bool
    /// Whether the remaining time is shown in the status-bar title while a session runs.
    /// On by default; when off the title shows only the phase word (still never blank).
    var showCountdownInLabel: Bool

    /// Shipping defaults: menu bar on, countdown shown (§26/§65).
    static let `default` = MenuBarPreferences(
        showInMenuBar: true,
        showCountdownInLabel: true
    )
}

/// An observable, UserDefaults-backed store for `MenuBarPreferences`.
///
/// Injecting a `UserDefaults` (e.g. a scratch suite) keeps this fully testable without
/// touching the user's real preferences (mirrors `NotificationPreferencesStore`).
@MainActor
@Observable
final class MenuBarPreferencesStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let key = "menubar.settings.v1"

    private(set) var settings: MenuBarPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(MenuBarPreferences.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    var showInMenuBar: Bool {
        get { settings.showInMenuBar }
        set { update { $0.showInMenuBar = newValue } }
    }

    var showCountdownInLabel: Bool {
        get { settings.showCountdownInLabel }
        set { update { $0.showCountdownInLabel = newValue } }
    }

    /// Applies a mutation and writes it through to UserDefaults.
    func update(_ transform: (inout MenuBarPreferences) -> Void) {
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
