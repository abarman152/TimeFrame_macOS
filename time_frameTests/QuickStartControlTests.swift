//
//  QuickStartControlTests.swift
//  time_frameTests (Milestone 23)
//
//  The configurable Control Center quick-start control is a COMMAND surface over the ONE timer:
//  the user picks a saved configuration, and one tap starts exactly that configuration through the
//  existing single mutation seam. These tests prove — deterministically, with no WidgetKit host and
//  no real time — every part of that chain and its failure modes:
//
//    • the App Group catalog (descriptor/store) round-trips and degrades safely (Entity/Catalog);
//    • the entity query resolves stable ids, drops deleted ones, and filters by name (Entity);
//    • the app-side writer maps the authoritative repository into the catalog (Catalog);
//    • the pure presentation layer produces meaningful titles + VoiceOver phrasing (Accessibility);
//    • the quick-start routes through `WidgetControlActions.performQuickStart` →
//      `AppIntentSessionActions.startSession` → `SessionCoordinator`, starting the SELECTED
//      configuration, using the AUTHORITATIVE (renamed) values, failing safely when deleted / when a
//      session is already running / when the router is unavailable, and never duplicating a session
//      under rapid taps (Routing / Failure / Concurrency).
//

import Foundation
import Testing
@testable import time_frame

// MARK: - Entity, descriptor & query

@Suite("Quick-start — descriptor & entity")
struct QuickStartEntityTests {

    @Test("A descriptor formats a plural subtitle, and singular for one session")
    func subtitleFormatting() {
        let plural = QuickStartTimerDescriptor(id: UUID(), name: "Deep Work", focusDuration: 1500, defaultTotalSessions: 4)
        #expect(plural.subtitle == "25 min focus · 4 sessions")
        let singular = QuickStartTimerDescriptor(id: UUID(), name: "One", focusDuration: 600, defaultTotalSessions: 1)
        #expect(singular.subtitle == "10 min focus · 1 session")
    }

    @Test("A sub-minute focus still reads as at least 1 minute (never 0)")
    func subtitleMinimumMinute() {
        let tiny = QuickStartTimerDescriptor(id: UUID(), name: "Test", focusDuration: 10, defaultTotalSessions: 2)
        #expect(tiny.subtitle == "1 min focus · 2 sessions")
    }

    @Test("An entity carries the descriptor's stable id, name, and frozen subtitle")
    func entityFromDescriptor() {
        let id = UUID()
        let entity = QuickStartTimerEntity(descriptor:
            QuickStartTimerDescriptor(id: id, name: "Sprint", focusDuration: 1200, defaultTotalSessions: 3))
        #expect(entity.id == id)
        #expect(entity.name == "Sprint")
        #expect(entity.subtitle == "20 min focus · 3 sessions")
    }
}

@Suite("Quick-start — entity query resolution (pure)")
struct QuickStartEntityQueryTests {

    private func catalog() -> QuickStartCatalog {
        QuickStartCatalog(timers: [
            QuickStartTimerDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                      name: "Deep Work", focusDuration: 1500, defaultTotalSessions: 4),
            QuickStartTimerDescriptor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                      name: "Sprint", focusDuration: 1200, defaultTotalSessions: 3)
        ])
    }

    @Test("suggested returns every saved timer, in catalog order")
    func suggested() {
        let entities = QuickStartTimerEntityQuery.suggested(in: catalog())
        #expect(entities.map(\.name) == ["Deep Work", "Sprint"])
    }

    @Test("resolve maps ids, preserves request order, and drops deleted (unknown) ids")
    func resolvePreservesOrderAndDropsDeleted() {
        let known1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let known2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let deleted = UUID()
        let resolved = QuickStartTimerEntityQuery.resolve([known2, deleted, known1], in: catalog())
        #expect(resolved.map(\.name) == ["Sprint", "Deep Work"])   // order preserved, unknown dropped
    }

    @Test("A deleted configuration resolves to nothing (graceful)")
    func deletedResolvesEmpty() {
        #expect(QuickStartTimerEntityQuery.resolve([UUID()], in: catalog()).isEmpty)
    }

    @Test("matching filters by name, case-insensitively")
    func matchingByName() {
        #expect(QuickStartTimerEntityQuery.matching("deep", in: catalog()).map(\.name) == ["Deep Work"])
        #expect(QuickStartTimerEntityQuery.matching("SP", in: catalog()).map(\.name) == ["Sprint"])
        #expect(QuickStartTimerEntityQuery.matching("zzz", in: catalog()).isEmpty)
    }
}

// MARK: - Catalog store

@Suite("Quick-start — catalog store")
struct QuickStartCatalogStoreTests {

    private func volatileStore() -> QuickStartCatalogStore {
        QuickStartCatalogStore(defaults: UserDefaults(suiteName: "qs.tests.\(UUID().uuidString)")!)
    }

    @Test("write then read round-trips the catalog")
    func roundTrip() {
        let store = volatileStore()
        let catalog = QuickStartCatalog(timers: [
            QuickStartTimerDescriptor(id: UUID(), name: "Deep Work", focusDuration: 1500, defaultTotalSessions: 4)
        ])
        #expect(store.write(catalog))
        #expect(store.read() == catalog)
    }

    @Test("An unavailable suite is inert: read is nil, write is false")
    func unavailableIsInert() {
        let store = QuickStartCatalogStore(defaults: nil)
        #expect(!store.isAvailable)
        #expect(store.read() == nil)
        #expect(!store.write(.empty))
    }

    @Test("A forward-incompatible schema version is ignored on read")
    func incompatibleSchemaIgnored() {
        let store = volatileStore()
        // Persist a catalog stamped with a future schema version; the store must not trust it.
        let future = QuickStartCatalog(timers: [], schemaVersion: QuickStartCatalog.currentSchemaVersion + 1)
        #expect(store.write(future))
        #expect(store.read() == nil)
    }

    @Test("clear removes any stored catalog")
    func clearRemoves() {
        let store = volatileStore()
        #expect(store.write(QuickStartCatalog(timers: [
            QuickStartTimerDescriptor(id: UUID(), name: "X", focusDuration: 600, defaultTotalSessions: 1)
        ])))
        store.clear()
        #expect(store.read() == nil)
    }

    @Test("The catalog store and the widget projection store share the App Group but never collide")
    func distinctKeys() {
        #expect(QuickStartCatalogStore.storageKey != WidgetProjection.storageKey)
        // Same App Group suite for both surfaces — no new App Group is introduced.
        #expect(WidgetProjectionStore.appGroupIdentifier == "group.abirbarman.com.time-frame")
    }
}

// MARK: - App-side catalog writer

@Suite("Quick-start — catalog writer maps the authoritative repository")
@MainActor
struct QuickStartCatalogWriterTests {

    private func volatileStore() -> QuickStartCatalogStore {
        QuickStartCatalogStore(defaults: UserDefaults(suiteName: "qs.writer.\(UUID().uuidString)")!)
    }

    @Test("refresh publishes every saved configuration with matching id and name")
    func publishesConfigurations() throws {
        let rig = try makeAppIntentRig()   // seeds one default "Deep Work"
        let sprint = try insertConfiguration(rig.container, name: "Sprint", focus: 1200, isDefault: false)
        let store = volatileStore()

        QuickStartCatalogWriter.refresh(configurations: rig.coordinator.configurations, store: store)

        let catalog = try #require(store.read())
        let byID = Dictionary(uniqueKeysWithValues: catalog.timers.map { ($0.id, $0) })
        #expect(byID[rig.config.id]?.name == "Deep Work")
        #expect(byID[sprint.id]?.name == "Sprint")
        #expect(byID[sprint.id]?.focusDuration == 1200)
    }

    @Test("A deleted configuration disappears from the catalog after the next refresh")
    func deletedDisappears() throws {
        let rig = try makeAppIntentRig()
        let temp = try insertConfiguration(rig.container, name: "Temp", isDefault: false)
        let store = volatileStore()

        QuickStartCatalogWriter.refresh(configurations: rig.coordinator.configurations, store: store)
        #expect(store.read()?.timers.contains { $0.id == temp.id } == true)

        try rig.coordinator.configurations.delete(temp)
        QuickStartCatalogWriter.refresh(configurations: rig.coordinator.configurations, store: store)
        #expect(store.read()?.timers.contains { $0.id == temp.id } == false)
    }
}

// MARK: - Presentation (accessibility)

@Suite("Quick-start — control presentation & accessibility")
struct QuickStartPresentationTests {

    @Test("A selected timer reads as its name with a spoken Start label")
    func selectedName() {
        let content = QuickStartControlPresentation.content(timerName: "Deep Work")
        #expect(content.title == "Deep Work")
        #expect(content.symbolName == "play.fill")
        #expect(content.accessibilityLabel == "Start Deep Work Timer")
        #expect(content.hasSelection)
    }

    @Test("No selection reads as a plain, safe Start Timer")
    func noSelection() {
        let content = QuickStartControlPresentation.content(timerName: nil)
        #expect(content.title == "Start Timer")
        #expect(content.accessibilityLabel == "Start Focus Timer")
        #expect(!content.hasSelection)
    }

    @Test("A blank/whitespace name is treated as no selection")
    func blankIsNoSelection() {
        let content = QuickStartControlPresentation.content(timerName: "   ")
        #expect(!content.hasSelection)
        #expect(content.title == "Start Timer")
    }
}

// MARK: - Routing (the mutation seam)

@Suite("Quick-start — routes through the one mutation seam")
@MainActor
struct QuickStartRoutingTests {

    private func router(_ rig: AppIntentRig, refreshed: @escaping @MainActor () -> Void = {}) -> WidgetControlActions {
        WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: refreshed)
    }

    @Test("Quick-starting a selected configuration starts THAT configuration on the one coordinator")
    func startsSelectedConfiguration() throws {
        let rig = try makeAppIntentRig()   // default "Deep Work"
        let sprint = try insertConfiguration(rig.container, name: "Sprint", focus: 1200, isDefault: false)
        let r = router(rig)

        let result = try r.performQuickStart(configurationID: sprint.id)
        #expect(rig.coordinator.engine.state == .running)
        #expect(result.confirmation.contains("Sprint"))
    }

    @Test("A nil id starts from the user's default configuration")
    func nilStartsDefault() throws {
        let rig = try makeAppIntentRig()
        let r = router(rig)
        let result = try r.performQuickStart(configurationID: nil)
        #expect(rig.coordinator.engine.state == .running)
        #expect(result.confirmation.contains("Deep Work"))
    }

    @Test("A rename takes effect on the next tap (the id is authoritative, not a cached name)")
    func renameUsesAuthoritativeName() throws {
        let rig = try makeAppIntentRig()
        let id = rig.config.id
        rig.config.name = "Renamed Focus"
        try rig.container.mainContext.save()

        let result = try router(rig).performQuickStart(configurationID: id)
        #expect(result.confirmation.contains("Renamed Focus"))
        #expect(!result.confirmation.contains("Deep Work"))
    }

    @Test("The quick-start refreshes the widget projection to running")
    func refreshesProjection() throws {
        let rig = try makeAppIntentRig()
        let store = WidgetProjectionStore(defaults: UserDefaults(suiteName: "qs.proj.\(UUID().uuidString)")!)
        let writer = WidgetProjectionWriter(coordinator: rig.coordinator, store: store, reload: {})
        let r = WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: { writer.update() })

        _ = try r.performQuickStart(configurationID: rig.config.id)
        #expect(store.read()?.state == .running)
    }
}

// MARK: - Failure handling

@Suite("Quick-start — failure isolation")
@MainActor
struct QuickStartFailureTests {

    @Test("The inert router fails safely for quick-start — no handler, no crash")
    func unavailableRouterFailsSafely() {
        #expect(throws: WidgetControlError.unavailable) {
            _ = try WidgetControlActions.unavailable.performQuickStart(configurationID: UUID())
        }
    }

    @Test("A deleted configuration id fails safely and never starts a phantom session")
    func deletedConfigurationFailsSafely() throws {
        let rig = try makeAppIntentRig()
        let temp = try insertConfiguration(rig.container, name: "Temp", isDefault: false)
        let id = temp.id
        try rig.coordinator.configurations.delete(temp)
        let r = WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: {})

        #expect(throws: TimeFrameIntentError.configurationUnavailable) {
            _ = try r.performQuickStart(configurationID: id)
        }
        // The engine never left idle — a failed quick-start can never start a phantom timer.
        #expect(rig.coordinator.engine.state == .idle)
        #expect(rig.coordinator.activeSession == nil)
    }

    @Test("Quick-starting while a session is running throws and keeps the SAME session")
    func alreadyRunningKeepsOneSession() throws {
        let rig = try makeAppIntentRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let id = rig.coordinator.activeSession?.id
        let r = WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: {})

        #expect(throws: TimeFrameIntentError.sessionAlreadyRunning) {
            _ = try r.performQuickStart(configurationID: rig.config.id)
        }
        #expect(rig.coordinator.activeSession?.id == id)
        #expect(rig.coordinator.engine.state == .running)
    }
}

// MARK: - Concurrency (rapid taps)

@Suite("Quick-start — rapid repeated taps")
@MainActor
struct QuickStartConcurrencyTests {

    @Test("Two rapid quick-start taps create exactly one session")
    func twoRapidTaps() throws {
        let rig = try makeAppIntentRig()
        let r = WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: {})
        _ = try r.performQuickStart(configurationID: rig.config.id)
        let id = rig.coordinator.activeSession?.id
        #expect(throws: TimeFrameIntentError.sessionAlreadyRunning) {
            _ = try r.performQuickStart(configurationID: rig.config.id)
        }
        #expect(rig.coordinator.activeSession?.id == id)
    }

    @Test("Ten rapid quick-start taps never create a second session or corrupt state")
    func tenRapidTaps() throws {
        let rig = try makeAppIntentRig()
        let r = WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: {})
        var started = 0
        for _ in 0..<10 {
            if (try? r.performQuickStart(configurationID: rig.config.id)) != nil { started += 1 }
        }
        #expect(started == 1)                                   // only the first tap started a session
        #expect(rig.coordinator.engine.state == .running)
        let id = try #require(rig.coordinator.activeSession?.id)
        #expect(rig.coordinator.activeSession?.id == id)
    }
}
