//
//  PersistenceV6FixtureModels.swift
//  time_frameTests (Milestone 31)
//
//  Frozen copies of the Milestone-27 (schema **V6**) `@Model` types.
//
//  ## Why these exist
//  The app keeps no frozen per-version model definitions: every `TimeFrameSchemaV1…V7`
//  returns the *current* Swift classes, so `TimeFrameSchemaV6.models` and
//  `TimeFrameSchemaV7.models` are byte-for-byte the same schema at runtime. The version
//  numbers were labels, not shapes.
//
//  That is why "V6 → V7 migrates cleanly" could never be tested before: there was nothing
//  in the codebase that could *write* a V6 store. The migration was asserted in a comment
//  and believed. It was wrong, and a real user's history paid for it.
//
//  These types are the missing half. They are the V6 shapes exactly — the current models
//  minus the three attributes Milestone 28 added (`iconIdentifier`, `isPinned`, `pinnedAt`
//  on `TaskTemplate` and `SessionPlan`) — so a test can create a genuine V6 store on disk,
//  close it, and reopen it with the production schema.
//
//  They live in the **test target only**: production must never gain a second definition
//  of its models. They are nested inside an enum so their entity names ("TaskTemplate",
//  "FocusSession", …) match the app's, which is what makes the store SwiftData writes here
//  indistinguishable from one written by the shipped V6 build.
//

import Foundation
import SwiftData
@testable import time_frame

/// The V6 schema, as it actually was on disk.
enum SchemaV6Fixture {

    // MARK: Models

    @Model
    final class PomodoroConfiguration {
        private(set) var id: UUID = UUID()
        var name: String = ""
        var focusDuration: TimeInterval = 25 * 60
        var shortBreakDuration: TimeInterval = 5 * 60
        var longBreakDuration: TimeInterval = 15 * 60
        var sessionsBeforeLongBreak: Int = 4
        var defaultTotalSessions: Int = 4
        var createdAt: Date = Date()
        var modifiedAt: Date = Date()
        var isDefault: Bool = false

        @Relationship(deleteRule: .nullify, inverse: \FocusSession.configuration)
        var focusSessions: [FocusSession] = []

        @Relationship(deleteRule: .nullify, inverse: \TaskTemplate.configuration)
        var taskTemplates: [TaskTemplate] = []

        @Relationship(deleteRule: .nullify, inverse: \SessionPlanItem.configuration)
        var planItems: [SessionPlanItem] = []

        init(id: UUID = UUID(), name: String, focusDuration: TimeInterval,
             shortBreakDuration: TimeInterval, longBreakDuration: TimeInterval,
             sessionsBeforeLongBreak: Int, defaultTotalSessions: Int, isDefault: Bool = false) {
            self.id = id
            self.name = name
            self.focusDuration = focusDuration
            self.shortBreakDuration = shortBreakDuration
            self.longBreakDuration = longBreakDuration
            self.sessionsBeforeLongBreak = sessionsBeforeLongBreak
            self.defaultTotalSessions = defaultTotalSessions
            self.isDefault = isDefault
        }
    }

    /// V6 `TaskTemplate` — note the absence of `iconIdentifier`, `isPinned`, `pinnedAt`.
    @Model
    final class TaskTemplate {
        private(set) var id: UUID = UUID()
        var name: String = ""
        var taskName: String = ""
        var configuration: PomodoroConfiguration?
        var defaultTotalSessions: Int = 4
        var isDefault: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), name: String, taskName: String,
             configuration: PomodoroConfiguration?, defaultTotalSessions: Int,
             isDefault: Bool = false) {
            self.id = id
            self.name = name
            self.taskName = taskName
            self.configuration = configuration
            self.defaultTotalSessions = defaultTotalSessions
            self.isDefault = isDefault
        }
    }

    /// V6 `SessionPlan` — likewise without the Quick Start identity fields.
    @Model
    final class SessionPlan {
        private(set) var id: UUID = UUID()
        var name: String = ""
        var taskName: String = ""
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \SessionPlanItem.plan)
        var items: [SessionPlanItem] = []

        init(id: UUID = UUID(), name: String, taskName: String) {
            self.id = id
            self.name = name
            self.taskName = taskName
        }
    }

    @Model
    final class SessionPlanItem {
        private(set) var id: UUID = UUID()
        var order: Int = 0
        var phase: TimerPhase = TimerPhase.focus
        var duration: TimeInterval = 0
        var configuration: PomodoroConfiguration?
        var configurationName: String = ""
        var plan: SessionPlan?

        init(id: UUID = UUID(), order: Int, phase: TimerPhase, duration: TimeInterval,
             configuration: PomodoroConfiguration?, configurationName: String) {
            self.id = id
            self.order = order
            self.phase = phase
            self.duration = duration
            self.configuration = configuration
            self.configurationName = configurationName
        }
    }

    @Model
    final class FocusSession {
        private(set) var id: UUID = UUID()
        var taskName: String = ""
        var configuration: PomodoroConfiguration?
        var configurationName: String = ""
        var startedAt: Date?
        var pausedAt: Date?
        var endedAt: Date?
        var currentIntervalIndex: Int = 0
        var status: SessionStatus = SessionStatus.planned
        var originatingDeviceID: String?

        @Relationship(deleteRule: .cascade, inverse: \SessionInterval.session)
        var intervals: [SessionInterval] = []

        init(id: UUID = UUID(), taskName: String, configuration: PomodoroConfiguration?,
             configurationName: String, status: SessionStatus = .planned) {
            self.id = id
            self.taskName = taskName
            self.configuration = configuration
            self.configurationName = configurationName
            self.status = status
        }
    }

    @Model
    final class SessionInterval {
        private(set) var id: UUID = UUID()
        var phase: TimerPhase = TimerPhase.focus
        var plannedDuration: TimeInterval = 0
        var startedAt: Date?
        var endedAt: Date?
        var targetEndAt: Date?
        var remainingAtPause: TimeInterval?
        var status: IntervalStatus = IntervalStatus.pending
        var order: Int = 0
        var configurationName: String = ""
        var session: FocusSession?

        init(id: UUID = UUID(), phase: TimerPhase, plannedDuration: TimeInterval,
             order: Int, status: IntervalStatus = .pending, configurationName: String = "") {
            self.id = id
            self.phase = phase
            self.plannedDuration = plannedDuration
            self.order = order
            self.status = status
            self.configurationName = configurationName
        }
    }

    // MARK: Schema

    /// The V6 model set, in the same order the app's schema lists it.
    static var models: [any PersistentModel.Type] {
        [
            PomodoroConfiguration.self, FocusSession.self, SessionInterval.self,
            TaskTemplate.self, SessionPlan.self, SessionPlanItem.self
        ]
    }

    static var schema: Schema { Schema(models) }

    /// Opens (or creates) a V6 store at `url`.
    ///
    /// Deliberately takes an explicit URL and refuses the production store, so a fixture
    /// can never be written over a real user's data.
    static func container(at url: URL) throws -> ModelContainer {
        StoreLocation.assertNotProductionStore(url)
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
    }
}
