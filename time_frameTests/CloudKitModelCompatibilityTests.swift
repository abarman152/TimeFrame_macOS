//
//  CloudKitModelCompatibilityTests.swift
//  time_frameTests (Milestone 13)
//
//  Guards the CloudKit constraints on the V6 schema: no uniqueness constraints
//  (CloudKit rejects them), the full model set is present, and every model still
//  round-trips through a container. Deterministic and offline.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("CloudKit model compatibility")
struct CloudKitModelCompatibilityTests {

    @Test("The V6 schema contains all six models")
    func modelSet() {
        let schema = Schema(versionedSchema: TimeFrameSchemaV6.self)
        let names = Set(schema.entities.map(\.name))
        for expected in [
            "PomodoroConfiguration", "FocusSession", "SessionInterval",
            "TaskTemplate", "SessionPlan", "SessionPlanItem"
        ] {
            #expect(names.contains(expected))
        }
    }

    @Test("No model declares a uniqueness constraint (CloudKit-incompatible)")
    func noUniquenessConstraints() {
        let schema = Schema(versionedSchema: TimeFrameSchemaV6.self)
        for entity in schema.entities {
            #expect(entity.uniquenessConstraints.isEmpty,
                    "\(entity.name) must not declare a uniqueness constraint under CloudKit")
        }
    }

    @Test("The latest schema is V7, built on the V6 CloudKit-compatibility baseline")
    func latestIsV7() {
        #expect(TimeFrameSchemaLatest.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(TimeFrameSchemaV7.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(TimeFrameSchemaV6.versionIdentifier == Schema.Version(6, 0, 0))
        // V7 adds attributes only: the six-model set from V6 is unchanged.
        #expect(Schema(versionedSchema: TimeFrameSchemaV7.self).entities.count
                == Schema(versionedSchema: TimeFrameSchemaV6.self).entities.count)
    }

    @Test("Every model round-trips through the container")
    func roundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let config = PomodoroConfiguration(name: "Compat")
        context.insert(config)
        let template = TaskTemplate(name: "T", taskName: "Task", configuration: config)
        context.insert(template)
        let plan = SessionPlan(name: "P", taskName: "Task")
        let item = SessionPlanItem(order: 0, phase: .focus, duration: 60, configuration: config)
        plan.items.append(item)
        context.insert(plan)
        let session = FocusSession(taskName: "Task", configuration: config, status: .completed)
        session.intervals.append(SessionInterval(phase: .focus, plannedDuration: 60, order: 0))
        context.insert(session)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<PomodoroConfiguration>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TaskTemplate>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SessionPlan>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SessionPlanItem>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FocusSession>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SessionInterval>()).count == 1)
    }

    @Test("Cascade and nullify relationships survive round-trip")
    func relationships() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let config = PomodoroConfiguration(name: "Rel")
        context.insert(config)
        let plan = SessionPlan(name: "P", taskName: "Task")
        plan.items.append(SessionPlanItem(order: 0, phase: .focus, duration: 60, configuration: config))
        context.insert(plan)
        try context.save()

        // Cascade: deleting the plan removes its item…
        context.delete(plan)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SessionPlanItem>()).isEmpty)
        // …but never the configuration it referenced (nullify side).
        #expect(try context.fetch(FetchDescriptor<PomodoroConfiguration>()).count == 1)
    }
}
