//
//  WidgetProjectionWriterTests.swift
//  time_frameTests (Milestone 11)
//
//  The app-side writer mirrors authoritative state into the store and asks WidgetKit to
//  reload — but it must never mutate the timer (ADR-055). These tests wire the REAL
//  coordinator to a volatile store and a stub reload, and assert the written projection
//  matches state, a reload is requested, and the coordinator/engine are untouched.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Widget projection writer")
struct WidgetProjectionWriterTests {

    private final class ReloadCounter { var count = 0 }

    private func scratchStore() -> WidgetProjectionStore {
        let suite = "test.widget.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return WidgetProjectionStore(defaults: defaults)
    }

    @Test("Updating writes a projection that matches the running state and reloads")
    func writesRunningAndReloads() async throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 1500, total: 4)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let store = scratchStore()
        let reloads = ReloadCounter()
        let writer = WidgetProjectionWriter(
            coordinator: coordinator, store: store,
            now: { clock.now() },
            todayProvider: { TodaySummary(focusSeconds: 600, completedSessions: 1) },
            reload: { reloads.count += 1 }
        )

        try coordinator.startSession(configuration: config, taskName: "Ship it")
        writer.update()

        // The SESSION projection is written synchronously, so a control never waits on a
        // statistics read (M26, ADR-099).
        let immediate = store.read()
        #expect(immediate?.state == .running)
        #expect(immediate?.phase == .focus)
        #expect(immediate?.title == "Ship it")
        #expect(reloads.count == 1)

        // The TODAY summary arrives on the coalesced follow-up pass, off the control path.
        await drainTodayRefresh()
        let read = store.read()
        #expect(read?.state == .running)
        #expect(read?.title == "Ship it")
        #expect(read?.focusSecondsToday == 600)
        #expect(reloads.count == 2, "one extra reload when the today figures actually change")
    }

    /// Lets the writer's deferred today-summary task run to completion.
    private func drainTodayRefresh() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test("Handling a lifecycle event refreshes the projection")
    func handleEventWrites() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 100)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let store = scratchStore()
        let writer = WidgetProjectionWriter(coordinator: coordinator, store: store, now: { clock.now() })

        try coordinator.startSession(configuration: config)
        clock.advance(by: 30)
        try coordinator.pause()
        writer.handle(.paused(coordinator.currentLifecycleContext()!))

        let read = store.read()
        #expect(read?.state == .paused)
        expectClose(read?.pausedRemainingSeconds ?? -1, 70)
    }

    @Test("Updating the widget never mutates the coordinator or engine")
    func doesNotMutateModel() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 100)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let writer = WidgetProjectionWriter(coordinator: coordinator, store: scratchStore(), now: { clock.now() })

        try coordinator.startSession(configuration: config, taskName: "Untouched")
        let sessionID = coordinator.activeSession?.id
        let stateBefore = coordinator.engine.state
        let indexBefore = coordinator.engine.currentIndex
        let remainingBefore = coordinator.engine.remaining

        writer.update()
        writer.update()

        #expect(coordinator.activeSession?.id == sessionID)
        #expect(coordinator.engine.state == stateBefore)
        #expect(coordinator.engine.currentIndex == indexBefore)
        expectClose(coordinator.engine.remaining, remainingBefore)
    }
}
