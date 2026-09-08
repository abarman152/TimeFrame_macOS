//
//  CloudSyncPreferences.swift
//  time_frame
//
//  The user's iCloud-sync preference and last-known sync metadata, in a small
//  UserDefaults-backed store. Mirrors the other integration preference stores
//  (menu bar / notifications). Non-relational, so UserDefaults not SwiftData —
//  no schema change (Milestone 13).
//

import Foundation
import Observation

/// The persisted iCloud-sync preferences.
///
/// A pure value type with only primitive fields. `syncEnabled` records whether the
/// user wants iCloud sync; because SwiftData binds a container to a CloudKit
/// database at *creation* time, changing it takes effect on the **next launch**
/// (the UI says so). `lastSyncedAt` is a best-effort timestamp for display only.
nonisolated struct CloudSyncPreferences: Codable, Equatable, Sendable {
    /// Whether the user wants iCloud sync. On by default so a signed-in user gets
    /// cross-device sync out of the box; it degrades to local automatically when
    /// iCloud is unavailable (never blocking the app).
    var syncEnabled: Bool

    /// The last time a successful sync was observed, if any. Display-only.
    var lastSyncedAt: Date?

    static let `default` = CloudSyncPreferences(syncEnabled: true, lastSyncedAt: nil)
}

/// An observable, UserDefaults-backed store for `CloudSyncPreferences`.
///
/// Injecting a `UserDefaults` (e.g. a scratch suite) keeps this fully testable
/// without touching the user's real preferences. Mirrors `MenuBarPreferencesStore`.
@MainActor
@Observable
final class CloudSyncPreferencesStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let key = "cloud.sync.settings.v1"

    private(set) var settings: CloudSyncPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(CloudSyncPreferences.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    var syncEnabled: Bool {
        get { settings.syncEnabled }
        set { update { $0.syncEnabled = newValue } }
    }

    var lastSyncedAt: Date? {
        get { settings.lastSyncedAt }
        set { update { $0.lastSyncedAt = newValue } }
    }

    /// Applies a mutation and writes it through to UserDefaults.
    func update(_ transform: (inout CloudSyncPreferences) -> Void) {
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
