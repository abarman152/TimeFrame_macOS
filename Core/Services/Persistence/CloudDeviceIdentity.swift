//
//  CloudDeviceIdentity.swift
//  time_frame
//
//  A stable, per-install device identifier used to keep timer recovery
//  device-local once CloudKit sync is enabled (Milestone 13 / ADR-063).
//

import Foundation

/// A stable identifier for *this install of the app on this device*.
///
/// It is a random `UUID` string generated once and remembered in `UserDefaults`.
/// It is **not** an iCloud account identifier and carries **no** personal
/// information — it exists only so a synced running/paused `FocusSession` can be
/// attributed to the device that started it, and so timer recovery never takes
/// over a session that is running on a *different* device (the running-session
/// policy, ADR-063). Nothing about it is sent anywhere by this type; it is simply
/// stamped onto the `FocusSession` rows the store already syncs.
///
/// `UserDefaults` (not SwiftData) so the value is intentionally **local to this
/// device** and never itself syncs — each device keeps its own id.
nonisolated enum CloudDeviceIdentity {
    /// The defaults key under which the generated identifier is stored.
    static let storageKey = "cloud.device.identifier.v1"

    /// This device's identifier, generating and persisting one on first access.
    static var current: String { current(in: .standard) }

    /// The identifier stored in `defaults`, minting and persisting one if absent.
    /// Injecting a scratch `UserDefaults` keeps this fully testable without
    /// touching the real per-device value.
    static func current(in defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: storageKey)
        return generated
    }
}
