//
//  PersistenceTests.swift
//  time_frameTests
//
//  Verifies the SwiftData container initializes and the model relationships /
//  delete rules behave as designed. Uses an in-memory store.
//
//  NOTE: each test keeps its `ModelContainer` alive for the whole test body.
//  A `ModelContext` does not keep its container alive, so letting the container
//  deallocate while the context is still in use is a use-after-free that traps
//  inside SwiftData.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Persistence")
struct PersistenceTests {

    @Test("The container initializes from the versioned schema")
    func containerInitializes() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<PomodoroConfiguration>()) == 0)
    }

    @Test("A configuration can be inserted and fetched")
    func insertConfiguration() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(PomodoroConfiguration.classic())
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PomodoroConfiguration>()) == 1)
    }

    @Test("A session references its configuration and owns its intervals")
    func sessionRelationships() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let config = PomodoroConfiguration.classic()
        let session = FocusSession(taskName: "Write docs", configuration: config, status: .running)
        let plan = IntervalPlan(configuration: config.snapshot)
        for planned in plan.intervals {
            session.intervals.append(SessionInterval(planned: planned))
        }
        context.insert(session)
        try context.save()

        #expect(session.configuration?.id == config.id)
        #expect(session.intervals.count == plan.count)
        #expect(config.focusSessions.contains { $0.id == session.id })
        #expect(session.orderedIntervals.first?.phase == .focus)
    }

    @Test("Deleting a session cascades to its intervals")
    func deleteCascades() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let session = FocusSession(taskName: "Cascade", status: .running)
        session.intervals.append(SessionInterval(phase: .focus, plannedDuration: 10, order: 0))
        session.intervals.append(SessionInterval(phase: .shortBreak, plannedDuration: 5, order: 1))
        context.insert(session)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<SessionInterval>()) == 2)

        context.delete(session)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<SessionInterval>()) == 0)
    }

    @Test("Deleting a configuration nullifies its sessions but keeps them")
    func deleteNullifies() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let config = PomodoroConfiguration.classic()
        let session = FocusSession(taskName: "Keep me", configuration: config, status: .completed)
        context.insert(session)
        try context.save()

        context.delete(config)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<FocusSession>()) == 1)
        let fetched = try context.fetch(FetchDescriptor<FocusSession>()).first
        #expect(fetched?.configuration == nil)
    }
}
