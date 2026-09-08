//
//  SessionPlanValidationTests.swift
//  time_frameTests
//
//  Pure validation, duration arithmetic, and ordering normalization for a plan
//  draft. No store, no clock.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Session plan validation")
struct SessionPlanValidationTests {

    private let configID = UUID()

    private func focus(_ duration: TimeInterval = 50 * 60, order: Int = 0) -> PlanItemDraft {
        PlanItemDraft(order: order, phase: .focus, duration: duration,
                      configurationID: configID, configurationName: "Research")
    }

    private func brk(_ duration: TimeInterval = 10 * 60, order: Int = 1) -> PlanItemDraft {
        PlanItemDraft(order: order, phase: .shortBreak, duration: duration)
    }

    @Test("A well-formed plan is valid")
    func validPlan() {
        let draft = SessionPlanDraft(name: "Research", taskName: "Quantum IDS",
                                     items: [focus(), brk(), focus(order: 2)])
        #expect(draft.validate().isEmpty)
    }

    @Test("An empty name is rejected")
    func emptyName() {
        let draft = SessionPlanDraft(name: "   ", taskName: "Quantum IDS", items: [focus()])
        #expect(draft.validate().contains(.emptyName))
    }

    @Test("An empty task name is rejected")
    func emptyTaskName() {
        let draft = SessionPlanDraft(name: "Research", taskName: "", items: [focus()])
        #expect(draft.validate().contains(.emptyTaskName))
    }

    @Test("A plan with no focus interval is rejected")
    func noFocus() {
        let draft = SessionPlanDraft(name: "Breaks only", taskName: "Rest",
                                     items: [brk(order: 0)])
        #expect(draft.validate().contains(.noFocusItems))
    }

    @Test("A focus item missing a configuration is rejected")
    func focusMissingConfiguration() {
        let orphan = PlanItemDraft(order: 0, phase: .focus, duration: 50 * 60, configurationID: nil)
        let draft = SessionPlanDraft(name: "Research", taskName: "Quantum IDS", items: [orphan])
        #expect(draft.validate().contains(.focusMissingConfiguration))
    }

    @Test("A zero-length interval is rejected")
    func zeroDuration() {
        let draft = SessionPlanDraft(name: "Research", taskName: "Quantum IDS",
                                     items: [focus(0)])
        #expect(draft.validate().contains(.invalidItemDuration))
    }

    @Test("An interval longer than eight hours is rejected")
    func intervalTooLong() {
        let draft = SessionPlanDraft(name: "Research", taskName: "Quantum IDS",
                                     items: [focus(PlanLimits.maxItemDuration + 1)])
        #expect(draft.validate().contains(.invalidItemDuration))
    }

    @Test("More than the maximum number of items is rejected")
    func tooManyItems() {
        let items = (0..<(PlanLimits.maxItems + 1)).map { focus(60, order: $0) }
        let draft = SessionPlanDraft(name: "Huge", taskName: "Quantum IDS", items: items)
        #expect(draft.validate().contains(.tooManyItems))
    }

    @Test("A total duration over 24 hours is rejected")
    func totalTooLong() {
        // 5 focus intervals of 5 hours each = 25 hours total (each under the 8h item cap).
        let items = (0..<5).map { focus(5 * 60 * 60, order: $0) }
        let draft = SessionPlanDraft(name: "Marathon", taskName: "Quantum IDS", items: items)
        #expect(draft.validate().contains(.totalDurationTooLong))
    }

    @Test("Total duration sums every interval")
    func totalDurationArithmetic() {
        let draft = SessionPlanDraft(name: "Research", taskName: "Quantum IDS",
                                     items: [focus(50 * 60), brk(10 * 60, order: 1), focus(50 * 60, order: 2)])
        expectClose(draft.totalDuration, 110 * 60)
    }

    @Test("An empty plan reports both missing-name and no-focus rules")
    func emptyPlanReportsAll() {
        let draft = SessionPlanDraft(name: "", taskName: "", items: [])
        let errors = draft.validate()
        #expect(errors.contains(.emptyName))
        #expect(errors.contains(.emptyTaskName))
        #expect(errors.contains(.noFocusItems))
    }

    @Test("Normalization reassigns contiguous order from array position")
    func normalizeOrder() {
        // Items given out-of-order `order` values; normalization uses array position.
        let draft = SessionPlanDraft(name: "Research", taskName: "Quantum IDS", items: [
            focus(order: 9),
            brk(order: 3),
            focus(order: 7)
        ])
        let normalized = draft.normalized
        #expect(normalized.items.map(\.order) == [0, 1, 2])
        // Identity and values are preserved through normalization.
        #expect(normalized.items.map(\.id) == draft.items.map(\.id))
    }

    @Test("Focus count counts only focus items")
    func focusCount() {
        let draft = SessionPlanDraft(name: "Research", taskName: "Quantum IDS",
                                     items: [focus(), brk(), focus(order: 2), brk(order: 3)])
        #expect(draft.focusCount == 2)
    }
}
