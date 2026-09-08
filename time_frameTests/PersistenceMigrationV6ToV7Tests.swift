//
//  PersistenceMigrationV6ToV7Tests.swift
//  time_frameTests (Milestone 31)
//
//  The test that should have existed before schema V7 shipped.
//
//  Each case writes a **genuine V6 store** with the frozen V6 models (`SchemaV6Fixture`),
//  closes it, and reopens the same file with the production schema through the app's own
//  `PersistenceController.openOnDiskContainer`. Then it checks the rows are still there,
//  with their identities, values and relationships.
//
//  Until Milestone 31 no test could do this, because the app keeps no frozen per-version
//  models: `TimeFrameSchemaV6.models` and `TimeFrameSchemaV7.models` return the *same*
//  current classes, so nothing in the codebase could write a V6 store. "An existing V6
//  store opens in place" was a comment in the schema file — believed, but never executed.
//
//  ## Structure, learned the hard way
//  Every case follows the same shape, and it is not stylistic:
//
//   • the V6 container lives inside an explicit `do { }` so it is fully released before the
//     V7 container opens the same file;
//   • every `try` is evaluated into a local **outside** the `#expect` macros;
//   • the V7 container is bound to a local and kept alive for the whole case — a
//     `ModelContext` does not retain its `ModelContainer` (CLAUDE.md testing rules), and
//     letting it deallocate mid-test faults inside SwiftData;
//   • no case deletes its store directory while a container may still be tearing down.
//
//  Departing from any of these produced a `SIGTRAP` inside SwiftData that presents as a
//  migration failure and is nothing of the kind. Stores go to fresh temporary
//  subdirectories, which the OS reclaims.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Persistence: V6 → V7 migration")
struct PersistenceMigrationV6ToV7Tests {

    /// A fresh temporary store path. Never the production store — `SchemaV6Fixture.container`
    /// asserts that independently.
    private func url() -> URL {
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent("tf-v6-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("default.store")
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        return u
    }

    /// The V6 configuration every case starts from is built inline, deliberately **not**
    /// from the seeded defaults, so a store that had been reset and reseeded could never
    /// pass these assertions.

    // MARK: Tests

    @Test("A realistic V6 library keeps every row when opened with the current schema")
    func realisticLibrarySurvives() throws {
        let u = url()
        let configID = UUID()
        do {
            let c = try SchemaV6Fixture.container(at: u)
            let ctx = c.mainContext
            let cfg = SchemaV6Fixture.PomodoroConfiguration(
                id: configID, name: "PF45",
                focusDuration: 45 * 60, shortBreakDuration: 5 * 60, longBreakDuration: 15 * 60,
                sessionsBeforeLongBreak: 4, defaultTotalSessions: 4, isDefault: true)
            ctx.insert(cfg)
            for name in ["Deep Focus", "Research"] {
                ctx.insert(SchemaV6Fixture.TaskTemplate(
                    name: name, taskName: "Write the design document",
                    configuration: cfg, defaultTotalSessions: 4))
            }
            let plan = SchemaV6Fixture.SessionPlan(name: "Research Plan",
                                                   taskName: "Literature review")
            ctx.insert(plan)
            plan.items = (0..<3).map { i in
                SchemaV6Fixture.SessionPlanItem(
                    order: i, phase: i.isMultiple(of: 2) ? .focus : .shortBreak,
                    duration: i.isMultiple(of: 2) ? 45 * 60 : 5 * 60,
                    configuration: cfg, configurationName: "PF45")
            }
            for _ in 0..<3 {
                let s = SchemaV6Fixture.FocusSession(
                    taskName: "Write the design document", configuration: cfg,
                    configurationName: "PF45", status: .completed)
                ctx.insert(s)
                s.intervals = [
                    SchemaV6Fixture.SessionInterval(phase: .focus, plannedDuration: 45 * 60,
                                                    order: 0, status: .completed,
                                                    configurationName: "PF45"),
                    SchemaV6Fixture.SessionInterval(phase: .shortBreak, plannedDuration: 5 * 60,
                                                    order: 1, status: .completed,
                                                    configurationName: "PF45")
                ]
            }
            try ctx.save()
        }

        // The container is bound to a local and kept alive for the whole test: a
        // `ModelContext` does not retain its `ModelContainer`, and letting the container
        // deallocate mid-test faults inside SwiftData (CLAUDE.md testing rules).
        let container = try PersistenceController.openOnDiskContainer(
            schema: PersistenceController.schema,
            configuration: ModelConfiguration(schema: PersistenceController.schema, url: u))
        let ctx = container.mainContext
        let configs = try ctx.fetch(FetchDescriptor<PomodoroConfiguration>())
        let templates = try ctx.fetch(FetchDescriptor<TaskTemplate>())
        let plans = try ctx.fetch(FetchDescriptor<SessionPlan>())
        let items = try ctx.fetch(FetchDescriptor<SessionPlanItem>())
        let sessions = try ctx.fetch(FetchDescriptor<FocusSession>())
        let intervals = try ctx.fetch(FetchDescriptor<SessionInterval>())

        // Nothing dropped.
        #expect(configs.count == 1)
        #expect(templates.count == 2)
        #expect(plans.count == 1)
        #expect(items.count == 3)
        #expect(sessions.count == 3)
        #expect(intervals.count == 6)

        // The configuration is the same row with its own numbers, not a reseeded default.
        #expect(configs.first?.id == configID)
        #expect(configs.first?.name == "PF45")
        // Explicit `Double` literals: an integer literal inside `#expect` is inferred
        // independently of the left-hand side and compares unequal to the stored
        // `TimeInterval`, which looks like a data-loss failure and is not one.
        #expect(configs.first?.focusDuration == 2700.0)
        #expect(configs.first?.shortBreakDuration == 300.0)
        #expect(configs.first?.longBreakDuration == 900.0)
        #expect(configs.first?.defaultTotalSessions == 4)
        #expect(configs.first?.isDefault == true)

        // History kept its status, its frozen configuration name and its intervals.
        #expect(sessions.allSatisfy { $0.status == .completed })
        #expect(sessions.allSatisfy { $0.configurationName == "PF45" })
        #expect(sessions.allSatisfy { $0.orderedIntervals.map(\.phase) == [.focus, .shortBreak] })
    }

    @Test("A template keeps its identity, values and link to the configuration")
    func templateSurvives() throws {
        let u = url()
        let templateID = UUID()
        let configID = UUID()
        do {
            let c = try SchemaV6Fixture.container(at: u)
            let cfg = SchemaV6Fixture.PomodoroConfiguration(
                id: configID, name: "PF45",
                focusDuration: 45 * 60, shortBreakDuration: 5 * 60, longBreakDuration: 15 * 60,
                sessionsBeforeLongBreak: 4, defaultTotalSessions: 4, isDefault: true)
            c.mainContext.insert(cfg)
            c.mainContext.insert(SchemaV6Fixture.TaskTemplate(
                id: templateID, name: "Deep Focus", taskName: "Write the design document",
                configuration: cfg, defaultTotalSessions: 4, isDefault: true))
            try c.mainContext.save()
        }

        // The container is bound to a local and kept alive for the whole test: a
        // `ModelContext` does not retain its `ModelContainer`, and letting the container
        // deallocate mid-test faults inside SwiftData (CLAUDE.md testing rules).
        let container = try PersistenceController.openOnDiskContainer(
            schema: PersistenceController.schema,
            configuration: ModelConfiguration(schema: PersistenceController.schema, url: u))
        let ctx = container.mainContext
        let templates = try ctx.fetch(FetchDescriptor<TaskTemplate>())

        #expect(templates.first?.id == templateID)
        #expect(templates.first?.name == "Deep Focus")
        #expect(templates.first?.taskName == "Write the design document")
        #expect(templates.first?.defaultTotalSessions == 4)
        #expect(templates.first?.isDefault == true)
        #expect(templates.first?.configuration?.id == configID)
    }

    @Test("A plan keeps its ordered timeline and each item's configuration reference")
    func planTimelineSurvives() throws {
        let u = url()
        let planID = UUID()
        let configID = UUID()
        do {
            let c = try SchemaV6Fixture.container(at: u)
            let cfg = SchemaV6Fixture.PomodoroConfiguration(
                id: configID, name: "PF45",
                focusDuration: 45 * 60, shortBreakDuration: 5 * 60, longBreakDuration: 15 * 60,
                sessionsBeforeLongBreak: 4, defaultTotalSessions: 4, isDefault: true)
            c.mainContext.insert(cfg)
            let plan = SchemaV6Fixture.SessionPlan(id: planID, name: "Research Plan",
                                                   taskName: "Literature review")
            c.mainContext.insert(plan)
            plan.items = (0..<3).map { i in
                SchemaV6Fixture.SessionPlanItem(
                    order: i, phase: i.isMultiple(of: 2) ? .focus : .shortBreak,
                    duration: i.isMultiple(of: 2) ? 45 * 60 : 5 * 60,
                    configuration: cfg, configurationName: "PF45")
            }
            try c.mainContext.save()
        }

        // The container is bound to a local and kept alive for the whole test: a
        // `ModelContext` does not retain its `ModelContainer`, and letting the container
        // deallocate mid-test faults inside SwiftData (CLAUDE.md testing rules).
        let container = try PersistenceController.openOnDiskContainer(
            schema: PersistenceController.schema,
            configuration: ModelConfiguration(schema: PersistenceController.schema, url: u))
        let ctx = container.mainContext
        let plans = try ctx.fetch(FetchDescriptor<SessionPlan>())
        let ordered = plans.first?.orderedItems ?? []

        #expect(plans.first?.id == planID)
        #expect(plans.first?.name == "Research Plan")
        #expect(plans.first?.taskName == "Literature review")
        #expect(ordered.map(\.order) == [0, 1, 2])
        #expect(ordered.map(\.phase) == [.focus, .shortBreak, .focus])
        #expect(ordered.map(\.duration) == [2700.0, 300.0, 2700.0])
        #expect(ordered.allSatisfy { $0.configuration?.id == configID })
        #expect(ordered.allSatisfy { $0.configurationName == "PF45" })
    }

    @Test("The attributes V7 added read as their defaults on rows that predate them")
    func newAttributesTakeDefaults() throws {
        let u = url()
        do {
            let c = try SchemaV6Fixture.container(at: u)
            let cfg = SchemaV6Fixture.PomodoroConfiguration(
                id: UUID(), name: "PF45",
                focusDuration: 45 * 60, shortBreakDuration: 5 * 60, longBreakDuration: 15 * 60,
                sessionsBeforeLongBreak: 4, defaultTotalSessions: 4, isDefault: true)
            c.mainContext.insert(cfg)
            c.mainContext.insert(SchemaV6Fixture.TaskTemplate(
                name: "Deep Focus", taskName: "Write", configuration: cfg,
                defaultTotalSessions: 4))
            c.mainContext.insert(SchemaV6Fixture.SessionPlan(name: "Research Plan",
                                                             taskName: "Lit review"))
            try c.mainContext.save()
        }

        // The container is bound to a local and kept alive for the whole test: a
        // `ModelContext` does not retain its `ModelContainer`, and letting the container
        // deallocate mid-test faults inside SwiftData (CLAUDE.md testing rules).
        let container = try PersistenceController.openOnDiskContainer(
            schema: PersistenceController.schema,
            configuration: ModelConfiguration(schema: PersistenceController.schema, url: u))
        let ctx = container.mainContext
        let templates = try ctx.fetch(FetchDescriptor<TaskTemplate>())
        let plans = try ctx.fetch(FetchDescriptor<SessionPlan>())

        // A V6 row had no pin and no icon column at all. After migration it must read as
        // "not pinned, default icon" — and still be its own row, with its own name. These
        // are exactly the reads a Templates row performs the instant it is drawn, so a
        // migration that left them unset would fault the app on the first render.
        #expect(templates.first?.isPinned == false)
        #expect(templates.first?.pinnedAt == nil)
        #expect(templates.first?.iconIdentifier == TimeFrameIconIdentifier.templateDefault.rawValue)
        #expect(templates.first?.icon == .templateDefault)
        #expect(templates.first?.name == "Deep Focus")

        #expect(plans.first?.isPinned == false)
        #expect(plans.first?.pinnedAt == nil)
        #expect(plans.first?.icon == .planDefault)
        #expect(plans.first?.name == "Research Plan")
    }

    @Test("The migrated store is writable: a V7-only pin persists across a reopen")
    func migratedStoreIsWritable() throws {
        let u = url()
        let pinnedAt = Date(timeIntervalSince1970: 1_760_000_000)
        do {
            let c = try SchemaV6Fixture.container(at: u)
            let cfg = SchemaV6Fixture.PomodoroConfiguration(
                id: UUID(), name: "PF45",
                focusDuration: 45 * 60, shortBreakDuration: 5 * 60, longBreakDuration: 15 * 60,
                sessionsBeforeLongBreak: 4, defaultTotalSessions: 4, isDefault: true)
            c.mainContext.insert(cfg)
            c.mainContext.insert(SchemaV6Fixture.TaskTemplate(
                name: "Deep Focus", taskName: "Write", configuration: cfg,
                defaultTotalSessions: 4))
            try c.mainContext.save()
        }

        do {
            // The container is bound to a local and kept alive for the whole test: a
        // `ModelContext` does not retain its `ModelContainer`, and letting the container
        // deallocate mid-test faults inside SwiftData (CLAUDE.md testing rules).
        let container = try PersistenceController.openOnDiskContainer(
            schema: PersistenceController.schema,
            configuration: ModelConfiguration(schema: PersistenceController.schema, url: u))
        let ctx = container.mainContext
            let templates = try ctx.fetch(FetchDescriptor<TaskTemplate>())
            templates.first?.isPinned = true
            templates.first?.pinnedAt = pinnedAt
            try ctx.save()
        }

        // The container is bound to a local and kept alive for the whole test: a
        // `ModelContext` does not retain its `ModelContainer`, and letting the container
        // deallocate mid-test faults inside SwiftData (CLAUDE.md testing rules).
        let container = try PersistenceController.openOnDiskContainer(
            schema: PersistenceController.schema,
            configuration: ModelConfiguration(schema: PersistenceController.schema, url: u))
        let ctx = container.mainContext
        let templates = try ctx.fetch(FetchDescriptor<TaskTemplate>())

        #expect(templates.first?.isPinned == true)
        #expect(templates.first?.pinnedAt == pinnedAt)
        // ...and the V6 values are still beside the new one, not replaced by the write.
        #expect(templates.first?.name == "Deep Focus")
        #expect(templates.first?.taskName == "Write")
    }
}
