//
//  ConfigurationValidationTests.swift
//  time_frameTests
//
//  Pure validation rules for configuration drafts (ADR-015).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Configuration validation")
struct ConfigurationValidationTests {

    @Test("A sensible draft is valid")
    func validDraft() {
        let draft = ConfigurationDraft(name: "Deep Work")
        #expect(draft.validate().isEmpty)
    }

    @Test("An empty or whitespace name is rejected")
    func emptyName() {
        #expect(ConfigurationDraft(name: "").validate().contains(.emptyName))
        #expect(ConfigurationDraft(name: "   ").validate().contains(.emptyName))
    }

    @Test("Focus duration must be strictly positive")
    func focusNotPositive() {
        let errors = ConfigurationDraft(name: "X", focusDuration: 0).validate()
        #expect(errors.contains(.focusDurationNotPositive))
    }

    @Test("Breaks may be zero but not negative")
    func breaksNonNegative() {
        #expect(ConfigurationDraft(name: "X", shortBreakDuration: 0, longBreakDuration: 0).validate().isEmpty)
        let errors = ConfigurationDraft(name: "X", shortBreakDuration: -1, longBreakDuration: -1).validate()
        #expect(errors.contains(.shortBreakNegative))
        #expect(errors.contains(.longBreakNegative))
    }

    @Test("Counts must be strictly positive")
    func countsPositive() {
        let errors = ConfigurationDraft(name: "X", sessionsBeforeLongBreak: 0, totalSessions: 0).validate()
        #expect(errors.contains(.totalSessionsNotPositive))
        #expect(errors.contains(.sessionsBeforeLongBreakNotPositive))
    }

    @Test("Values beyond the maximum limits are rejected")
    func overMaxima() {
        let errors = ConfigurationDraft(
            name: "X",
            focusDuration: ConfigurationLimits.maxDuration + 1,
            shortBreakDuration: ConfigurationLimits.maxDuration + 1,
            longBreakDuration: ConfigurationLimits.maxDuration + 1,
            sessionsBeforeLongBreak: ConfigurationLimits.maxSessionsBeforeLongBreak + 1,
            totalSessions: ConfigurationLimits.maxTotalSessions + 1
        ).validate()
        #expect(errors.contains(.focusDurationTooLong))
        #expect(errors.contains(.shortBreakTooLong))
        #expect(errors.contains(.longBreakTooLong))
        #expect(errors.contains(.tooManySessions))
        #expect(errors.contains(.sessionsBeforeLongBreakTooLarge))
    }

    @Test("Invalid input is reported, never silently modified")
    func doesNotMutate() throws {
        let draft = ConfigurationDraft(name: "X", focusDuration: -5)
        // The draft's own values are untouched; validation only reports.
        #expect(draft.focusDuration == -5)
        #expect(throws: PersistenceError.self) { try draft.validated() }
    }
}
