//
//  CalendarTimerIndependenceTests.swift
//  time_frameTests
//
//  The central Milestone 6 guarantee: Calendar is an optional representation, never
//  the source of truth, and a Calendar failure can NEVER stop or corrupt a timer
//  (§71/§72, ADR-035). A real SessionCoordinator is wired to a CalendarCoordinator
//  through the pure lifecycle-event seam, with an intentionally failing calendar
//  service, and the timer is asserted to be unaffected.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Calendar / timer independence")
struct CalendarTimerIndependenceTests {

    /// A wired pair: a real timer coordinator whose lifecycle events feed a calendar
    /// coordinator backed by a fake service.
    private struct Rig {
        let container: ModelContainer
        let clock: MockTimeSource
        let coordinator: SessionCoordinator
        let calendar: CalendarCoordinator
        let service: FakeCalendarService
        let config: PomodoroConfiguration
    }

    private func makeRig(
        status: CalendarAuthorizationStatus = .fullAccess,
        enabled: Bool = true,
        trigger: CalendarCreationTrigger = .both,
        focus: TimeInterval = 10,
        total: Int = 1
    ) throws -> Rig {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: focus, total: total)

        let defaults = makeScratchDefaults()
        let prefs = CalendarPreferencesStore(defaults: defaults)
        prefs.isEnabled = enabled
        prefs.creationTrigger = trigger
        let service = FakeCalendarService(status: status)
        let calendar = CalendarCoordinator(
            service: service,
            preferences: prefs,
            records: CalendarEventRecordStore(defaults: defaults)
        )
        coordinator.onLifecycleEvent = { [weak calendar] event in calendar?.handle(event) }
        return Rig(container: container, clock: clock, coordinator: coordinator,
                   calendar: calendar, service: service, config: config)
    }

    /// Lets deferred calendar tasks run. This drains async calendar work only; the
    /// timer engine remains deterministic and never waits real time.
    private func drainCalendar() async {
        try? await Task.sleep(for: .milliseconds(40))
    }

    // MARK: Timer is unaffected by calendar failures (§71)

    @Test("The timer starts even when calendar event creation fails")
    func timerStartsWhenCreateFails() async throws {
        let rig = try makeRig()
        rig.service.failCreate = .saveFailed

        let session = try rig.coordinator.startSession(configuration: rig.config)
        // Immediately — before any calendar work — the timer is authoritative.
        #expect(session != nil)
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.coordinator.activeSession != nil)

        await drainCalendar()
        // Calendar failed, so no association was stored — but the timer is fine.
        #expect(rig.calendar.records.record(for: session!.id) == nil)
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("The timer keeps running when a calendar update fails")
    func timerRunsWhenUpdateFails() async throws {
        let rig = try makeRig(focus: 100)
        try rig.coordinator.startSession(configuration: rig.config)
        await drainCalendar()
        rig.service.failAdjust = .updateFailed

        // A pause triggers a calendar end-adjust, which fails — timer unaffected.
        try rig.coordinator.pause()
        #expect(rig.coordinator.engine.state == .paused)
        try rig.coordinator.resume()
        #expect(rig.coordinator.engine.state == .running)
        await drainCalendar()
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("The timer is fully functional when calendar permission is denied")
    func timerFunctionalWhenDenied() async throws {
        let rig = try makeRig(status: .denied)
        let session = try rig.coordinator.startSession(configuration: rig.config)
        #expect(rig.coordinator.engine.state == .running)
        await drainCalendar()
        #expect(rig.service.createCount == 0)
        #expect(rig.calendar.records.record(for: session!.id) == nil)

        // Pause/resume/stop all work normally.
        try rig.coordinator.pause()
        try rig.coordinator.resume()
        try rig.coordinator.stop()
        #expect(rig.coordinator.engine.state == .cancelled)
    }

    // MARK: Calendar reflects the session when it can (§30)

    @Test("Starting a session creates one calendar event with the actual start time")
    func startCreatesEvent() async throws {
        let rig = try makeRig(focus: 25 * 60, total: 1)
        let startInstant = rig.clock.now()
        let session = try rig.coordinator.startSession(configuration: rig.config)
        await drainCalendar()

        #expect(rig.service.createCount == 1)
        let record = rig.calendar.records.record(for: session!.id)
        #expect(record?.references.count == 1)
        // The single event spans the actual start → projected end (the whole
        // session's total duration, including its trailing break).
        let expectedTotal = session!.orderedIntervals.reduce(0) { $0 + $1.plannedDuration }
        if let ref = record?.references.first, let draft = rig.service.storedEvents[ref.eventIdentifier] {
            #expect(draft.startDate == startInstant)
            #expect(draft.endDate == startInstant.addingTimeInterval(expectedTotal))
        } else {
            Issue.record("Expected a stored event for the session")
        }
    }

    @Test("No event is created when the trigger excludes session start")
    func noEventWhenTriggerManualOnly() async throws {
        let rig = try makeRig(trigger: .manual)
        let session = try rig.coordinator.startSession(configuration: rig.config)
        await drainCalendar()
        #expect(rig.service.createCount == 0)
        #expect(rig.calendar.records.record(for: session!.id) == nil)
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("No event is created when the integration is disabled")
    func noEventWhenDisabled() async throws {
        let rig = try makeRig(enabled: false)
        let session = try rig.coordinator.startSession(configuration: rig.config)
        await drainCalendar()
        #expect(rig.service.createCount == 0)
        #expect(rig.calendar.records.record(for: session!.id) == nil)
    }

    // MARK: Meaningful transitions only — never per tick (§53)

    @Test("Ticks with no state change never write to the calendar")
    func noPerTickUpdates() async throws {
        let rig = try makeRig(focus: 100, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        await drainCalendar()
        let baselineAdjust = rig.service.adjustCount

        // Several ticks with no elapsed time → no transition → no calendar writes.
        for _ in 0..<5 { try rig.coordinator.tick() }
        await drainCalendar()
        #expect(rig.service.adjustCount == baselineAdjust)
        #expect(rig.service.createCount == 1)
    }

    // MARK: Stop / completion (§35/§36)

    @Test("Stopping keeps the event and reflects the actual end (never deletes it)")
    func stopKeepsEvent() async throws {
        let rig = try makeRig(focus: 100, total: 1)
        let session = try rig.coordinator.startSession(configuration: rig.config)
        await drainCalendar()
        rig.clock.advance(by: 23)
        try rig.coordinator.stop()
        await drainCalendar()

        #expect(rig.service.deleteCount == 0)          // history preserved
        #expect(rig.service.savedEventCount == 1)
        #expect(rig.service.adjustCount >= 1)
        #expect(rig.calendar.records.record(for: session!.id) != nil)
    }

    @Test("Completion adjusts the single event exactly once")
    func completionAdjustsEvent() async throws {
        let rig = try makeRig(focus: 10, total: 1)
        let session = try rig.coordinator.startSession(configuration: rig.config)
        await drainCalendar()

        // Advance past every interval (focus + trailing break); one synchronize
        // fast-forwards through all of them to completion.
        let total = session!.orderedIntervals.reduce(0) { $0 + $1.plannedDuration }
        rig.clock.advance(by: total + 1)
        try rig.coordinator.tick() // engine completes
        #expect(rig.coordinator.engine.state == .completed)
        await drainCalendar()
        #expect(rig.service.savedEventCount == 1)
        #expect(rig.service.adjustCount == 1)
        #expect(rig.calendar.records.record(for: session!.id) != nil)
    }

    // MARK: External deletion (§55/§79)

    @Test("An externally deleted event is forgotten, not silently recreated")
    func externalDeletionHandled() async throws {
        let rig = try makeRig(focus: 100, total: 1)
        let session = try rig.coordinator.startSession(configuration: rig.config)
        await drainCalendar()
        guard let ref = rig.calendar.records.record(for: session!.id)?.references.first else {
            Issue.record("Expected an event"); return
        }
        rig.service.removeExternally(ref)

        // A later transition finds the event gone and clears the association.
        try rig.coordinator.stop()
        await drainCalendar()
        #expect(rig.calendar.records.record(for: session!.id) == nil)
        #expect(rig.coordinator.engine.state == .cancelled) // timer unaffected
    }
}
