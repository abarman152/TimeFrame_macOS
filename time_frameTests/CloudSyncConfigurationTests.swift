//
//  CloudSyncConfigurationTests.swift
//  time_frameTests (Milestone 13)
//
//  The persistence-mode value, startup mode resolution, per-install device
//  identity, and the PersistenceController bootstrap's safe fallback — all
//  deterministic and with no real CloudKit account.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Cloud sync configuration")
struct CloudSyncConfigurationTests {

    private enum StubError: Error { case cloudUnavailable }

    // MARK: Persistence mode

    @Test("Only .cloudKit reports CloudKit active")
    func modeActivity() {
        #expect(PersistenceMode.cloudKit.isCloudActive)
        #expect(!PersistenceMode.local.isCloudActive)
        #expect(!PersistenceMode.fallback.isCloudActive)
    }

    @Test("Requested startup mode follows the sync preference")
    func requestedMode() {
        #expect(CloudSyncCoordinator.requestedMode(syncEnabled: true) == .cloudKit)
        #expect(CloudSyncCoordinator.requestedMode(syncEnabled: false) == .local)
    }

    // MARK: Bootstrap — local

    @Test("A local request opens the local store and reports .local")
    func bootstrapLocal() throws {
        let local = try makeInMemoryContainer()
        let boot = PersistenceController.bootstrap(
            requestedMode: .local,
            inMemory: true,
            makeCloud: { Issue.record("cloud must not be attempted for a local request"); return local },
            makeLocal: { local }
        )
        #expect(boot.activeMode == .local)
        #expect(boot.container === local)
    }

    // MARK: Bootstrap — cloud success

    @Test("A successful CloudKit request reports .cloudKit")
    func bootstrapCloudSuccess() throws {
        let cloud = try makeInMemoryContainer()
        let local = try makeInMemoryContainer()
        let boot = PersistenceController.bootstrap(
            requestedMode: .cloudKit,
            inMemory: true,
            makeCloud: { cloud },
            makeLocal: { local }
        )
        #expect(boot.activeMode == .cloudKit)
        #expect(boot.container === cloud)
    }

    // MARK: Bootstrap — cloud failure falls back to the existing local store

    @Test("A CloudKit failure falls back to the existing local store as .fallback")
    func bootstrapCloudFallback() throws {
        let local = try makeInMemoryContainer()
        var madeLocal = false
        let boot = PersistenceController.bootstrap(
            requestedMode: .cloudKit,
            inMemory: true,
            makeCloud: { throw StubError.cloudUnavailable },
            makeLocal: { madeLocal = true; return local }
        )
        #expect(boot.activeMode == .fallback)         // reported as fallback, not local
        #expect(boot.container === local)             // the SAME local store, not a new empty one
        #expect(madeLocal)                            // fallback actually opened the local store
    }

    // MARK: Device identity

    @Test("A device identity is stable and persisted per store")
    func deviceIdentityStable() {
        let defaults = UserDefaults(suiteName: "cloud.device.test.\(UUID().uuidString)")!
        let first = CloudDeviceIdentity.current(in: defaults)
        let second = CloudDeviceIdentity.current(in: defaults)
        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test("Different stores mint different device identities")
    func deviceIdentityDistinct() {
        let a = UserDefaults(suiteName: "cloud.device.test.\(UUID().uuidString)")!
        let b = UserDefaults(suiteName: "cloud.device.test.\(UUID().uuidString)")!
        #expect(CloudDeviceIdentity.current(in: a) != CloudDeviceIdentity.current(in: b))
    }
}
