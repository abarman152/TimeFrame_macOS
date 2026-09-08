//
//  CloudSyncPresentationState.swift
//  time_frame
//
//  A pure, framework-free projection of the app's iCloud sync situation for the
//  Settings UI. Contains no CloudKit types (Milestone 13 / ADR-060).
//

import Foundation

/// Whether the user's iCloud account is usable for sync, derived without importing
/// CloudKit (from the presence of an iCloud ubiquity identity). `unknown` is the
/// not-yet-checked state.
nonisolated enum CloudAccountStatus: String, Equatable, Sendable, CaseIterable {
    case available
    case unavailable
    case unknown
}

/// An immutable, `Sendable` snapshot of the iCloud sync situation for display.
///
/// This is a **read-only projection** — like the menu bar / widget / App Intents
/// projections — built by a pure resolver from the active `PersistenceMode`, the
/// iCloud account status, and the user's sync preference. It holds no CloudKit
/// framework types and is never a second persistence authority: the UI observes it,
/// it never mutates the store or the timer (ADR-060). All user-facing phrasing lives
/// here so it stays in one place and never relies on colour alone.
nonisolated struct CloudSyncPresentationState: Equatable, Sendable {

    /// The distinct situations the Settings UI must communicate.
    enum Phase: String, Equatable, Sendable, CaseIterable {
        /// Sync is on but the iCloud account is unavailable (not signed in / disabled).
        case unavailable
        /// Sync is off by choice — the app is working locally only.
        case localOnly
        /// CloudKit mirroring is active and the account is available.
        case available
        /// CloudKit mirroring is active and a sync is in progress (best-effort).
        case syncing
        /// Sync was requested but CloudKit could not initialise; running on the
        /// preserved local store.
        case error
    }

    let phase: Phase
    let mode: PersistenceMode
    let accountStatus: CloudAccountStatus
    /// The last time a successful sync was observed, if known. Best-effort — see
    /// `CloudSyncCoordinator`; `nil` when unknown.
    let lastSyncedAt: Date?

    /// The constant section/title label. Kept here so the whole surface reads from
    /// one source of phrasing.
    var title: String { "iCloud Sync" }

    /// A short status word, safe to show on its own (never colour-only).
    var statusText: String {
        switch phase {
        case .unavailable: return "Unavailable"
        case .localOnly:   return "Local Only"
        case .available:   return "Available"
        case .syncing:     return "Syncing"
        case .error:       return "Sync Unavailable"
        }
    }

    /// An SF Symbol name to pair *with* the text (never a colour-only signal).
    var symbolName: String {
        switch phase {
        case .unavailable: return "icloud.slash"
        case .localOnly:   return "internaldrive"
        case .available:   return "checkmark.icloud"
        case .syncing:     return "arrow.triangle.2.circlepath.icloud"
        case .error:       return "exclamationmark.icloud"
        }
    }

    /// A one-sentence plain-language explanation for the current situation. Always
    /// reassures that the timer and local data are unaffected.
    var explanation: String {
        switch phase {
        case .unavailable:
            return "Sign in to iCloud in System Settings to sync your configurations, "
                + "templates, plans, and history across your devices. Time Frame keeps "
                + "working normally on this device."
        case .localOnly:
            return "iCloud Sync is off. Your data is stored on this device only. Turn it "
                + "on to keep your Mac and other devices in sync."
        case .available:
            return "Your configurations, templates, plans, and history sync across your "
                + "devices signed in to the same iCloud account."
        case .syncing:
            return "Syncing your data with iCloud. This happens in the background and never "
                + "interrupts a running timer."
        case .error:
            return "iCloud is currently unavailable, so Time Frame is using your local data. "
                + "Nothing is lost — it will sync again once iCloud is reachable."
        }
    }

    /// Whether CloudKit mirroring is actually active (drives the "on" appearance of
    /// the toggle's status line, independent of the preference switch).
    var isSyncing: Bool { phase == .available || phase == .syncing }

    // MARK: Resolver

    /// The neutral starting state before anything is known.
    static let unknown = CloudSyncPresentationState(
        phase: .localOnly, mode: .local, accountStatus: .unknown, lastSyncedAt: nil
    )

    /// Derives the presentation state from the authoritative inputs. Pure and
    /// total: every combination maps to exactly one phase, so the whole surface is
    /// unit-testable without CloudKit or a running app.
    ///
    /// - Parameters:
    ///   - mode: the persistence mode actually active this launch.
    ///   - account: the iCloud account status.
    ///   - syncEnabled: the user's "iCloud Sync" preference.
    ///   - isSyncing: whether a sync is currently observed in progress (best-effort).
    ///   - lastSyncedAt: last observed successful sync, if known.
    static func resolve(
        mode: PersistenceMode,
        account: CloudAccountStatus,
        syncEnabled: Bool,
        isSyncing: Bool = false,
        lastSyncedAt: Date? = nil
    ) -> CloudSyncPresentationState {
        let phase: Phase
        switch mode {
        case .local:
            // Local by resolution. If the user *wants* sync but we're local, the
            // reason is an unavailable account; otherwise it's a deliberate choice.
            phase = syncEnabled ? .unavailable : .localOnly
        case .fallback:
            // Requested cloud, fell back. Distinguish "no account" from other errors.
            phase = (account == .unavailable) ? .unavailable : .error
        case .cloudKit:
            if account == .unavailable {
                phase = .unavailable
            } else {
                phase = isSyncing ? .syncing : .available
            }
        }
        return CloudSyncPresentationState(
            phase: phase, mode: mode, accountStatus: account, lastSyncedAt: lastSyncedAt
        )
    }
}
