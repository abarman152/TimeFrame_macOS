//
//  PersistenceTestSupport.swift
//  time_frameTests
//
//  Shared helpers for the Milestone 2 persistence / lifecycle suites.
//
//  IMPORTANT: every test that uses one of these must keep the returned
//  `ModelContainer` alive for the whole test body. A `ModelContext` does not
//  retain its container; letting the container deallocate while a context is in
//  use traps inside SwiftData (see ADR notes / CLAUDE.md).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

/// A fresh in-memory container isolated from disk and from other tests.
@MainActor
func makeInMemoryContainer() throws -> ModelContainer {
    try PersistenceController.makeContainer(inMemory: true)
}

/// A configuration repository over the container's main context.
@MainActor
func makeConfigRepository(_ container: ModelContainer) -> ConfigurationRepository {
    ConfigurationRepository(context: container.mainContext)
}

/// A session repository over the container's main context.
@MainActor
func makeSessionRepository(_ container: ModelContainer) -> SessionRepository {
    SessionRepository(context: container.mainContext)
}

/// A task-template repository over the container's main context.
@MainActor
func makeTemplateRepository(_ container: ModelContainer) -> TaskTemplateRepository {
    TaskTemplateRepository(context: container.mainContext)
}

/// A coordinator wired to the container and a mock clock, with the background
/// heartbeat disabled so tests drive `tick()` deterministically.
@MainActor
func makeCoordinator(
    _ container: ModelContainer,
    clock: MockTimeSource
) -> SessionCoordinator {
    SessionCoordinator(
        context: container.mainContext,
        timeSource: clock,
        autoTick: false
    )
}

/// Inserts a configuration directly (bypassing validation) for lifecycle tests
/// that need short, test-friendly durations.
@MainActor
@discardableResult
func insertConfiguration(
    _ container: ModelContainer,
    name: String = "Test",
    focus: TimeInterval = 10,
    short: TimeInterval = 5,
    long: TimeInterval = 15,
    before: Int = 4,
    total: Int = 4,
    isDefault: Bool = true
) throws -> PomodoroConfiguration {
    let config = PomodoroConfiguration(
        name: name,
        focusDuration: focus,
        shortBreakDuration: short,
        longBreakDuration: long,
        sessionsBeforeLongBreak: before,
        defaultTotalSessions: total,
        isDefault: isDefault
    )
    container.mainContext.insert(config)
    try container.mainContext.save()
    return config
}
