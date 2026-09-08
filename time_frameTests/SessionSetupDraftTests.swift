//
//  SessionSetupDraftTests.swift
//  time_frameTests
//
//  Pure application logic for the Timer setup screen: task validation, the
//  session-count override, and plan-preview generation. No UI, no persistence.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Session setup draft")
struct SessionSetupDraftTests {

    @Test("A task name is required")
    func taskRequired() {
        #expect(SessionSetupDraft(taskName: "").isValid == false)
        #expect(SessionSetupDraft(taskName: "   \n").isValid == false)
        #expect(SessionSetupDraft(taskName: "Research").isValid == true)
    }

    @Test("The trimmed task name strips surrounding whitespace")
    func trimsWhitespace() {
        let draft = SessionSetupDraft(taskName: "  Research Paper  ")
        #expect(draft.trimmedTaskName == "Research Paper")
        #expect(draft.isValid)
    }

    @Test("The plan preview honours the session-count override")
    func planHonoursOverride() {
        let config = makeConfig(total: 4) // configuration default is 4
        let draft = SessionSetupDraft(taskName: "X", totalSessions: 2)

        let plan = draft.plan(for: config)
        let focusCount = plan.intervals.filter { $0.phase == .focus }.count
        #expect(focusCount == 2)             // override applied
        #expect(plan.intervals.count == 4)   // focus, break, focus, break
    }

    @Test("The plan preview uses the configuration's durations")
    func planUsesConfigDurations() {
        let expectedFocus: TimeInterval = 30 * 60
        let config = makeConfig(focus: expectedFocus, short: 5 * 60, total: 1)
        let draft = SessionSetupDraft(taskName: "X", totalSessions: 1)

        let plan = draft.plan(for: config)
        #expect(plan.intervals.first?.phase == .focus)
        #expect(plan.intervals.first?.duration == expectedFocus)
    }
}

@Suite("Configuration snapshot override")
struct ConfigurationSnapshotOverrideTests {

    @Test("Overriding replaces only the session count")
    func overrideReplacesCountOnly() {
        let base = makeConfig(focus: 25 * 60, short: 5 * 60, long: 15 * 60, before: 4, total: 4)
        let overridden = base.overriding(totalSessions: 7)

        #expect(overridden.totalSessions == 7)
        #expect(overridden.focusDuration == base.focusDuration)
        #expect(overridden.shortBreakDuration == base.shortBreakDuration)
        #expect(overridden.longBreakDuration == base.longBreakDuration)
        #expect(overridden.sessionsBeforeLongBreak == base.sessionsBeforeLongBreak)
    }

    @Test("A nil override returns an identical snapshot")
    func nilOverrideIsIdentity() {
        let base = makeConfig(total: 4)
        #expect(base.overriding(totalSessions: nil) == base)
    }
}
