//
//  NotificationRecoveryTests.swift
//  time_frameTests
//
//  On relaunch, the TimerEngine recovers the authoritative state; the notification
//  layer then cancels stale requests and schedules the next future transitions without
//  duplicates and without resurrecting a finished session (§31/§61).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Notification recovery")
struct NotificationRecoveryTests {

    /// Persists a running session in `container`, then returns a fresh coordinator that
    /// has recovered it — simulating an app relaunch.
    private func relaunch(
        _ container: ModelContainer, clock: MockTimeSource, focus: TimeInterval, total: Int
    ) throws -> SessionCoordinator {
        let recovered = makeCoordinator(container, clock: clock)
        _ = try recovered.recover()
        return recovered
    }

    @Test("Recovery schedules the next future transition for a still-running session")
    func recoverySchedulesNextTransition() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()

        // First launch: start a running session and persist it.
        let first = makeCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 100, total: 1)
        try first.startSession(configuration: config)

        // Relaunch: a fresh coordinator recovers the running session.
        let recovered = try relaunch(container, clock: clock, focus: 100, total: 1)
        #expect(recovered.engine.state == .running)

        // Wire a fresh notification coordinator and reconcile against the recovered state.
        let service = FakeNotificationService(status: .authorized)
        let prefs = NotificationPreferencesStore(defaults: makeScratchDefaults())
        prefs.isEnabled = true
        let notifications = NotificationCoordinator(scheduler: service, preferences: prefs)
        await notifications.refreshAuthorization()

        notifications.reconcileActiveSession(recovered.currentLifecycleContext(),
                                             isRunning: recovered.engine.state == .running)
        await drainNotifications()

        #expect(service.pending(ofCategory: .shortBreakStarted).count == 1)
    }

    @Test("Recovery cancels stale Time Frame notifications before rescheduling")
    func recoveryCancelsStale() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let first = makeCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 100, total: 1)
        let session = try first.startSession(configuration: config)

        let recovered = try relaunch(container, clock: clock, focus: 100, total: 1)

        let service = FakeNotificationService(status: .authorized)
        let prefs = NotificationPreferencesStore(defaults: makeScratchDefaults())
        prefs.isEnabled = true
        let notifications = NotificationCoordinator(scheduler: service, preferences: prefs)
        await notifications.refreshAuthorization()

        // Simulate a stale notification left over from before the relaunch.
        let stale = NotificationDescriptor(
            identifier: NotificationIdentifier.transition(sessionID: session!.id, intervalIndex: 99),
            content: NotificationContent(title: "Stale", subtitle: nil, body: "Old"),
            fireDate: Date().addingTimeInterval(9999),
            category: .shortBreakStarted, sound: .none, showsActions: false, sessionID: session!.id)
        try await service.schedule(stale)
        #expect(await service.pendingIdentifiers().contains(stale.identifier))

        notifications.reconcileActiveSession(recovered.currentLifecycleContext(),
                                             isRunning: recovered.engine.state == .running)
        await drainNotifications()

        // The stale request is gone; a fresh one is scheduled; no duplicates.
        #expect(await service.pendingIdentifiers().contains(stale.identifier) == false)
        #expect(service.pending(ofCategory: .shortBreakStarted).count == 1)
    }

    @Test("A completed session is never resurrected with notifications on relaunch")
    func completedSessionNotResurrected() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let first = makeCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 10, total: 1)
        try first.startSession(configuration: config)
        // Let the whole session elapse and complete.
        clock.advance(by: 1000)
        try first.tick()
        #expect(first.engine.state == .completed)

        // Relaunch: there is no recoverable (running/paused) session.
        let recovered = makeCoordinator(container, clock: clock)
        let didRecover = try recovered.recover()
        #expect(didRecover == false)

        let service = FakeNotificationService(status: .authorized)
        let prefs = NotificationPreferencesStore(defaults: makeScratchDefaults())
        prefs.isEnabled = true
        let notifications = NotificationCoordinator(scheduler: service, preferences: prefs)
        await notifications.refreshAuthorization()

        notifications.reconcileActiveSession(recovered.currentLifecycleContext(),
                                             isRunning: recovered.engine.state == .running)
        await drainNotifications()
        #expect(service.pendingCount == 0)
    }
}
