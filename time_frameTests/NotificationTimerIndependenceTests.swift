//
//  NotificationTimerIndependenceTests.swift
//  time_frameTests
//
//  The central Milestone 7 guarantee: notifications are an optional representation and
//  a notification failure can NEVER stop or corrupt a timer (§62, ADR-042). It also
//  proves notifications and Calendar are independent — a failure in one never affects
//  the other (§63).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Notification / timer independence")
struct NotificationTimerIndependenceTests {

    // MARK: Timer is unaffected by notification failures (§62)

    @Test("The timer starts even when notification scheduling fails")
    func timerStartsWhenScheduleFails() async throws {
        let rig = try makeNotificationRig(focus: 100, total: 1)
        await rig.notifications.refreshAuthorization()
        rig.service.failSchedule = .schedulingFailed

        let session = try rig.coordinator.startSession(configuration: rig.config)
        // Immediately — before any notification work — the timer is authoritative.
        #expect(session != nil)
        #expect(rig.coordinator.engine.state == .running)

        await drainNotifications()
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.service.pendingCount == 0) // scheduling failed, but timer is fine
        // The failure was captured as a non-blocking status, never rethrown.
        #expect(rig.notifications.lastErrorMessage != nil)
    }

    @Test("Pause/resume/stop all work when scheduling keeps failing")
    func controlsWorkWhenScheduleFails() async throws {
        let rig = try makeNotificationRig(focus: 100, total: 2)
        await rig.notifications.refreshAuthorization()
        rig.service.failSchedule = .schedulingFailed

        try rig.coordinator.startSession(configuration: rig.config)
        try rig.coordinator.pause()
        #expect(rig.coordinator.engine.state == .paused)
        try rig.coordinator.resume()
        #expect(rig.coordinator.engine.state == .running)
        try rig.coordinator.skip()
        try rig.coordinator.stop()
        #expect(rig.coordinator.engine.state == .cancelled)
        await drainNotifications()
    }

    @Test("The timer is fully functional when notification permission is denied")
    func timerFunctionalWhenDenied() async throws {
        let rig = try makeNotificationRig(status: .denied, focus: 100, total: 1)
        await rig.notifications.refreshAuthorization()

        let session = try rig.coordinator.startSession(configuration: rig.config)
        #expect(rig.coordinator.engine.state == .running)
        await drainNotifications()
        #expect(rig.service.pendingCount == 0) // nothing scheduled without permission
        #expect(session != nil)

        try rig.coordinator.pause()
        try rig.coordinator.resume()
        try rig.coordinator.stop()
        #expect(rig.coordinator.engine.state == .cancelled)
    }

    @Test("Completion with a scheduling failure still completes the session cleanly")
    func completionWithFailure() async throws {
        let rig = try makeNotificationRig(focus: 10, total: 1)
        await rig.notifications.refreshAuthorization()
        try rig.coordinator.startSession(configuration: rig.config)
        rig.service.failSchedule = .schedulingFailed
        rig.clock.advance(by: 100)
        try rig.coordinator.tick()
        #expect(rig.coordinator.engine.state == .completed)
        await drainNotifications()
        // History/engine unaffected by the failed completion notification (§77).
        #expect(rig.coordinator.activeSession?.isCompleted == true)
    }

    // MARK: Calendar / notification independence (§63)

    @Test("A notification failure never prevents Calendar from recording the session")
    func notificationFailureDoesNotAffectCalendar() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 100, total: 1)

        // Calendar (succeeds) + Notifications (fails), both subscribed to the same seam.
        let calDefaults = makeScratchDefaults()
        let calPrefs = CalendarPreferencesStore(defaults: calDefaults)
        calPrefs.isEnabled = true
        calPrefs.creationTrigger = .both
        let calService = FakeCalendarService(status: .fullAccess)
        let calendar = CalendarCoordinator(service: calService, preferences: calPrefs,
                                           records: CalendarEventRecordStore(defaults: calDefaults))

        let noteService = FakeNotificationService(status: .authorized)
        noteService.failSchedule = .schedulingFailed
        let notePrefs = NotificationPreferencesStore(defaults: makeScratchDefaults())
        notePrefs.isEnabled = true
        let notifications = NotificationCoordinator(scheduler: noteService, preferences: notePrefs)
        await notifications.refreshAuthorization()

        coordinator.onLifecycleEvent = { [weak calendar, weak notifications] event in
            calendar?.handle(event)
            notifications?.handle(event)
        }

        let session = try coordinator.startSession(configuration: config)
        await drainNotifications()

        // Calendar recorded the session even though notifications failed.
        #expect(calService.createCount == 1)
        #expect(calendar.records.record(for: session!.id) != nil)
        #expect(noteService.pendingCount == 0)
        #expect(coordinator.engine.state == .running)
    }

    @Test("A Calendar failure never prevents notifications from scheduling")
    func calendarFailureDoesNotAffectNotifications() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 100, total: 1)

        let calDefaults = makeScratchDefaults()
        let calPrefs = CalendarPreferencesStore(defaults: calDefaults)
        calPrefs.isEnabled = true
        calPrefs.creationTrigger = .both
        let calService = FakeCalendarService(status: .fullAccess)
        calService.failCreate = .saveFailed
        let calendar = CalendarCoordinator(service: calService, preferences: calPrefs,
                                           records: CalendarEventRecordStore(defaults: calDefaults))

        let noteService = FakeNotificationService(status: .authorized)
        let notePrefs = NotificationPreferencesStore(defaults: makeScratchDefaults())
        notePrefs.isEnabled = true
        let notifications = NotificationCoordinator(scheduler: noteService, preferences: notePrefs)
        await notifications.refreshAuthorization()

        coordinator.onLifecycleEvent = { [weak calendar, weak notifications] event in
            calendar?.handle(event)
            notifications?.handle(event)
        }

        let session = try coordinator.startSession(configuration: config)
        await drainNotifications()

        // Notifications scheduled even though Calendar failed.
        #expect(noteService.pendingCount == 1)
        #expect(calendar.records.record(for: session!.id) == nil)
        #expect(coordinator.engine.state == .running)
    }
}
