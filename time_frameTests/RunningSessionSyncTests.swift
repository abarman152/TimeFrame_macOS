//
//  RunningSessionSyncTests.swift
//  time_frameTests (Milestone 13)
//
//  The running-session cross-device policy (ADR-063): timer execution is
//  device-local. A running/paused session synced from another device must NOT be
//  recovered into a second live timer here, and must NOT be mutated (which would
//  sync back and stop the device that owns it). Modelled by stamping a foreign
//  originating device onto a persisted session — no real CloudKit or second device.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Running session cross-device policy")
struct RunningSessionSyncTests {

    // MARK: belongsToDevice

    @Test("A session with no origin is treated as local (back-compat)")
    func legacyOriginIsLocal() {
        let session = FocusSession(taskName: "x")
        session.originatingDeviceID = nil
        #expect(session.belongsToDevice("anything"))
    }

    @Test("A session belongs only to its originating device")
    func originMatching() {
        let session = FocusSession(taskName: "x")
        session.originatingDeviceID = "device-A"
        #expect(session.belongsToDevice("device-A"))
        #expect(!session.belongsToDevice("device-B"))
    }

    // MARK: Coordinator recovery does not take over a foreign running session

    @Test("Device B does not start a second timer from a synced running session")
    func deviceBDoesNotTakeOver() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container) // focus 10
        let clockA = MockTimeSource()
        let coordA = makeCoordinator(container, clock: clockA)

        // Device A starts a real, recoverable running session…
        let session = try #require(try coordA.startSession(configuration: config))
        // …which then syncs to "device B" — model that by re-stamping its origin.
        session.originatingDeviceID = "device-A-remote"
        try container.mainContext.save()

        // Device B relaunches over the same (synced) store.
        let clockB = MockTimeSource()
        clockB.set(to: clockA.now())
        let coordB = makeCoordinator(container, clock: clockB)
        let restored = try coordB.recover()

        // No takeover: no restore, no second live timer, no active session here.
        #expect(restored == false)
        #expect(coordB.engine.state == .idle)
        #expect(coordB.activeSession == nil)
        // And the synced session is left exactly as Device A owns it — NOT interrupted.
        #expect(session.status == .running)
    }

    @Test("A device still recovers a session it started")
    func ownDeviceRecovers() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let clock = MockTimeSource()
        let coord = makeCoordinator(container, clock: clock)
        let started = try #require(try coord.startSession(configuration: config))

        // Same device (the coordinator's repository) relaunches.
        let clockB = MockTimeSource()
        clockB.set(to: clock.now())
        let coordB = makeCoordinator(container, clock: clockB)
        #expect(try coordB.recover())
        #expect(coordB.activeSession?.id == started.id)
    }

    // MARK: Repository-level gating leaves the foreign session untouched

    @Test("fetchRecoverableSession is device-scoped and non-destructive")
    func repositoryDeviceScope() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let clock = MockTimeSource()
        let coord = makeCoordinator(container, clock: clock)
        let session = try #require(try coord.startSession(configuration: config))
        session.originatingDeviceID = "device-A"
        try container.mainContext.save()

        // Device B sees nothing to recover, and does not mutate the row.
        let repoB = SessionRepository(context: container.mainContext, deviceID: "device-B")
        #expect(try repoB.fetchRecoverableSession() == nil)
        #expect(session.status == .running)

        // Device A recovers its own session.
        let repoA = SessionRepository(context: container.mainContext, deviceID: "device-A")
        #expect(try repoA.fetchRecoverableSession()?.id == session.id)
    }
}
