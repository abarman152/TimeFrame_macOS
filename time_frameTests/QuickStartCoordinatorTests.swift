//
//  QuickStartCoordinatorTests.swift
//  time_frameTests (Milestone 28)
//
//  The Quick Start adapter must behave exactly like every other Time Frame surface: it
//  observes the ONE authoritative coordinator, and every start it performs goes through the
//  existing `AppIntentSessionActions` seam into that one `SessionCoordinator`/`TimerEngine`
//  (ADR-104). These tests drive the real coordinator with a mock clock, so a start is proved
//  against real engine state rather than a stub.
//
//  They also hold the failure behaviour: a stale row, a deleted item, an item that lost its
//  configuration, or a session that is already running must fail *safely* — a message, no
//  phantom session, and a timer that is left exactly as it was.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
private struct QuickStartRig {
    let container: ModelContainer
    let clock: MockTimeSource
    let coordinator: SessionCoordinator
    let quickStart: QuickStartCoordinator
    let config: PomodoroConfiguration
}

@MainActor
private func makeQuickStartRig() throws -> QuickStartRig {
    let container = try makeInMemoryContainer()
    let clock = MockTimeSource()
    let coordinator = makeCoordinator(container, clock: clock)
    let config = try insertConfiguration(container, focus: 10, short: 5, long: 15, before: 4, total: 2)
    return QuickStartRig(container: container, clock: clock, coordinator: coordinator,
                         quickStart: QuickStartCoordinator(session: coordinator), config: config)
}

@Suite("Quick Start coordinator")
@MainActor
struct QuickStartCoordinatorTests {

    @Test("The adapter observes the one shared coordinator; it never builds its own")
    func sharesTheOneCoordinator() throws {
        let rig = try makeQuickStartRig()
        #expect(rig.quickStart.session === rig.coordinator)
        _ = rig.container
    }

    @Test("Refresh publishes the pinned items and reflects a later unpin")
    func refreshPublishesPins() throws {
        let rig = try makeQuickStartRig()
        let template = try rig.coordinator.templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship", configurationID: rig.config.id))

        rig.quickStart.refresh()
        #expect(rig.quickStart.isEmpty)

        try rig.coordinator.templates.setPinned(template, true)
        rig.quickStart.refresh()
        #expect(rig.quickStart.items.map(\.name) == ["Deep Work"])
        #expect(rig.quickStart.isEmpty == false)

        try rig.coordinator.templates.setPinned(template, false)
        rig.quickStart.refresh()
        #expect(rig.quickStart.isEmpty)
        _ = rig.container
    }

    @Test("Starting a pinned template runs the ONE engine through the existing seam")
    func startTemplateRunsTheOneEngine() throws {
        let rig = try makeQuickStartRig()
        let template = try rig.coordinator.templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship Release",
                              configurationID: rig.config.id, defaultTotalSessions: 2))
        try rig.coordinator.templates.setPinned(template, true)
        rig.quickStart.refresh()

        let item = try #require(rig.quickStart.items.first)
        #expect(rig.quickStart.start(item))

        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.coordinator.activeSession?.taskName == "Ship Release")
        #expect(rig.coordinator.engine.totalFocusSessions == 2)
        #expect(rig.quickStart.lastErrorMessage == nil)
        _ = rig.container
    }

    @Test("Starting a pinned plan runs the plan's frozen snapshot through the one engine")
    func startPlanRunsTheOneEngine() throws {
        let rig = try makeQuickStartRig()
        let plan = try rig.coordinator.plans.create(
            simplePlanDraft(rig.config, name: "Weekly Focus", task: "Thesis"))
        try rig.coordinator.plans.setPinned(plan, true)
        rig.quickStart.refresh()

        let item = try #require(rig.quickStart.items.first)
        #expect(item.kind == .plan)
        #expect(rig.quickStart.start(item))

        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.coordinator.activeSession?.taskName == "Thesis")
        #expect(rig.coordinator.engine.plan.intervals.count == 3)
        _ = rig.container
    }

    @Test("Quick Start cannot start a second session while one is running")
    func cannotStartWhileRunning() throws {
        let rig = try makeQuickStartRig()
        let template = try rig.coordinator.templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship", configurationID: rig.config.id))
        try rig.coordinator.templates.setPinned(template, true)
        rig.quickStart.refresh()
        let item = try #require(rig.quickStart.items.first)
        #expect(rig.quickStart.start(item))

        let running = rig.coordinator.activeSession?.id
        #expect(rig.quickStart.canStart == false)
        #expect(rig.quickStart.start(item) == false)

        #expect(rig.coordinator.activeSession?.id == running, "The live session must be untouched")
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.quickStart.lastErrorMessage != nil)
        _ = rig.container
    }

    @Test("Starting a stale row for a deleted item fails safely and re-reads the truth")
    func staleRowFailsSafely() throws {
        let rig = try makeQuickStartRig()
        let template = try rig.coordinator.templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship", configurationID: rig.config.id))
        try rig.coordinator.templates.setPinned(template, true)
        rig.quickStart.refresh()
        let stale = try #require(rig.quickStart.items.first)

        // Deleted behind the popover's back — the cached row is now stale.
        try rig.coordinator.templates.delete(template)

        #expect(rig.quickStart.start(stale) == false)
        #expect(rig.coordinator.engine.state == .idle, "No phantom session may be created")
        #expect(rig.coordinator.activeSession == nil)
        #expect(rig.quickStart.lastErrorMessage != nil)
        #expect(rig.quickStart.isEmpty, "The failed start re-reads the authoritative list")
        _ = rig.container
    }

    @Test("Starting an item whose configuration was deleted fails safely")
    func unstartableItemFailsSafely() throws {
        let rig = try makeQuickStartRig()
        let template = try rig.coordinator.templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship", configurationID: rig.config.id))
        try rig.coordinator.templates.setPinned(template, true)
        rig.container.mainContext.delete(rig.config)
        try rig.container.mainContext.save()
        rig.quickStart.refresh()

        let item = try #require(rig.quickStart.items.first)
        #expect(item.isStartable == false)
        #expect(rig.quickStart.start(item) == false)
        #expect(rig.coordinator.engine.state == .idle)
        #expect(rig.quickStart.lastErrorMessage != nil)
        _ = rig.container
    }

    @Test("A stale plan row for a deleted plan fails safely")
    func stalePlanRowFailsSafely() throws {
        let rig = try makeQuickStartRig()
        let plan = try rig.coordinator.plans.create(simplePlanDraft(rig.config))
        try rig.coordinator.plans.setPinned(plan, true)
        rig.quickStart.refresh()
        let stale = try #require(rig.quickStart.items.first)
        try rig.coordinator.plans.delete(plan)

        #expect(rig.quickStart.start(stale) == false)
        #expect(rig.coordinator.engine.state == .idle)
        #expect(rig.quickStart.lastErrorMessage != nil)
        _ = rig.container
    }

    @Test("A successful start clears any previous error message")
    func successClearsError() throws {
        let rig = try makeQuickStartRig()
        let template = try rig.coordinator.templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship", configurationID: rig.config.id))
        try rig.coordinator.templates.setPinned(template, true)
        rig.quickStart.refresh()
        let item = try #require(rig.quickStart.items.first)

        rig.quickStart.lastErrorMessage = "stale message"
        #expect(rig.quickStart.start(item))
        #expect(rig.quickStart.lastErrorMessage == nil)
        _ = rig.container
    }

    @Test("Quick Start adds no clock: nothing advances without the injected time source")
    func addsNoClock() throws {
        let rig = try makeQuickStartRig()
        let template = try rig.coordinator.templates.create(
            TaskTemplateDraft(name: "Deep Work", taskName: "Ship", configurationID: rig.config.id))
        try rig.coordinator.templates.setPinned(template, true)
        rig.quickStart.refresh()
        _ = rig.quickStart.start(try #require(rig.quickStart.items.first))

        let before = rig.coordinator.engine.remaining
        rig.quickStart.refresh()
        rig.quickStart.refresh()
        #expect(rig.coordinator.engine.remaining == before,
                "Refreshing the list must not move the timer")

        rig.clock.advance(by: 4)
        #expect(rig.coordinator.engine.remaining == before - 4,
                "Time only moves with the injected clock")
        _ = rig.container
    }
}

@Suite("Quick Start error lifetime")
@MainActor
struct QuickStartErrorTests {

    @Test("A stale failure message can be cleared without touching the list or the timer")
    func clearError() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let quickStart = QuickStartCoordinator(session: coordinator)

        quickStart.lastErrorMessage = "A session is already running"
        quickStart.clearError()

        #expect(quickStart.lastErrorMessage == nil)
        #expect(coordinator.engine.state == .idle)
        #expect(quickStart.isEmpty)
        _ = container
    }
}
