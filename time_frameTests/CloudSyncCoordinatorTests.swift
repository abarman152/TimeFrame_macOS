//
//  CloudSyncCoordinatorTests.swift
//  time_frameTests (Milestone 13)
//
//  The @Observable sync adapter: it projects the resolved mode + account status,
//  reacts to a preference change, and never owns store/timer state. Driven by a
//  fake account provider and a scratch UserDefaults — no real iCloud.
//

import Foundation
import Testing
@testable import time_frame

/// A fake iCloud account provider with a settable status.
final class FakeCloudAccountStatusProvider: CloudAccountStatusProviding, @unchecked Sendable {
    var status: CloudAccountStatus
    init(_ status: CloudAccountStatus) { self.status = status }
    func currentStatus() -> CloudAccountStatus { status }
}

@MainActor
@Suite("Cloud sync coordinator")
struct CloudSyncCoordinatorTests {

    private func scratchPreferences(syncEnabled: Bool = true) -> CloudSyncPreferencesStore {
        let defaults = UserDefaults(suiteName: "cloud.sync.test.\(UUID().uuidString)")!
        let store = CloudSyncPreferencesStore(defaults: defaults)
        store.syncEnabled = syncEnabled
        return store
    }

    @Test("Seeds a resolved state immediately (no blank)")
    func seedsState() {
        let coord = CloudSyncCoordinator(
            activeMode: .cloudKit,
            preferences: scratchPreferences(),
            accountProvider: FakeCloudAccountStatusProvider(.available)
        )
        #expect(coord.presentationState.phase == .available)
        #expect(coord.inactiveReason == nil)
    }

    @Test("Fallback mode with an account reports the error phase and reason")
    func fallbackReason() {
        let coord = CloudSyncCoordinator(
            activeMode: .fallback,
            preferences: scratchPreferences(),
            accountProvider: FakeCloudAccountStatusProvider(.available)
        )
        #expect(coord.presentationState.phase == .error)
        #expect(coord.inactiveReason == .cloudKitUnavailable)
    }

    @Test("Turning sync off updates the projection and persists the intent")
    func toggleOff() {
        let prefs = scratchPreferences(syncEnabled: true)
        let coord = CloudSyncCoordinator(
            activeMode: .local,
            preferences: prefs,
            accountProvider: FakeCloudAccountStatusProvider(.unavailable)
        )
        // Sync wanted but no account → unavailable.
        #expect(coord.presentationState.phase == .unavailable)

        coord.syncEnabled = false
        #expect(prefs.syncEnabled == false)                 // persisted intent
        #expect(coord.presentationState.phase == .localOnly) // projection refreshed
        #expect(coord.inactiveReason == .syncDisabled)
    }

    @Test("Refresh picks up an account becoming available")
    func refreshAccount() {
        let provider = FakeCloudAccountStatusProvider(.unavailable)
        let coord = CloudSyncCoordinator(
            activeMode: .cloudKit,
            preferences: scratchPreferences(),
            accountProvider: provider
        )
        #expect(coord.presentationState.phase == .unavailable)

        provider.status = .available
        coord.refresh()
        #expect(coord.presentationState.phase == .available)
    }
}
