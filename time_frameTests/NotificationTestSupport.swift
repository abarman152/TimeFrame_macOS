//
//  NotificationTestSupport.swift
//  time_frameTests
//
//  A wired rig: a real `SessionCoordinator` whose lifecycle events feed a
//  `NotificationCoordinator` backed by a `FakeNotificationService`, exactly as the app
//  wires them. Lets the notification tests exercise real transitions deterministically
//  without a real notification center (§52/§64).
//

import Foundation
import SwiftData
@testable import time_frame

@MainActor
struct NotificationRig {
    let container: ModelContainer
    let clock: MockTimeSource
    let coordinator: SessionCoordinator
    let notifications: NotificationCoordinator
    let service: FakeNotificationService
    let config: PomodoroConfiguration
}

@MainActor
func makeNotificationRig(
    status: NotificationAuthorizationStatus = .authorized,
    enabled: Bool = true,
    focus: TimeInterval = 10,
    short: TimeInterval = 5,
    long: TimeInterval = 15,
    before: Int = 4,
    total: Int = 1
) throws -> NotificationRig {
    let container = try makeInMemoryContainer()
    let clock = MockTimeSource()
    let coordinator = makeCoordinator(container, clock: clock)
    let config = try insertConfiguration(
        container, focus: focus, short: short, long: long, before: before, total: total)

    let defaults = makeScratchDefaults()
    let prefs = NotificationPreferencesStore(defaults: defaults)
    prefs.isEnabled = enabled
    let service = FakeNotificationService(status: status)
    let notifications = NotificationCoordinator(scheduler: service, preferences: prefs)

    // Wire exactly as the app does.
    notifications.performAction = { [weak coordinator] action in
        guard let coordinator else { return }
        switch action {
        case .pause: try? coordinator.pause()
        case .resume: try? coordinator.resume()
        case .skip: try? coordinator.skip()
        case .stop: try? coordinator.stop()
        case .open: break
        }
    }
    notifications.timerStateProvider = { [weak coordinator] in
        (coordinator?.activeSession?.id, coordinator?.engine.state ?? .idle)
    }
    coordinator.onLifecycleEvent = { [weak notifications] event in notifications?.handle(event) }

    return NotificationRig(container: container, clock: clock, coordinator: coordinator,
                           notifications: notifications, service: service, config: config)
}

/// Lets deferred notification tasks run. Drains async scheduling only; the timer engine
/// remains deterministic and never waits real time.
@MainActor
func drainNotifications() async {
    try? await Task.sleep(for: .milliseconds(40))
}
