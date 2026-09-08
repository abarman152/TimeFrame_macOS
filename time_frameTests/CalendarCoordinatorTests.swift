//
//  CalendarCoordinatorTests.swift
//  time_frameTests
//
//  Authorization, calendar selection, and event lifecycle (create/update/delete,
//  duplicate prevention, missing events) via the FakeCalendarService — no real
//  Calendar (§64/§68/§69/§70).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Calendar coordinator")
struct CalendarCoordinatorTests {

    private func makeCoordinator(
        _ service: FakeCalendarService,
        enabled: Bool = true,
        style: CalendarEventStyle = .singlePlan
    ) -> CalendarCoordinator {
        let defaults = makeScratchDefaults()
        let prefs = CalendarPreferencesStore(defaults: defaults)
        prefs.isEnabled = enabled
        prefs.eventStyle = style
        let records = CalendarEventRecordStore(defaults: defaults)
        return CalendarCoordinator(service: service, preferences: prefs, records: records)
    }

    private func makePlan(_ container: ModelContainer) throws -> SessionPlan {
        let config = try insertConfiguration(container)
        return try makePlanRepository(container).create(simplePlanDraft(config))
    }

    // MARK: Authorization (§64)

    @Test("Requesting access from not-determined grants full access and loads calendars")
    func requestGrantsAccess() async {
        let service = FakeCalendarService(status: .notDetermined, grantsOnRequest: .fullAccess)
        let coordinator = makeCoordinator(service)
        let status = await coordinator.requestAccess()
        #expect(status == .fullAccess)
        #expect(coordinator.authorizationStatus == .fullAccess)
        #expect(coordinator.availableCalendars.count == 2)
    }

    @Test("A denied request leaves status denied and no calendars")
    func requestDenied() async {
        let service = FakeCalendarService(status: .notDetermined, grantsOnRequest: .denied)
        let coordinator = makeCoordinator(service)
        let status = await coordinator.requestAccess()
        #expect(status == .denied)
        #expect(coordinator.availableCalendars.isEmpty)
        #expect(coordinator.syncStatus == .permissionDenied)
    }

    @Test("Restricted and write-only are treated as insufficient")
    func insufficientStatuses() {
        #expect(CalendarAuthorizationStatus.restricted.isSufficient == false)
        #expect(CalendarAuthorizationStatus.writeOnly.isSufficient == false)
        #expect(CalendarAuthorizationStatus.denied.isSufficient == false)
        #expect(CalendarAuthorizationStatus.fullAccess.isSufficient == true)
    }

    // MARK: Calendar selection (§19/§20)

    @Test("A stored default calendar that no longer exists is cleared")
    func staleDefaultCalendarCleared() async {
        let service = FakeCalendarService(status: .fullAccess)
        let coordinator = makeCoordinator(service)
        coordinator.preferences.defaultCalendarIdentifier = "cal-gone"
        await coordinator.loadCalendars()
        #expect(coordinator.preferences.defaultCalendarIdentifier == nil)
    }

    // MARK: Event creation (§65/§66)

    @Test("Adding a plan creates one event and stores the association")
    func addPlanSingle() async throws {
        let container = try makeInMemoryContainer()
        let plan = try makePlan(container)
        let service = FakeCalendarService(status: .fullAccess)
        let coordinator = makeCoordinator(service, style: .singlePlan)

        let ok = await coordinator.addPlan(plan, startDate: Date(), style: .singlePlan,
                                           calendarIdentifier: "cal-work", titleOverride: nil)
        #expect(ok)
        #expect(service.createCount == 1)
        #expect(coordinator.record(for: plan)?.references.count == 1)
        #expect(coordinator.syncStatus == .synced)
    }

    @Test("Per-interval style creates one event per interval")
    func addPlanPerInterval() async throws {
        let container = try makeInMemoryContainer()
        let plan = try makePlan(container)
        let service = FakeCalendarService(status: .fullAccess)
        let coordinator = makeCoordinator(service, style: .perInterval)

        _ = await coordinator.addPlan(plan, startDate: Date(), style: .perInterval,
                                      calendarIdentifier: nil, titleOverride: nil)
        #expect(service.createCount == plan.orderedItems.count)
        #expect(coordinator.record(for: plan)?.references.count == plan.orderedItems.count)
    }

    // MARK: Duplicate prevention (§24/§68)

    @Test("Re-adding a plan replaces its events rather than duplicating")
    func reAddReplaces() async throws {
        let container = try makeInMemoryContainer()
        let plan = try makePlan(container)
        let service = FakeCalendarService(status: .fullAccess)
        let coordinator = makeCoordinator(service)

        _ = await coordinator.addPlan(plan, startDate: Date(), style: .singlePlan, calendarIdentifier: nil, titleOverride: nil)
        _ = await coordinator.addPlan(plan, startDate: Date(), style: .singlePlan, calendarIdentifier: nil, titleOverride: nil)

        // Two creates, one delete of the old event → exactly one live event remains.
        #expect(service.createCount == 2)
        #expect(service.deleteCount == 1)
        #expect(service.savedEventCount == 1)
        #expect(coordinator.record(for: plan)?.references.count == 1)
    }

    // MARK: Failure handling (§70)

    @Test("A create failure reports an error and stores no association")
    func createFailureIsolated() async throws {
        let container = try makeInMemoryContainer()
        let plan = try makePlan(container)
        let service = FakeCalendarService(status: .fullAccess)
        service.failCreate = .saveFailed
        let coordinator = makeCoordinator(service)

        let ok = await coordinator.addPlan(plan, startDate: Date(), style: .singlePlan, calendarIdentifier: nil, titleOverride: nil)
        #expect(ok == false)
        #expect(coordinator.record(for: plan) == nil)
        #expect(coordinator.lastErrorMessage != nil)
    }

    @Test("Adding without sufficient access fails without creating anything")
    func addWithoutAccess() async throws {
        let container = try makeInMemoryContainer()
        let plan = try makePlan(container)
        let service = FakeCalendarService(status: .denied)
        let coordinator = makeCoordinator(service)

        let ok = await coordinator.addPlan(plan, startDate: Date(), style: .singlePlan, calendarIdentifier: nil, titleOverride: nil)
        #expect(ok == false)
        #expect(service.createCount == 0)
        #expect(coordinator.syncStatus == .permissionDenied)
    }

    // MARK: Explicit deletion (§70)

    @Test("Removing events for an owner deletes them and forgets the association")
    func removeEvents() async throws {
        let container = try makeInMemoryContainer()
        let plan = try makePlan(container)
        let service = FakeCalendarService(status: .fullAccess)
        let coordinator = makeCoordinator(service, style: .perInterval)

        _ = await coordinator.addPlan(plan, startDate: Date(), style: .perInterval, calendarIdentifier: nil, titleOverride: nil)
        let count = plan.orderedItems.count
        await coordinator.removeEvents(forOwner: plan.id)
        #expect(service.deleteCount == count)
        #expect(coordinator.record(for: plan) == nil)
        #expect(service.savedEventCount == 0)
    }
}
