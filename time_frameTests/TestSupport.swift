//
//  TestSupport.swift
//  time_frameTests
//
//  Shared helpers for the timer engine test suites.
//

import Foundation
import Testing
@testable import time_frame

/// Builds a configuration snapshot with test-friendly (short) defaults.
nonisolated func makeConfig(
    focus: TimeInterval = 10,
    short: TimeInterval = 5,
    long: TimeInterval = 15,
    before: Int = 4,
    total: Int = 4
) -> PomodoroConfigurationSnapshot {
    PomodoroConfigurationSnapshot(
        focusDuration: focus,
        shortBreakDuration: short,
        longBreakDuration: long,
        sessionsBeforeLongBreak: before,
        totalSessions: total
    )
}

/// Builds an engine driven by the given mock clock.
@MainActor
func makeEngine(
    _ config: PomodoroConfigurationSnapshot = makeConfig(),
    clock: MockTimeSource
) -> TimerEngine {
    TimerEngine(configuration: config, timeSource: clock)
}

/// Asserts two time intervals are equal within a small tolerance.
func expectClose(
    _ lhs: TimeInterval,
    _ rhs: TimeInterval,
    tolerance: TimeInterval = 0.0001,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(abs(lhs - rhs) <= tolerance, "expected \(lhs) ≈ \(rhs)", sourceLocation: sourceLocation)
}
