//
//  CloudSyncCoordinator.swift
//  time_frame
//
//  Observes the app's iCloud sync situation and exposes it as a pure presentation
//  state for the Settings UI. It is an observer/adapter — never a second
//  persistence authority and never anywhere near the timer (Milestone 13).
//

import Foundation
import Observation
import os

/// An `@Observable`, `@MainActor` adapter that projects the iCloud sync situation.
///
/// It knows the `PersistenceMode` the store actually came up in (decided once, at
/// launch, by `PersistenceController.bootstrap`), reads the iCloud account status
/// from an injected provider, and combines them with the user's sync preference
/// into a pure `CloudSyncPresentationState`. It imports **no** CloudKit, owns no
/// timer state, and mutates no store — the actual sync is SwiftData's native
/// mirroring below the repositories (ADR-060/062).
///
/// Changing the sync preference here records intent; because SwiftData binds the
/// CloudKit database at container-creation time, it takes effect on the **next
/// launch** (the UI communicates this). The coordinator refreshes when the iCloud
/// account changes (`NSUbiquityIdentityDidChange`).
@MainActor
@Observable
final class CloudSyncCoordinator {
    /// The current pure projection the Settings UI observes.
    private(set) var presentationState: CloudSyncPresentationState

    /// The persistence mode active this launch (authoritative, set once).
    let activeMode: PersistenceMode

    /// The user's sync preference store. Toggling it takes effect next launch.
    let preferences: CloudSyncPreferencesStore

    @ObservationIgnored private let accountProvider: CloudAccountStatusProviding
    @ObservationIgnored private var ubiquityObserver: NSObjectProtocol?

    init(
        activeMode: PersistenceMode,
        preferences: CloudSyncPreferencesStore,
        accountProvider: CloudAccountStatusProviding = SystemCloudAccountStatusProvider()
    ) {
        self.activeMode = activeMode
        self.preferences = preferences
        self.accountProvider = accountProvider
        // Seed with a resolved state immediately so the UI never shows a blank.
        self.presentationState = CloudSyncPresentationState.resolve(
            mode: activeMode,
            account: accountProvider.currentStatus(),
            syncEnabled: preferences.syncEnabled,
            lastSyncedAt: preferences.lastSyncedAt
        )
        observeAccountChanges()
    }

    deinit {
        if let ubiquityObserver {
            NotificationCenter.default.removeObserver(ubiquityObserver)
        }
    }

    /// Recomputes the presentation state from the current account status and
    /// preference. Cheap and side-effect-free (beyond assigning the projection);
    /// safe to call from `.task`/`onAppear` in Settings.
    func refresh() {
        let account = accountProvider.currentStatus()
        presentationState = CloudSyncPresentationState.resolve(
            mode: activeMode,
            account: account,
            syncEnabled: preferences.syncEnabled,
            lastSyncedAt: preferences.lastSyncedAt
        )
        AppLog.persistence.info(
            "Cloud sync state: \(self.presentationState.phase.rawValue, privacy: .public) (mode \(self.activeMode.rawValue, privacy: .public))."
        )
    }

    /// The reason sync is currently inactive, if any (`nil` when actively syncing).
    var inactiveReason: CloudSyncError? {
        CloudSyncError.reason(
            mode: activeMode,
            account: presentationState.accountStatus,
            syncEnabled: preferences.syncEnabled
        )
    }

    /// The user's sync preference. Writing it persists the intent; the note in the
    /// UI explains it applies on next launch.
    var syncEnabled: Bool {
        get { preferences.syncEnabled }
        set {
            preferences.syncEnabled = newValue
            refresh()
        }
    }

    /// The persistence mode to request at launch for a given preference. Kept here
    /// (pure/static) so the app and tests resolve startup identically: sync on →
    /// request CloudKit; off → local.
    static func requestedMode(syncEnabled: Bool) -> PersistenceMode {
        syncEnabled ? .cloudKit : .local
    }

    private func observeAccountChanges() {
        ubiquityObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
}
