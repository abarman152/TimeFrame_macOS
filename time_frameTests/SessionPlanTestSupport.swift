//
//  SessionPlanTestSupport.swift
//  time_frameTests
//
//  Shared helpers for the Milestone 5 Session Planner suites. In-memory store,
//  mock clock, value-typed drafts — deterministic and isolated from disk.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

/// A session-plan repository over the container's main context.
@MainActor
func makePlanRepository(_ container: ModelContainer) -> SessionPlanRepository {
    SessionPlanRepository(context: container.mainContext)
}

/// A focus plan-item draft referencing a configuration by id.
nonisolated func focusItem(
    _ configuration: PomodoroConfiguration,
    duration: TimeInterval? = nil,
    order: Int = 0
) -> PlanItemDraft {
    PlanItemDraft(
        order: order,
        phase: .focus,
        duration: duration ?? configuration.focusDuration,
        configurationID: configuration.id,
        configurationName: configuration.name
    )
}

/// A break plan-item draft (short or long).
nonisolated func breakItem(
    _ phase: TimerPhase,
    duration: TimeInterval,
    order: Int = 0
) -> PlanItemDraft {
    PlanItemDraft(order: order, phase: phase, duration: duration)
}

/// A simple, valid plan draft: focus, short break, focus (ends on focus).
@MainActor
func simplePlanDraft(_ configuration: PomodoroConfiguration, name: String = "Research Deep Work", task: String = "Research Quantum IDS") -> SessionPlanDraft {
    SessionPlanDraft(
        name: name,
        taskName: task,
        items: [
            focusItem(configuration, order: 0),
            breakItem(.shortBreak, duration: configuration.shortBreakDuration, order: 1),
            focusItem(configuration, order: 2)
        ]
    )
}
