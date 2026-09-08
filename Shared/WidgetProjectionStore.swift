//
//  WidgetProjectionStore.swift
//  Time Frame — shared widget projection (Milestone 11)
//
//  The read/write bridge for the widget projection over App Group `UserDefaults`. The app
//  writes; the widget reads. It is intentionally the *only* channel between the two
//  processes, and it is deliberately dumb: JSON in, JSON out, no app model state ever
//  touched (ADR-055). Every failure mode is isolated and non-fatal —
//
//   • a missing/denied App Group suite → the store is inert (writes no-op, reads `nil`);
//   • a corrupt or forward-incompatible payload on read → `nil` (the caller substitutes an
//     `.unavailable` projection), never a throw or crash.
//
//  Compiled into BOTH the app target and the widget extension. Foundation-only.
//

import Foundation

/// Reads and writes the single `WidgetProjection` in a shared `UserDefaults` suite.
///
/// Construct with `init(appGroupIdentifier:)` in the app and widget (both pass the same
/// group), or with `init(defaults:)` in tests (pass a volatile suite). A `nil` `defaults`
/// models the "App Group unavailable" case so callers exercise the fallback path.
// `@unchecked Sendable`: the only stored member is a `UserDefaults` (documented
// thread-safe) which the type reads and writes atomically; the compiler cannot prove
// `UserDefaults`'s Sendability, so we vouch for it here.
public struct WidgetProjectionStore: @unchecked Sendable {

    /// The App Group both the app and the widget extension declare in their entitlements.
    /// Documented in `docs/20-WIDGETKIT.md`.
    public static let appGroupIdentifier = "group.abirbarman.com.time-frame"

    /// The shared suite, or `nil` when it could not be opened (missing entitlement,
    /// denied container). When `nil` the store is a safe no-op.
    private let defaults: UserDefaults?

    /// Injects a specific suite (or `nil`). Used directly by tests.
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    /// Opens the named App Group suite. Falls back to an inert store if the suite cannot
    /// be created (so construction never fails and never crashes the widget).
    public init(appGroupIdentifier: String = WidgetProjectionStore.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Whether a shared suite is actually available. `false` means every read returns
    /// `nil` and every write is a no-op.
    public var isAvailable: Bool { defaults != nil }

    /// Persists the projection as JSON. Returns `true` on success, `false` when the suite
    /// is unavailable or encoding failed — the caller may log but must never treat a
    /// failed widget write as fatal to the app (§writer).
    @discardableResult
    public func write(_ projection: WidgetProjection) -> Bool {
        guard let defaults else { return false }
        do {
            let data = try WidgetProjectionStore.encoder.encode(projection)
            defaults.set(data, forKey: WidgetProjection.storageKey)
            return true
        } catch {
            return false
        }
    }

    /// Reads the last-written projection, or `nil` when the suite is unavailable, nothing
    /// has been written, the payload is corrupt, or its schema version is not understood.
    /// Corruption is swallowed, never thrown.
    public func read() -> WidgetProjection? {
        guard let defaults else { return nil }
        guard let data = defaults.data(forKey: WidgetProjection.storageKey) else { return nil }
        guard let projection = try? WidgetProjectionStore.decoder.decode(WidgetProjection.self, from: data) else {
            return nil
        }
        // A payload from an incompatible schema is treated as untrustworthy.
        guard projection.isSchemaCompatible else { return nil }
        return projection
    }

    /// Removes any stored projection. Used when the app has no meaningful state to show.
    public func clear() {
        defaults?.removeObject(forKey: WidgetProjection.storageKey)
    }

    // MARK: Codec

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
