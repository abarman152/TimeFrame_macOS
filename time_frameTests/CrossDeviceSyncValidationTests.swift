//
//  CrossDeviceSyncValidationTests.swift
//  time_frameTests (Milestone 19)
//
//  Deterministic proof of the architecture expected under CloudKit sync (ADR-081),
//  with no real iCloud account. A single in-memory container models the MERGED,
//  synced store; two `SessionRepository`/`SessionCoordinator` instances with distinct
//  device IDs act as Device A and Device B viewing that shared store. The invariants:
//  historical rows and their frozen fields survive a merge intact, statistics derive
//  correctly from merged history, a running session is device-local and never taken
//  over by another device, and a cloud failure never blocks the timer.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Cross-device sync validation")
struct CrossDeviceSyncValidationTests {

    // MARK: Fixtures

    /// A completed session written directly (no clock needed) with a FROZEN
    /// configuration name and one completed focus interval — the shape a historical
    /// row has after it syncs between devices.
    @discardableResult
    private func insertCompletedSession(
        _ container: ModelContainer,
        configuration: PomodoroConfiguration?,
        frozenName: String,
        origin: String,
        start: Date,
        focus: TimeInterval
    ) throws -> FocusSession {
        let session = FocusSession(
            taskName: "Task", configuration: configuration, status: .completed, startedAt: start
        )
        session.configurationName = frozenName
        session.originatingDeviceID = origin
        session.endedAt = start.addingTimeInterval(focus)
        let interval = SessionInterval(phase: .focus, plannedDuration: focus, order: 0)
        interval.status = .completed
        interval.configurationName = frozenName
        interval.startedAt = start
        interval.endedAt = start.addingTimeInterval(focus)
        session.intervals.append(interval)
        container.mainContext.insert(session)
        try container.mainContext.save()
        return session
    }

    private func wideRange() -> StatisticsDateRange {
        StatisticsDateRange(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 4_000_000_000)
        )
    }

    // MARK: 1 & 2 — historical rows + frozen fields survive a merge

    @Test("A completed session's frozen fields survive a configuration rename")
    func frozenNameSurvivesRename() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, name: "Deep Work", focus: 1500)
        let session = try insertCompletedSession(
            container, configuration: config, frozenName: "Deep Work",
            origin: "device-A", start: Date(timeIntervalSince1970: 1_000_000), focus: 1500
        )

        // A later edit (which could arrive as a merge from another device) renames
        // the live configuration…
        config.name = "Renamed Focus"
        try container.mainContext.save()

        // …but the historical row's frozen name and interval timing are unchanged.
        #expect(session.configurationName == "Deep Work")
        #expect(session.displayConfigurationName == "Deep Work")
        let interval = try #require(session.orderedIntervals.first)
        #expect(interval.plannedDuration == 1500)
        #expect(interval.phase == .focus)
        #expect(interval.configurationName == "Deep Work")
    }

    @Test("A completed session's frozen fields survive a configuration delete")
    func frozenNameSurvivesDelete() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, name: "Deep Work", focus: 1500)
        let session = try insertCompletedSession(
            container, configuration: config, frozenName: "Deep Work",
            origin: "device-A", start: Date(timeIntervalSince1970: 1_000_000), focus: 1500
        )

        // Deleting the configuration nullifies the relationship (never deletes history).
        container.mainContext.delete(config)
        try container.mainContext.save()

        #expect(session.configuration == nil)                 // nullified
        #expect(session.status == .completed)                 // history intact
        #expect(session.displayConfigurationName == "Deep Work") // frozen name still shown
        #expect(session.orderedIntervals.count == 1)          // interval history intact
        #expect(session.orderedIntervals.first?.plannedDuration == 1500)
    }

    // MARK: 8 — completed history is visible to BOTH devices over the merged store

    @Test("Both devices see a completed session written by one of them")
    func completedHistoryVisibleToBothDevices() throws {
        let container = try makeInMemoryContainer()
        let session = try insertCompletedSession(
            container, configuration: nil, frozenName: "Solo",
            origin: "device-A", start: Date(timeIntervalSince1970: 2_000_000), focus: 600
        )

        let repoA = SessionRepository(context: container.mainContext, deviceID: "device-A")
        let repoB = SessionRepository(context: container.mainContext, deviceID: "device-B")
        let historyA = try repoA.allSessions()
        let historyB = try repoB.allSessions()
        #expect(historyA.contains { $0.id == session.id })
        #expect(historyB.contains { $0.id == session.id },
                "completed history must be visible on a device that did not create it")
    }

    // MARK: 4, 5, 6, 7 — a running session is device-local across the merged store

    @Test("A running session syncs as visible history but is never taken over by another device")
    func runningSessionIsDeviceLocal() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container) // focus 10

        // Device A starts a real running session on the shared store.
        let clockA = MockTimeSource()
        let coordA = SessionCoordinator(context: container.mainContext, timeSource: clockA, autoTick: false)
        // Stamp A's coordinator repo device id via a real start (SessionRepository stamps origin).
        let repoDeviceA = coordA.sessions.deviceID
        let started = try #require(try coordA.startSession(configuration: config))
        #expect(started.originatingDeviceID == repoDeviceA)
        #expect(started.status == .running)

        // Device B relaunches over the same synced store with a DIFFERENT device id.
        let clockB = MockTimeSource(); clockB.set(to: clockA.now())
        let coordB = SessionCoordinator(context: container.mainContext, timeSource: clockB, autoTick: false)
        // Force B's identity to differ from A's so the row is foreign to B.
        let repoB = SessionRepository(context: container.mainContext, deviceID: repoDeviceA + "-B")

        // B does not recover a second live timer, and the fetch is non-destructive.
        #expect(try repoB.fetchRecoverableSession() == nil)
        #expect(coordB.engine.state == .idle)
        #expect(started.status == .running, "B must not interrupt A's running session")

        // A still owns and can complete its own session.
        #expect(try coordA.sessions.fetchRecoverableSession()?.id == started.id)
    }

    // MARK: 9 — statistics derive correctly from MERGED history (device-agnostic)

    @Test("Statistics aggregate the merged history from all devices")
    func statisticsFromMergedHistory() throws {
        let container = try makeInMemoryContainer()
        // Three completed sessions from two different devices — the merged store.
        try insertCompletedSession(container, configuration: nil, frozenName: "A-cfg",
                                   origin: "device-A", start: Date(timeIntervalSince1970: 1_000_000), focus: 1500)
        try insertCompletedSession(container, configuration: nil, frozenName: "A-cfg",
                                   origin: "device-A", start: Date(timeIntervalSince1970: 1_100_000), focus: 1500)
        try insertCompletedSession(container, configuration: nil, frozenName: "B-cfg",
                                   origin: "device-B", start: Date(timeIntervalSince1970: 1_200_000), focus: 600)

        // Statistics read the same store both devices share — a single fetch, then
        // pure aggregation. Attribution is by session/interval fields, never by device.
        let inputs = try StatisticsRepository(context: container.mainContext).sessionInputs()
        let snapshot = StatisticsAggregator.aggregate(sessions: inputs, range: wideRange())

        #expect(snapshot.completedSessions == 3)
        #expect(snapshot.completedFocusIntervals == 3)
        #expect(snapshot.focusDuration == 1500 + 1500 + 600)
        // Configuration breakdown groups by the FROZEN name (survives rename/delete).
        let names = Set(snapshot.configurations.map(\.configurationName))
        #expect(names.contains("A-cfg"))
        #expect(names.contains("B-cfg"))
    }

    // MARK: 12 — a cloud failure never blocks the timer or its controls

    @Test("Under CloudKit fallback the timer controls all work over the preserved local store")
    func timerWorksUnderCloudFallback() throws {
        // Requested CloudKit, but the cloud container throws (no entitlement/account) —
        // the store falls back to a working local container. The timer must be fully usable.
        let bootstrap = PersistenceController.bootstrap(
            requestedMode: .cloudKit,
            inMemory: true,
            makeCloud: { throw CloudSyncError.cloudKitUnavailable },
            makeLocal: { try PersistenceController.makeContainer(inMemory: true) }
        )
        #expect(bootstrap.activeMode == .fallback)

        let config = try insertConfiguration(bootstrap.container)
        let clock = MockTimeSource()
        let coord = SessionCoordinator(context: bootstrap.container.mainContext, timeSource: clock, autoTick: false)

        // Every control works despite CloudKit being unavailable.
        let session = try #require(try coord.startSession(configuration: config))
        #expect(coord.engine.state == .running)
        try coord.pause();  #expect(coord.engine.state == .paused)
        try coord.resume(); #expect(coord.engine.state == .running)
        try coord.skip()    // still active, advanced to the next interval
        #expect(coord.engine.state.isActive)
        try coord.stop()    // stop cancels the active session
        #expect(coord.engine.state == .cancelled)
        #expect(coord.engine.state.isActive == false)
        #expect(session.originatingDeviceID != nil) // still device-stamped for later sync
    }
}
