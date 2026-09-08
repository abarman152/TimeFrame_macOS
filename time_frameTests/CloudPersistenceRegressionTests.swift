//
//  CloudPersistenceRegressionTests.swift
//  time_frameTests (Milestone 13)
//
//  The CloudKit-ready persistence layer must not regress the WidgetKit projection
//  or App Intents. Widgets keep reading the local App Group projection (not
//  CloudKit), and intents keep routing through the one SessionCoordinator.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Cloud persistence regressions")
struct CloudPersistenceRegressionTests {

    // MARK: WidgetKit — still driven by the local App Group projection

    @Test("WidgetProjectionWriter still mirrors a running session to the App Group store")
    func widgetProjectionStillWorks() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let clock = MockTimeSource()
        let coord = makeCoordinator(container, clock: clock)

        let store = WidgetProjectionStore(defaults: UserDefaults(suiteName: "widget.regress.\(UUID().uuidString)"))
        let writer = WidgetProjectionWriter(
            coordinator: coord,
            store: store,
            now: { clock.now() },
            reload: {}
        )

        _ = try coord.startSession(configuration: config, taskName: "Focus")
        writer.update()

        let projection = try #require(store.read())
        #expect(projection.state == .running)
        #expect(projection.state.isActive)
        #expect(projection.title == "Focus")
    }

    // MARK: App Intents — still route through SessionCoordinator

    @Test("An App Intent action starts a session on the one coordinator")
    func appIntentStillRoutesThroughCoordinator() throws {
        let rig = try makeAppIntentRig()
        _ = try rig.actions.startSession(configurationID: rig.config.id, taskName: "From Intent", totalSessions: nil)
        #expect(rig.coordinator.activeSession != nil)
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.coordinator.activeSession?.taskName == "From Intent")
    }

    @Test("An App Intent pause routes through the coordinator")
    func appIntentPause() throws {
        let rig = try makeAppIntentRig()
        _ = try rig.actions.startSession(configurationID: rig.config.id, taskName: "x", totalSessions: nil)
        try rig.actions.pause()
        #expect(rig.coordinator.engine.state == .paused)
    }
}
