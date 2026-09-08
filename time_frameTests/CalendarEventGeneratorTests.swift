//
//  CalendarEventGeneratorTests.swift
//  time_frameTests
//
//  Pure tests of CalendarEventGenerator: single vs per-interval, durations,
//  titles, notes, and multiple configurations. No EventKit involved (§65–67).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Calendar event generation")
struct CalendarEventGeneratorTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// A four-focus plan: focus/break ×4, long break every fourth (ends on focus).
    private func classicContext() -> CalendarPlanContext {
        var intervals: [CalendarPlanContext.Interval] = []
        for i in 0..<4 {
            intervals.append(.init(phase: .focus, duration: 25 * 60, configurationName: "Classic Pomodoro"))
            if i < 3 {
                intervals.append(.init(phase: .shortBreak, duration: 5 * 60, configurationName: ""))
            }
        }
        return CalendarPlanContext(
            taskName: "Research Quantum IDS",
            planName: "Research Deep Work",
            startDate: start,
            intervals: intervals
        )
    }

    @Test("Single-plan style makes exactly one event spanning the whole plan")
    func singleEvent() {
        let context = classicContext()
        let drafts = CalendarEventGenerator.drafts(for: context, style: .singlePlan, calendarIdentifier: "cal-work")

        #expect(drafts.count == 1)
        let draft = drafts[0]
        #expect(draft.title == "Research Quantum IDS")
        #expect(draft.startDate == start)
        // 4 × 25m focus + 3 × 5m break = 115 minutes.
        #expect(draft.endDate == start.addingTimeInterval(115 * 60))
        #expect(draft.calendarIdentifier == "cal-work")
        #expect(draft.notes?.contains("Plan: Research Deep Work") == true)
        #expect(draft.notes?.contains("Task: Research Quantum IDS") == true)
        #expect(draft.notes?.contains("Focus sessions: 4") == true)
        #expect(draft.notes?.contains("Created by Time Frame") == true)
    }

    @Test("start + total planned duration = end (single event)")
    func durationArithmetic() {
        let context = classicContext()
        let draft = CalendarEventGenerator.drafts(for: context, style: .singlePlan, calendarIdentifier: nil)[0]
        #expect(draft.duration == context.totalDuration)
        #expect(draft.endDate == draft.startDate.addingTimeInterval(context.totalDuration))
    }

    @Test("Per-interval style makes one back-to-back event per interval")
    func perIntervalEvents() {
        let context = classicContext()
        let drafts = CalendarEventGenerator.drafts(for: context, style: .perInterval, calendarIdentifier: "cal-x")

        #expect(drafts.count == context.intervals.count) // 7
        // Back to back: each event starts where the previous ended.
        for pair in zip(drafts, drafts.dropFirst()) {
            #expect(pair.0.endDate == pair.1.startDate)
        }
        // The first starts at the anchor and the last ends at anchor + total.
        #expect(drafts.first?.startDate == start)
        #expect(drafts.last?.endDate == start.addingTimeInterval(context.totalDuration))
    }

    @Test("Per-interval titles are phase-specific")
    func perIntervalTitles() {
        let context = classicContext()
        let drafts = CalendarEventGenerator.drafts(for: context, style: .perInterval, calendarIdentifier: nil)
        #expect(drafts[0].title == "Focus — Research Quantum IDS")
        #expect(drafts[1].title == "Short Break")
        #expect(drafts[1].notes?.contains("Phase: Short Break") == true)
        #expect(drafts[0].notes?.contains("Configuration: Classic Pomodoro") == true)
    }

    @Test("A long break is titled and counted correctly")
    func longBreakTitle() {
        let context = CalendarPlanContext(
            taskName: "Write",
            startDate: start,
            intervals: [
                .init(phase: .focus, duration: 60, configurationName: "Deep"),
                .init(phase: .longBreak, duration: 30, configurationName: "")
            ]
        )
        let drafts = CalendarEventGenerator.drafts(for: context, style: .perInterval, calendarIdentifier: nil)
        #expect(drafts.count == 2)
        #expect(drafts[1].title == "Long Break")
    }

    @Test("Multiple configurations are represented in the notes")
    func multipleConfigurations() {
        let context = CalendarPlanContext(
            taskName: "Mixed",
            planName: "Mixed Plan",
            startDate: start,
            intervals: [
                .init(phase: .focus, duration: 50 * 60, configurationName: "Research"),
                .init(phase: .shortBreak, duration: 10 * 60, configurationName: ""),
                .init(phase: .focus, duration: 45 * 60, configurationName: "Writing")
            ]
        )
        let single = CalendarEventGenerator.drafts(for: context, style: .singlePlan, calendarIdentifier: nil)[0]
        #expect(single.notes?.contains("Research") == true)
        #expect(single.notes?.contains("Writing") == true)

        let perInterval = CalendarEventGenerator.drafts(for: context, style: .perInterval, calendarIdentifier: nil)
        #expect(perInterval[0].notes?.contains("Configuration: Research") == true)
        #expect(perInterval[2].notes?.contains("Configuration: Writing") == true)
    }

    @Test("A trailing break is included when present, absent otherwise")
    func finalBreakHandling() {
        let endsOnFocus = classicContext() // 7 intervals, ends on focus
        #expect(endsOnFocus.intervals.last?.phase == .focus)
        #expect(CalendarEventGenerator.drafts(for: endsOnFocus, style: .perInterval, calendarIdentifier: nil).count == 7)

        var withBreak = endsOnFocus.intervals
        withBreak.append(.init(phase: .shortBreak, duration: 5 * 60, configurationName: ""))
        let endsOnBreak = CalendarPlanContext(taskName: "t", startDate: start, intervals: withBreak)
        #expect(CalendarEventGenerator.drafts(for: endsOnBreak, style: .perInterval, calendarIdentifier: nil).count == 8)
        #expect(endsOnBreak.endDate == start.addingTimeInterval(120 * 60))
    }

    @Test("A custom title overrides only the single-event title")
    func titleOverride() {
        let context = classicContext()
        let single = CalendarEventGenerator.drafts(for: context, style: .singlePlan, calendarIdentifier: nil, titleOverride: "My Focus Block")[0]
        #expect(single.title == "My Focus Block")

        // Per-interval ignores the override and keeps phase titles.
        let perInterval = CalendarEventGenerator.drafts(for: context, style: .perInterval, calendarIdentifier: nil, titleOverride: "My Focus Block")
        #expect(perInterval[0].title == "Focus — Research Quantum IDS")
    }

    @Test("An empty plan produces no drafts")
    func emptyPlan() {
        let context = CalendarPlanContext(taskName: "", startDate: start, intervals: [])
        #expect(CalendarEventGenerator.drafts(for: context, style: .singlePlan, calendarIdentifier: nil).isEmpty)
        #expect(CalendarEventGenerator.drafts(for: context, style: .perInterval, calendarIdentifier: nil).isEmpty)
    }

    @Test("A blank title override falls back to the default title")
    func blankOverrideFallsBack() {
        let context = classicContext()
        let single = CalendarEventGenerator.drafts(for: context, style: .singlePlan, calendarIdentifier: nil, titleOverride: "   ")[0]
        #expect(single.title == "Research Quantum IDS")
    }
}
