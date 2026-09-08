//
//  SessionPlanTests.swift
//  time_frameTests
//
//  Engine IntervalPlan sequence generation, including long-break placement.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Interval plan generation")
struct SessionPlanTests {

    @Test("Four-session plan alternates focus/break and ends on a long break")
    func fourSessionSequence() {
        let plan = IntervalPlan(configuration: makeConfig(focus: 10, short: 5, long: 15, before: 4, total: 4))
        let phases = plan.intervals.map(\.phase)
        #expect(phases == [
            .focus, .shortBreak,
            .focus, .shortBreak,
            .focus, .shortBreak,
            .focus, .longBreak
        ])
        #expect(plan.count == 8)
    }

    @Test("Durations map to the correct phase")
    func durationsMapCorrectly() {
        let plan = IntervalPlan(configuration: makeConfig(focus: 25, short: 5, long: 15, before: 4, total: 4))
        for interval in plan.intervals {
            switch interval.phase {
            case .focus: expectClose(interval.duration, 25)
            case .shortBreak: expectClose(interval.duration, 5)
            case .longBreak: expectClose(interval.duration, 15)
            }
        }
    }

    @Test("Indices are contiguous and zero-based")
    func contiguousIndices() {
        let plan = IntervalPlan(configuration: makeConfig(total: 3))
        #expect(plan.intervals.map(\.index) == Array(0..<plan.count))
    }

    @Test("Long break honours a custom interval of two")
    func customLongBreakInterval() {
        let plan = IntervalPlan(configuration: makeConfig(before: 2, total: 4))
        let phases = plan.intervals.map(\.phase)
        #expect(phases == [
            .focus, .shortBreak,
            .focus, .longBreak,
            .focus, .shortBreak,
            .focus, .longBreak
        ])
    }

    @Test("Single-session plan is a focus followed by a short break")
    func singleSession() {
        let plan = IntervalPlan(configuration: makeConfig(before: 4, total: 1))
        #expect(plan.intervals.map(\.phase) == [.focus, .shortBreak])
    }

    @Test("A one-in-one long-break interval makes every break long")
    func everyBreakLong() {
        let plan = IntervalPlan(configuration: makeConfig(before: 1, total: 2))
        #expect(plan.intervals.map(\.phase) == [.focus, .longBreak, .focus, .longBreak])
    }

    @Test("The number of focus intervals equals the configured session count")
    func focusCountMatchesConfig() {
        let plan = IntervalPlan(configuration: makeConfig(total: 5))
        #expect(plan.intervals.filter { $0.phase == .focus }.count == 5)
    }
}
