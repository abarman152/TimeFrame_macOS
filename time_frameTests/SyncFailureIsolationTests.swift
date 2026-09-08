//
//  SyncFailureIsolationTests.swift
//  time_frameTests (Milestone 13)
//
//  A CloudKit problem must never reach the timer. When the CloudKit store cannot
//  be created the app falls back to the preserved local store, and the timer runs
//  exactly as before over that store. The sync projection can report an error at
//  the same time without any effect on the engine (ADR-060/062).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Sync failure isolation")
struct SyncFailureIsolationTests {

    private enum StubError: Error { case cloudDown }

    @Test("After a CloudKit init failure, the timer runs on the fallback store")
    func timerRunsAfterFallback() throws {
        // The store comes up in fallback because CloudKit "failed".
        let local = try makeInMemoryContainer()
        let boot = PersistenceController.bootstrap(
            requestedMode: .cloudKit,
            inMemory: true,
            makeCloud: { throw StubError.cloudDown },
            makeLocal: { local }
        )
        #expect(boot.activeMode == .fallback)

        // A coordinator over that container drives a real session deterministically.
        let clock = MockTimeSource()
        let coord = makeCoordinator(boot.container, clock: clock)
        let config = try insertConfiguration(boot.container) // focus 10
        let session = try #require(try coord.startSession(configuration: config))

        clock.advance(by: 3)
        try coord.tick()
        #expect(coord.engine.state == .running)
        expectClose(coord.engine.remaining, 7)

        try coord.pause()
        #expect(coord.engine.state == .paused)
        try coord.resume()
        #expect(coord.engine.state == .running)

        try coord.stop()
        #expect(coord.activeSession?.id == session.id)
        #expect(coord.engine.state == .cancelled)
    }

    @Test("The sync projection can report an error while the timer is unaffected")
    func projectionErrorDoesNotTouchTimer() throws {
        let local = try makeInMemoryContainer()
        let boot = PersistenceController.bootstrap(
            requestedMode: .cloudKit,
            inMemory: true,
            makeCloud: { throw StubError.cloudDown },
            makeLocal: { local }
        )

        let defaults = UserDefaults(suiteName: "cloud.sync.iso.\(UUID().uuidString)")!
        let cloud = CloudSyncCoordinator(
            activeMode: boot.activeMode,
            preferences: CloudSyncPreferencesStore(defaults: defaults),
            accountProvider: FakeCloudAccountStatusProvider(.available)
        )
        #expect(cloud.presentationState.phase == .error)
        #expect(cloud.inactiveReason == .cloudKitUnavailable)

        // Timer still starts and runs.
        let clock = MockTimeSource()
        let coord = makeCoordinator(boot.container, clock: clock)
        let config = try insertConfiguration(boot.container)
        _ = try coord.startSession(configuration: config)
        #expect(coord.engine.state == .running)
    }
}
