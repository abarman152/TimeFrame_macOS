//
//  AllIntegrationsFailureIsolationTests.swift
//  time_frameTests (Milestone 17)
//
//  The per-integration independence suites each prove ONE observer can fail without stopping
//  the timer. This is the consolidated worst case: Calendar, Notifications, and the Widget
//  projection are wired to a single real coordinator through the same lifecycle fan-out the
//  app uses, ALL failing at once, plus a deliberately disruptive lifecycle observer — and a
//  full session is driven start → run → completion. The timer must stay perfectly
//  authoritative and persist correctly regardless (ADR-035/042/055; §71/§62).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("All integrations failing — timer isolation")
struct AllIntegrationsFailureIsolationTests {

    private struct Rig {
        let container: ModelContainer
        let clock: MockTimeSource
        let coordinator: SessionCoordinator
        let config: PomodoroConfiguration
        let observerCalls: Box
    }

    /// A tiny reference box so the disruptive observer can record that it ran (and threw,
    /// caught) without the coordinator ever depending on the result.
    private final class Box { var count = 0 }

    private func makeFailingRig(focus: TimeInterval = 10, total: Int = 1) throws -> Rig {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: focus, total: total)

        // Calendar — enabled, permission granted, but every write fails.
        let calDefaults = makeScratchDefaults()
        let calPrefs = CalendarPreferencesStore(defaults: calDefaults)
        calPrefs.isEnabled = true
        let calService = FakeCalendarService(status: .fullAccess)
        calService.failCreate = .saveFailed
        calService.failAdjust = .updateFailed
        let calendar = CalendarCoordinator(service: calService, preferences: calPrefs,
                                           records: CalendarEventRecordStore(defaults: calDefaults))

        // Notifications — enabled, authorized, but every schedule fails.
        let notePrefs = NotificationPreferencesStore(defaults: makeScratchDefaults())
        notePrefs.isEnabled = true
        let noteService = FakeNotificationService(status: .authorized)
        noteService.failSchedule = .schedulingFailed
        let notifications = NotificationCoordinator(scheduler: noteService, preferences: notePrefs)

        // Widget — an inert App Group store (writes no-op) with a today provider that fails.
        let widgetWriter = WidgetProjectionWriter(
            coordinator: coordinator,
            store: WidgetProjectionStore(defaults: nil),
            todayProvider: { nil },
            reload: { }   // never touch the real WidgetCenter under test
        )

        // A disruptive observer: it runs on every event and throws (caught), proving the
        // coordinator neither awaits nor depends on an observer's success.
        let box = Box()
        func throwingWork() throws { throw NotificationIntegrationError.schedulingFailed }

        coordinator.onLifecycleEvent = { [weak calendar, weak notifications, weak widgetWriter] event in
            calendar?.handle(event)
            notifications?.handle(event)
            widgetWriter?.handle(event)
            box.count += 1
            try? throwingWork()
        }
        coordinator.onMeaningfulTransition = { [weak widgetWriter] in widgetWriter?.update() }

        return Rig(container: container, clock: clock, coordinator: coordinator,
                   config: config, observerCalls: box)
    }

    private func drain() async { try? await Task.sleep(for: .milliseconds(50)) }

    @Test("A full session runs to completion while every integration fails")
    func fullSessionCompletesDespiteFailures() async throws {
        let rig = try makeFailingRig(focus: 10, total: 1)

        let session = try #require(try rig.coordinator.startSession(configuration: rig.config))
        #expect(rig.coordinator.engine.state == .running)
        await drain()

        // Pause / resume through failing integrations.
        try rig.coordinator.pause()
        #expect(rig.coordinator.engine.state == .paused)
        try rig.coordinator.resume()
        #expect(rig.coordinator.engine.state == .running)
        await drain()

        // Advance past the whole plan (focus + trailing break); one tick completes it.
        let total = session.orderedIntervals.reduce(0) { $0 + $1.plannedDuration }
        rig.clock.advance(by: total + 1)
        try rig.coordinator.tick()

        #expect(rig.coordinator.engine.state == .completed)
        await drain()

        // The persisted session is correct and complete — no integration corrupted it.
        let persisted = try #require(try makeSessionRepository(rig.container).allSessions().first)
        #expect(persisted.status == .completed)
        #expect(persisted.orderedIntervals.allSatisfy { $0.status == .completed })
        // The disruptive observer really did run (and throw, caught) on each transition.
        #expect(rig.observerCalls.count >= 2)
    }

    @Test("Stop preserves history while every integration fails")
    func stopPreservesHistoryDespiteFailures() async throws {
        let rig = try makeFailingRig(focus: 100, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        await drain()

        rig.clock.advance(by: 40)
        try rig.coordinator.tick()          // still within the first focus interval
        try rig.coordinator.stop()
        await drain()

        #expect(rig.coordinator.engine.state == .cancelled)
        let persisted = try #require(try makeSessionRepository(rig.container).allSessions().first)
        #expect(persisted.status == .cancelled)          // stop is never a delete
        #expect(persisted.orderedIntervals.isEmpty == false)
    }
}
