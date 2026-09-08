//
//  PomodoroConfigurationSnapshotTests.swift
//  time_frameTests
//
//  Configuration validation and plan-shaping inputs.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Configuration")
struct PomodoroConfigurationSnapshotTests {

    @Test("Custom durations and counts are preserved")
    func customValues() {
        let config = PomodoroConfigurationSnapshot(
            focusDuration: 50 * 60,
            shortBreakDuration: 10 * 60,
            longBreakDuration: 30 * 60,
            sessionsBeforeLongBreak: 3,
            totalSessions: 6
        )
        expectClose(config.focusDuration, 50 * 60)
        expectClose(config.shortBreakDuration, 10 * 60)
        expectClose(config.longBreakDuration, 30 * 60)
        #expect(config.sessionsBeforeLongBreak == 3)
        #expect(config.totalSessions == 6)
    }

    @Test("Zero and negative durations are clamped to the minimum")
    func invalidDurationsClamped() {
        let config = PomodoroConfigurationSnapshot(
            focusDuration: 0,
            shortBreakDuration: -5,
            longBreakDuration: .nan,
            sessionsBeforeLongBreak: 4,
            totalSessions: 4
        )
        expectClose(config.focusDuration, PomodoroConfigurationSnapshot.minimumDuration)
        expectClose(config.shortBreakDuration, PomodoroConfigurationSnapshot.minimumDuration)
        expectClose(config.longBreakDuration, PomodoroConfigurationSnapshot.minimumDuration)
    }

    @Test("Session count and long-break interval are clamped to at least one")
    func invalidCountsClamped() {
        let config = PomodoroConfigurationSnapshot(
            focusDuration: 10,
            shortBreakDuration: 5,
            longBreakDuration: 15,
            sessionsBeforeLongBreak: 0,
            totalSessions: -2
        )
        #expect(config.sessionsBeforeLongBreak == 1)
        #expect(config.totalSessions == 1)
    }
}
