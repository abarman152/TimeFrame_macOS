//
//  NotificationCoordinatorTests.swift
//  time_frameTests
//
//  The coordinator translates real lifecycle transitions into scheduling operations:
//  start schedules the upcoming transition, pause/stop cancel, resume/skip reschedule,
//  completion delivers exactly one completion notification, and actions route back
//  through SessionCoordinator (§55–§60/§64). All via the FakeNotificationService.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Notification coordinator")
struct NotificationCoordinatorTests {

    private func authorizedRig(
        focus: TimeInterval = 100, total: Int = 1, before: Int = 4, short: TimeInterval = 5, long: TimeInterval = 15
    ) async throws -> NotificationRig {
        let rig = try makeNotificationRig(focus: focus, short: short, long: long, before: before, total: total)
        await rig.notifications.refreshAuthorization() // adopt the fake's .authorized status
        return rig
    }

    // MARK: Authorization (§53)

    @Test("Requesting authorization from not-determined grants it")
    func requestGrants() async throws {
        let rig = try makeNotificationRig(status: .notDetermined)
        rig.service.grantsOnRequest = .authorized
        let status = await rig.notifications.requestAuthorization()
        #expect(status == .authorized)
        #expect(rig.notifications.authorizationStatus == .authorized)
    }

    @Test("A denied request leaves the status denied")
    func requestDenied() async throws {
        let rig = try makeNotificationRig(status: .notDetermined)
        rig.service.grantsOnRequest = .denied
        let status = await rig.notifications.requestAuthorization()
        #expect(status == .denied)
        #expect(rig.notifications.status == .permissionDenied)
    }

    // MARK: Start schedules the upcoming transition (§55)

    @Test("Starting a single-focus session schedules exactly one transition")
    func startSchedulesOneTransition() async throws {
        let rig = try await authorizedRig(focus: 100, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        await drainNotifications()
        #expect(rig.service.pending(ofCategory: .shortBreakStarted).count == 1)
        #expect(rig.service.pendingCount == 1)
    }

    @Test("Ticks with no transition never schedule more notifications")
    func noPerTickScheduling() async throws {
        let rig = try await authorizedRig(focus: 100, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        await drainNotifications()
        let baseline = rig.service.scheduleCount
        for _ in 0..<5 { try rig.coordinator.tick() }
        await drainNotifications()
        #expect(rig.service.scheduleCount == baseline)
        #expect(rig.service.pendingCount == 1)
    }

    @Test("Nothing is scheduled when the integration is disabled")
    func disabledSchedulesNothing() async throws {
        let rig = try makeNotificationRig(enabled: false, focus: 100, total: 1)
        await rig.notifications.refreshAuthorization()
        try rig.coordinator.startSession(configuration: rig.config)
        await drainNotifications()
        #expect(rig.service.pendingCount == 0)
        #expect(rig.coordinator.engine.state == .running)
    }

    // MARK: Pause / resume (§56/§57)

    @Test("Pausing cancels the pending transition; resuming reschedules it")
    func pauseCancelsResumeReschedules() async throws {
        let rig = try await authorizedRig(focus: 100, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        await drainNotifications()
        #expect(rig.service.pendingCount == 1)

        try rig.coordinator.pause()
        await drainNotifications()
        #expect(rig.service.pendingCount == 0) // stale transition removed (§25)

        rig.clock.advance(by: 20)
        try rig.coordinator.resume()
        await drainNotifications()
        // Rescheduled from the authoritative remaining time (§26/§57).
        #expect(rig.service.pending(ofCategory: .shortBreakStarted).count == 1)
    }

    // MARK: Skip (§58)

    @Test("Skipping cancels the old transition and schedules the next phase")
    func skipReschedules() async throws {
        // Two focus sessions so a skip lands mid-plan (still running).
        let rig = try await authorizedRig(focus: 100, total: 2)
        try rig.coordinator.startSession(configuration: rig.config)
        await drainNotifications()
        let before = rig.service.pendingDescriptors.map(\.identifier).sorted()

        try rig.coordinator.skip() // focus 0 → short break 1
        await drainNotifications()
        let after = rig.service.pendingDescriptors.map(\.identifier).sorted()
        // The set changed (old interval-0 transition gone, rescheduled from index 1).
        #expect(before != after)
        #expect(rig.coordinator.engine.state == .running)
        // No notification remains that announces interval 1 firing at the *old* time —
        // everything is rescheduled from the new current interval.
        #expect(rig.service.pendingCount >= 1)
    }

    // MARK: Stop (§59)

    @Test("Stopping cancels all of the session's pending notifications")
    func stopCancelsAll() async throws {
        let rig = try await authorizedRig(focus: 100, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        await drainNotifications()
        #expect(rig.service.pendingCount > 0)

        try rig.coordinator.stop()
        await drainNotifications()
        #expect(rig.service.pendingCount == 0)
        #expect(rig.coordinator.engine.state == .cancelled)
    }

    // MARK: Completion (§60)

    @Test("Completion delivers exactly one completion notification and no transitions")
    func completionDelivered() async throws {
        let rig = try await authorizedRig(focus: 10, total: 1, short: 5)
        try rig.coordinator.startSession(configuration: rig.config)
        await drainNotifications()

        // Advance past the whole plan; one tick fast-forwards to completion.
        rig.clock.advance(by: 100)
        try rig.coordinator.tick()
        #expect(rig.coordinator.engine.state == .completed)
        await drainNotifications()

        #expect(rig.service.pending(ofCategory: .sessionCompleted).count == 1)
        #expect(rig.service.pending(ofCategory: .shortBreakStarted).count == 0)

        // A further tick must not deliver a duplicate completion.
        let completionSchedules = rig.service.scheduleCount
        try rig.coordinator.tick()
        await drainNotifications()
        #expect(rig.service.scheduleCount == completionSchedules)
    }

    // MARK: Master toggle (§17)

    @Test("Turning notifications off cancels all pending Time Frame notifications")
    func disablingCancelsPending() async throws {
        let rig = try await authorizedRig(focus: 100, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        await drainNotifications()
        #expect(rig.service.pendingCount > 0)

        rig.notifications.setEnabled(false, activeSession: rig.coordinator.currentLifecycleContext(),
                                     isRunning: rig.coordinator.engine.state == .running)
        await drainNotifications()
        #expect(rig.service.pendingCount == 0)
        #expect(rig.coordinator.engine.state == .running) // timer untouched
    }

    // MARK: Actions route through SessionCoordinator (§37)

    @Test("A Pause action pauses the live session through the coordinator")
    func pauseActionRoutes() async throws {
        let rig = try await authorizedRig(focus: 100, total: 1)
        let session = try rig.coordinator.startSession(configuration: rig.config)
        await drainNotifications()

        rig.service.simulateAction(.init(action: .pause, sessionID: session?.id))
        #expect(rig.coordinator.engine.state == .paused)

        rig.service.simulateAction(.init(action: .resume, sessionID: session?.id))
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("An action for a stale session is ignored, never crashes")
    func staleActionIgnored() async throws {
        let rig = try await authorizedRig(focus: 100, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        await drainNotifications()
        // Unknown session id → ignored; the live session keeps running.
        rig.service.simulateAction(.init(action: .stop, sessionID: UUID()))
        #expect(rig.coordinator.engine.state == .running)
    }
}
