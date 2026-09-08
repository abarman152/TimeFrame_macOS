//
//  OnDiskRelaunchTests.swift
//  time_frameTests
//
//  Verifies session recovery across a *real* on-disk store: a session persisted
//  by one container is restored by a second, independent container opened over
//  the same file — the closest deterministic analogue of an app relaunch.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("On-disk relaunch")
struct OnDiskRelaunchTests {

    private func makeDiskContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
        return try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: TimeFrameMigrationPlan.self,
            configurations: [configuration]
        )
    }

    @Test("A running session survives a real store close/reopen")
    func survivesRelaunch() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tf-test-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + suffix)
                )
            }
        }

        let clockA = MockTimeSource()
        var startedID: UUID?

        // Launch 1: create + start a session, then let the container go away.
        do {
            let containerA = try makeDiskContainer(at: url)
            let config = PomodoroConfiguration(
                name: "Disk", focusDuration: 10, shortBreakDuration: 5,
                longBreakDuration: 15, sessionsBeforeLongBreak: 4, defaultTotalSessions: 4
            )
            containerA.mainContext.insert(config)
            try containerA.mainContext.save()

            let coordA = SessionCoordinator(context: containerA.mainContext, timeSource: clockA, autoTick: false)
            let session = try #require(try coordA.startSession(configuration: config, taskName: "Disk"))
            startedID = session.id
            clockA.advance(by: 3)
        }

        // Launch 2: a brand-new container over the same file restores the session.
        let clockB = MockTimeSource()
        clockB.set(to: clockA.now())
        let containerB = try makeDiskContainer(at: url)
        let coordB = SessionCoordinator(context: containerB.mainContext, timeSource: clockB, autoTick: false)

        let restored = try coordB.recover()

        #expect(restored)
        #expect(coordB.engine.state == .running)
        #expect(coordB.activeSession?.id == startedID)
        expectClose(coordB.engine.remaining, 7) // 10 − 3
        #expect(try makeSessionRepository(containerB).allSessions().count == 1)
    }
}
