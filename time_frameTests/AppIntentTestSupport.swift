//
//  AppIntentTestSupport.swift
//  time_frameTests (Milestone 12)
//
//  A wired rig for the App Intents suites: a real in-memory `SessionCoordinator` (mock clock,
//  heartbeat off) plus helpers to seed templates and plans. The intents' logic lives in
//  `AppIntentSessionActions`, which takes only the coordinator — so these tests drive the
//  exact production path deterministically, with no Siri, Shortcuts, or real time.
//

import Foundation
import SwiftData
@testable import time_frame

@MainActor
struct AppIntentRig {
    let container: ModelContainer
    let clock: MockTimeSource
    let coordinator: SessionCoordinator
    let config: PomodoroConfiguration

    /// The action helper under test, over the one authoritative coordinator.
    var actions: AppIntentSessionActions { AppIntentSessionActions(coordinator: coordinator) }
}

/// Builds a rig with one default configuration (short, test-friendly durations).
@MainActor
func makeAppIntentRig(
    focus: TimeInterval = 10,
    short: TimeInterval = 5,
    long: TimeInterval = 15,
    before: Int = 4,
    total: Int = 4,
    seedDefault: Bool = true
) throws -> AppIntentRig {
    let container = try makeInMemoryContainer()
    let clock = MockTimeSource()
    let coordinator = makeCoordinator(container, clock: clock)
    let config = try insertConfiguration(
        container, name: "Deep Work",
        focus: focus, short: short, long: long, before: before, total: total,
        isDefault: seedDefault)
    return AppIntentRig(container: container, clock: clock, coordinator: coordinator, config: config)
}

/// Inserts a task template referencing the given configuration.
@MainActor
@discardableResult
func insertTemplate(
    _ container: ModelContainer,
    name: String = "Research",
    taskName: String = "Research Paper",
    configuration: PomodoroConfiguration?,
    defaultTotalSessions: Int = 3
) throws -> TaskTemplate {
    let template = TaskTemplate(
        name: name,
        taskName: taskName,
        configuration: configuration,
        defaultTotalSessions: defaultTotalSessions
    )
    container.mainContext.insert(template)
    try container.mainContext.save()
    return template
}

/// Inserts a startable plan: focus → short break → focus, referencing `configuration` on
/// the focus items. Returns the plan.
@MainActor
@discardableResult
func insertPlan(
    _ container: ModelContainer,
    name: String = "Morning Deep Work",
    taskName: String = "Morning Focus",
    configuration: PomodoroConfiguration?,
    focusDuration: TimeInterval = 10,
    breakDuration: TimeInterval = 5
) throws -> SessionPlan {
    let plan = SessionPlan(name: name, taskName: taskName)
    container.mainContext.insert(plan)

    let configName = configuration?.name ?? ""
    let f1 = SessionPlanItem(order: 0, phase: .focus, duration: focusDuration,
                             configuration: configuration, configurationName: configName)
    let b1 = SessionPlanItem(order: 1, phase: .shortBreak, duration: breakDuration)
    let f2 = SessionPlanItem(order: 2, phase: .focus, duration: focusDuration,
                             configuration: configuration, configurationName: configName)
    for item in [f1, b1, f2] {
        item.plan = plan
        container.mainContext.insert(item)
    }
    plan.items = [f1, b1, f2]
    try container.mainContext.save()
    return plan
}
