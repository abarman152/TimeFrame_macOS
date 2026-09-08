//
//  WidgetTimelinePolicyTests.swift
//  time_frameTests (Milestone 11)
//
//  The timeline policy is pure: given a projection and `now` it decides the entry instants
//  and reload policy — no WidgetKit, no clock, no countdown loop (ADR-055). These tests pin
//  the contract: running reloads at the planned interval end, paused schedules NO artificial
//  tick, and settled/corrupt states use a conservative reload and never crash.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Widget timeline policy")
struct WidgetTimelinePolicyTests {

    private let now = Date(timeIntervalSinceReferenceDate: 700_000_000)

    @Test("Running reloads at the planned interval end")
    func runningRefreshesAtPlannedEnd() {
        let end = now.addingTimeInterval(25 * 60)
        let p = WidgetProjection(
            generatedAt: now, state: .running, phase: .focus,
            intervalStartedAt: now, intervalPlannedEndAt: end
        )
        let plan = WidgetTimelinePolicy.plan(for: p, now: now)

        #expect(plan.entryDates.first == now)
        #expect(plan.entryDates.contains(end))
        #expect(plan.refresh == .after(end))
    }

    @Test("Running with a past/missing end recovers with a conservative reload, not a crash")
    func runningWithoutFutureEnd() {
        let past = now.addingTimeInterval(-60)
        let p = WidgetProjection(
            generatedAt: now, state: .running, phase: .focus,
            intervalStartedAt: past, intervalPlannedEndAt: past
        )
        let plan = WidgetTimelinePolicy.plan(for: p, now: now)
        #expect(plan.entryDates == [now])
        #expect(plan.refresh == .after(now.addingTimeInterval(WidgetTimelinePolicy.conservativeRefreshInterval)))
    }

    @Test("Paused schedules a single entry and NO artificial countdown tick")
    func pausedNeverTicks() {
        let p = WidgetProjection(
            generatedAt: now, state: .paused, phase: .focus,
            pausedRemainingSeconds: 12 * 60
        )
        let plan = WidgetTimelinePolicy.plan(for: p, now: now)
        #expect(plan.entryDates == [now]) // exactly one entry — never advances
        #expect(plan.refresh == .never)
    }

    @Test("Idle, completed, interrupted and unavailable use a conservative reload")
    func settledStatesAreConservative() {
        let conservative = WidgetRefreshPolicy.after(now.addingTimeInterval(WidgetTimelinePolicy.conservativeRefreshInterval))
        for state in [WidgetSessionState.idle, .completed, .interrupted, .unavailable] {
            let p = WidgetProjection(generatedAt: now, state: state, phase: .none)
            let plan = WidgetTimelinePolicy.plan(for: p, now: now)
            #expect(plan.entryDates == [now])
            #expect(plan.refresh == conservative)
        }
    }

    @Test("An unavailable (corrupt/missing) projection never produces an empty timeline")
    func unavailableNeverEmpty() {
        let p = WidgetProjection.unavailable(reason: "corrupt", at: now)
        let plan = WidgetTimelinePolicy.plan(for: p, now: now)
        #expect(plan.entryDates.isEmpty == false)
    }
}
