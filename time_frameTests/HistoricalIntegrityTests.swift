//
//  HistoricalIntegrityTests.swift
//  time_frameTests (Milestone 13)
//
//  Historical records stay semantically frozen when other rows change — the
//  property that keeps History honest whether an edit is local or arrives via
//  CloudKit sync (ADR-063). Renaming a configuration, or deleting a plan/template,
//  never rewrites a session's frozen fields or deletes its history.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Historical integrity under edits")
struct HistoricalIntegrityTests {

    @Test("Renaming a configuration never rewrites a session's frozen name or timestamps")
    func renameDoesNotRewriteHistory() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, name: "Original")
        let clock = MockTimeSource()
        let coord = makeCoordinator(container, clock: clock)

        let session = try #require(try coord.startSession(configuration: config))
        let frozenName = session.configurationName
        let startedAt = session.startedAt
        #expect(frozenName == "Original")

        // Rename the live configuration.
        config.name = "Renamed"
        config.modifiedAt = Date()
        try container.mainContext.save()

        #expect(session.configurationName == "Original")          // frozen name unchanged
        #expect(session.displayConfigurationName == "Original")   // display still historical
        #expect(session.startedAt == startedAt)                   // timestamp untouched
    }

    @Test("Deleting a plan cascades to its items but never to session history")
    func planDeletionKeepsHistory() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let clock = MockTimeSource()
        let coord = makeCoordinator(container, clock: clock)

        let planRepo = makePlanRepository(container)
        let plan = try planRepo.create(simplePlanDraft(config))
        // Start a real session from the plan, then stop it so it is history.
        let session = try #require(try coord.startPlan(plan.executionSnapshot))
        try coord.stop()
        let sessionID = session.id

        try planRepo.delete(plan)

        #expect(try planRepo.all().isEmpty)                                   // plan gone
        #expect(try container.mainContext.fetch(FetchDescriptor<SessionPlanItem>()).isEmpty) // items cascaded
        let sessions = try makeSessionRepository(container).allSessions()
        #expect(sessions.contains { $0.id == sessionID })                    // history survives
    }

    @Test("Deleting a template never deletes a session it seeded")
    func templateDeletionKeepsHistory() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let clock = MockTimeSource()
        let coord = makeCoordinator(container, clock: clock)

        let template = try insertTemplate(container, configuration: config)
        // A session started "from" the template runs through the normal path.
        let session = try #require(try coord.startSession(configuration: config, taskName: template.taskName))
        try coord.stop()
        let sessionID = session.id

        try makeTemplateRepository(container).delete(template)

        #expect(try makeTemplateRepository(container).all().isEmpty)
        let sessions = try makeSessionRepository(container).allSessions()
        #expect(sessions.contains { $0.id == sessionID })
    }
}
