//
//  TaskTemplateValidationTests.swift
//  time_frameTests
//
//  Pure validation rules for TaskTemplateDraft (Milestone 4). No store needed —
//  validation is a pure function.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Task template validation")
struct TaskTemplateValidationTests {

    private func validDraft() -> TaskTemplateDraft {
        TaskTemplateDraft(
            name: "Research",
            taskName: "Research Quantum IDS",
            configurationID: UUID(),
            defaultTotalSessions: 4
        )
    }

    @Test("A complete draft is valid")
    func validDraftPasses() {
        #expect(validDraft().validate().isEmpty)
    }

    @Test("An empty template name is rejected")
    func emptyName() {
        var draft = validDraft()
        draft.name = "   "
        #expect(draft.validate().contains(.emptyName))
    }

    @Test("An empty task name is rejected")
    func emptyTaskName() {
        var draft = validDraft()
        draft.taskName = ""
        #expect(draft.validate().contains(.emptyTaskName))
    }

    @Test("A missing configuration is rejected")
    func missingConfiguration() {
        var draft = validDraft()
        draft.configurationID = nil
        #expect(draft.validate().contains(.missingConfiguration))
    }

    @Test("A session count below one is rejected")
    func sessionCountTooLow() {
        var draft = validDraft()
        draft.defaultTotalSessions = 0
        #expect(draft.validate().contains(.sessionCountNotPositive))
    }

    @Test("A session count above the maximum is rejected")
    func sessionCountTooHigh() {
        var draft = validDraft()
        draft.defaultTotalSessions = ConfigurationLimits.maxTotalSessions + 1
        #expect(draft.validate().contains(.tooManySessions))
    }

    @Test("The boundary session counts are valid")
    func boundarySessionCounts() {
        var low = validDraft(); low.defaultTotalSessions = 1
        var high = validDraft(); high.defaultTotalSessions = ConfigurationLimits.maxTotalSessions
        #expect(low.validate().isEmpty)
        #expect(high.validate().isEmpty)
    }

    @Test("Names are trimmed before persistence")
    func trimming() {
        var draft = validDraft()
        draft.name = "  Research  "
        draft.taskName = "  Research Quantum IDS  "
        #expect(draft.trimmedName == "Research")
        #expect(draft.trimmedTaskName == "Research Quantum IDS")
    }

    @Test("validated() throws on the first invalid draft, carrying all reasons")
    func validatedThrows() {
        var draft = validDraft()
        draft.name = ""
        draft.configurationID = nil
        #expect(throws: PersistenceError.self) { try draft.validated() }
    }
}
