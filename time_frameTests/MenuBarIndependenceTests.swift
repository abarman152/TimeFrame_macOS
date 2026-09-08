//
//  MenuBarIndependenceTests.swift
//  time_frameTests
//
//  The menu bar shares only the one `SessionCoordinator`; it is independent of the
//  Calendar and Notification integrations (§37/§38/§61/§62). A failure in either of those
//  can never break the menu bar or the timer, and the menu bar stays robust for awkward
//  sessions — empty task names, a deleted configuration (§60/§93).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Menu bar independence & robustness")
struct MenuBarIndependenceTests {

    /// A coordinator fanned out to a failing notification coordinator, a failing calendar
    /// coordinator, and the menu bar — exactly the app's wiring, but every integration
    /// broken. Returns the pieces the tests assert on.
    private struct Combined {
        let container: ModelContainer
        let clock: MockTimeSource
        let coordinator: SessionCoordinator
        let menuBar: MenuBarCoordinator
        let config: PomodoroConfiguration
        // Retained so the weakly-captured fan-out closure keeps delivering events.
        let notifications: NotificationCoordinator
        let calendar: CalendarCoordinator
        let notificationService: FakeNotificationService
    }

    private func makeCombined() async throws -> Combined {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 1500, total: 4)

        // Notifications that fail every schedule (authorized, so it genuinely attempts).
        let nDefaults = makeScratchDefaults()
        let nPrefs = NotificationPreferencesStore(defaults: nDefaults)
        nPrefs.isEnabled = true
        let nService = FakeNotificationService(status: .authorized)
        nService.failSchedule = .schedulingFailed
        let notifications = NotificationCoordinator(scheduler: nService, preferences: nPrefs)
        await notifications.refreshAuthorization()

        // Calendar that fails every create.
        let cDefaults = makeScratchDefaults()
        let cPrefs = CalendarPreferencesStore(defaults: cDefaults)
        cPrefs.isEnabled = true
        let cService = FakeCalendarService(status: .fullAccess)
        cService.failCreate = .saveFailed
        let calendar = CalendarCoordinator(
            service: cService, preferences: cPrefs, records: CalendarEventRecordStore(defaults: cDefaults))

        let menuBar = MenuBarCoordinator(
            session: coordinator, preferences: MenuBarPreferencesStore(defaults: makeScratchDefaults()))

        // Fan one lifecycle event out to both integrations, exactly as the app does.
        coordinator.onLifecycleEvent = { [weak calendar, weak notifications] event in
            calendar?.handle(event)
            notifications?.handle(event)
        }

        return Combined(container: container, clock: clock, coordinator: coordinator,
                        menuBar: menuBar, config: config,
                        notifications: notifications, calendar: calendar, notificationService: nService)
    }

    // MARK: Failure isolation (§61/§62)

    @Test("A failing notification and calendar integration never break the menu bar")
    func integrationsFailingMenuBarWorks() async throws {
        let rig = try await makeCombined()

        try rig.coordinator.startSession(configuration: rig.config, taskName: "Ship")
        // Let the deferred (failing) integration work run; it must not throw toward us.
        try? await Task.sleep(for: .milliseconds(40))

        // The menu bar reflects the authoritative timer regardless of the failures.
        #expect(rig.menuBar.presentation.situation == .running)
        #expect(rig.menuBar.presentation.taskName == "Ship")
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("A menu-bar control still drives the timer while integrations are failing")
    func menuBarControlsWorkWhileIntegrationsFail() async throws {
        let rig = try await makeCombined()
        try rig.coordinator.startSession(configuration: rig.config)
        try? await Task.sleep(for: .milliseconds(40))

        rig.menuBar.pause()
        #expect(rig.coordinator.engine.state == .paused)
        #expect(rig.menuBar.presentation.situation == .paused)

        rig.menuBar.resume()
        #expect(rig.coordinator.engine.state == .running)
    }

    // MARK: Robustness (§60/§93)

    @Test("An empty task name projects safely")
    func emptyTaskName() throws {
        let rig = try makeMenuBarRig(focus: 1500, total: 4)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "")
        let state = rig.menuBar.presentation
        #expect(state.taskName == "")
        // Title is unaffected by the missing task name.
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: true) == "Focus 25:00")
    }

    @Test("Deleting the configuration mid-run leaves the frozen name intact")
    func deletedConfiguration() throws {
        let rig = try makeMenuBarRig(focus: 1500, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        #expect(rig.menuBar.presentation.configurationName == "Test")

        rig.container.mainContext.delete(rig.config)
        try rig.container.mainContext.save()

        // The session's frozen snapshot survives configuration deletion (§53).
        #expect(rig.menuBar.presentation.configurationName == "Test")
        #expect(rig.coordinator.engine.state == .running)
    }
}
