//
//  OfflinePersistenceTests.swift
//  time_frameTests (Milestone 13)
//
//  With CloudKit unavailable, the whole app must keep working on the local store.
//  An in-memory container has no CloudKit mirroring, so it *is* the "iCloud
//  unavailable" case: create data, run a session, read history and statistics —
//  everything succeeds, fully offline and deterministic.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Offline persistence (CloudKit unavailable)")
struct OfflinePersistenceTests {

    @Test("Configurations, templates and plans are created offline")
    func createEntitiesOffline() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, name: "Deep Work")

        try insertTemplate(container, configuration: config)
        let planRepo = makePlanRepository(container)
        try planRepo.create(simplePlanDraft(config))

        #expect(try makeTemplateRepository(container).all().count == 1)
        #expect(try planRepo.all().count == 1)
    }

    @Test("A session runs, stops, and is recorded to local history offline")
    func runSessionOffline() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container) // focus 10
        let clock = MockTimeSource()
        let coord = makeCoordinator(container, clock: clock)

        _ = try coord.startSession(configuration: config, taskName: "Write")
        clock.advance(by: 4)
        try coord.tick()
        try coord.stop()

        let sessions = try makeSessionRepository(container).allSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.status == .cancelled)
        #expect(sessions.first?.taskName == "Write")
        // History freezes the configuration name even with no network.
        #expect(sessions.first?.displayConfigurationName == config.name)
    }

    @Test("Statistics project from local history offline")
    func statisticsOffline() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, total: 1) // [focus 10, short 5]
        let clock = MockTimeSource()
        let coord = makeCoordinator(container, clock: clock)

        _ = try coord.startSession(configuration: config)
        clock.advance(by: 200) // elapse the whole plan
        try coord.tick()

        let inputs = try StatisticsRepository(context: container.mainContext).sessionInputs()
        #expect(!inputs.isEmpty)
        let allTime = StatisticsPeriod.custom(start: .distantPast, end: .distantFuture)
        let snapshot = StatisticsAggregator.aggregate(sessions: inputs, range: allTime.range())
        #expect(snapshot.completedSessions >= 1)
    }
}
