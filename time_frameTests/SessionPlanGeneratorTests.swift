//
//  SessionPlanGeneratorTests.swift
//  time_frameTests
//
//  Deterministic generation of an initial plan from a configuration: session
//  counts, long-break placement, the optional trailing break, custom durations,
//  and per-focus configuration identity. Pure — no store, no clock.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Session plan generation")
struct SessionPlanGeneratorTests {

    private let configID = UUID()

    private func generate(
        _ config: PomodoroConfigurationSnapshot,
        sessions: Int,
        includeFinalBreak: Bool = false
    ) -> [PlanItemDraft] {
        SessionPlanGenerator.generate(
            from: config,
            configurationID: configID,
            configurationName: "Research",
            sessions: sessions,
            includeFinalBreak: includeFinalBreak
        )
    }

    @Test("A single-session plan is one focus and no trailing break by default")
    func singleSessionNoFinalBreak() {
        let items = generate(makeConfig(total: 4), sessions: 1)
        #expect(items.map(\.phase) == [.focus])
        #expect(items.count == 1)
    }

    @Test("A single-session plan can include a trailing break when asked")
    func singleSessionWithFinalBreak() {
        let items = generate(makeConfig(before: 4, total: 4), sessions: 1, includeFinalBreak: true)
        #expect(items.map(\.phase) == [.focus, .shortBreak])
    }

    @Test("A two-session plan ends on focus by default (no final break)")
    func twoSessionsEndOnFocus() {
        let items = generate(makeConfig(before: 4), sessions: 2)
        #expect(items.map(\.phase) == [.focus, .shortBreak, .focus])
        #expect(items.last?.phase == .focus)
    }

    @Test("A four-session plan places a long break at the interval boundary")
    func fourSessionsLongBreakPlacement() {
        // Long break every 4th focus; with no final break the last (4th) focus ends
        // the plan, so the long break that would follow it is omitted.
        let items = generate(makeConfig(before: 4), sessions: 4)
        #expect(items.map(\.phase) == [
            .focus, .shortBreak,
            .focus, .shortBreak,
            .focus, .shortBreak,
            .focus
        ])
    }

    @Test("A four-session plan with a final break ends on the long break")
    func fourSessionsWithFinalLongBreak() {
        let items = generate(makeConfig(before: 4), sessions: 4, includeFinalBreak: true)
        #expect(items.map(\.phase) == [
            .focus, .shortBreak,
            .focus, .shortBreak,
            .focus, .shortBreak,
            .focus, .longBreak
        ])
    }

    @Test("A custom long-break interval of two makes every second break long")
    func customLongBreakInterval() {
        let items = generate(makeConfig(before: 2), sessions: 4, includeFinalBreak: true)
        #expect(items.map(\.phase) == [
            .focus, .shortBreak,
            .focus, .longBreak,
            .focus, .shortBreak,
            .focus, .longBreak
        ])
    }

    @Test("Durations come from the configuration and map to the right phase")
    func customDurations() {
        let items = generate(makeConfig(focus: 50 * 60, short: 10 * 60, long: 30 * 60, before: 4), sessions: 4, includeFinalBreak: true)
        for item in items {
            switch item.phase {
            case .focus: expectClose(item.duration, 50 * 60)
            case .shortBreak: expectClose(item.duration, 10 * 60)
            case .longBreak: expectClose(item.duration, 30 * 60)
            }
        }
    }

    @Test("Generation is deterministic: same input yields an identical plan")
    func deterministic() {
        let a = generate(makeConfig(before: 4), sessions: 4)
        let b = generate(makeConfig(before: 4), sessions: 4)
        #expect(a.map(\.phase) == b.map(\.phase))
        #expect(a.map(\.duration) == b.map(\.duration))
    }

    @Test("Every focus item carries the source configuration's identity and name")
    func focusItemsCarryConfiguration() {
        let items = generate(makeConfig(before: 4), sessions: 3)
        for item in items where item.isFocus {
            #expect(item.configurationID == configID)
            #expect(item.configurationName == "Research")
        }
        for item in items where !item.isFocus {
            #expect(item.configurationID == nil)
        }
    }

    @Test("Orders are contiguous and zero-based")
    func contiguousOrders() {
        let items = generate(makeConfig(before: 4), sessions: 4, includeFinalBreak: true)
        #expect(items.map(\.order) == Array(0..<items.count))
    }

    @Test("The focus count always equals the requested session count")
    func focusCountMatchesRequest() {
        for sessions in 1...6 {
            let items = generate(makeConfig(before: 4), sessions: sessions)
            #expect(items.filter(\.isFocus).count == sessions)
        }
    }
}
