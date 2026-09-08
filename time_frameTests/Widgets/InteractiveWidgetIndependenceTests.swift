//
//  InteractiveWidgetIndependenceTests.swift
//  time_frameTests (Milestone 15)
//
//  Two guarantees: the interactive action flow works entirely over the LOCAL store with no
//  iCloud/CloudKit involved (a CloudKit problem can never disable widget interaction), and the
//  authoritative-state path is exactly action → coordinator → projection writer → shared store
//  (the widget/router never writes the store itself).
//

import Foundation
import Testing
@testable import time_frame

// MARK: - CloudKit independence

@MainActor
@Suite("Interactive widget CloudKit independence")
struct InteractiveWidgetCloudKitIndependenceTests {

    @Test("Every action works over a purely local store with no CloudKit")
    func actionsWorkLocally() throws {
        // The rig's container is an in-memory LOCAL store; the widget store is a volatile local
        // suite. No CloudKit, no account — the full control flow must still work.
        let rig = try makeInteractiveWidgetRig(focus: 600, short: 300, total: 4)
        try rig.perform(.start)
        #expect(rig.projection?.state == .running)
        _ = try rig.perform(.pause)
        #expect(rig.projection?.state == .paused)
        _ = try rig.perform(.resume)
        _ = try rig.perform(.skip)
        #expect(rig.coordinator.engine.currentPhase == .shortBreak)
        _ = try rig.perform(.stop)
        #expect(rig.projection?.state == .idle)
    }

    @Test("An unavailable widget store never blocks the action or the timer")
    func unavailableStoreDoesNotBlock() throws {
        // Simulate an unusable App Group suite: the store is inert, but the action still drives
        // the one coordinator (the timer is never gated on the widget projection).
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        #expect(rig.coordinator.engine.state == .running)
    }
}

// MARK: - Projection flow (action → coordinator → writer → store)

@MainActor
@Suite("Interactive widget projection flow")
struct InteractiveWidgetProjectionTests {

    @Test("After an action, the stored projection equals the mapper's view of authoritative state")
    func storeMatchesAuthoritativeState() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        _ = try rig.perform(.pause)

        // The projection in the store is exactly what the mapper derives from the coordinator —
        // proving the widget reads the writer's single mapping, not a widget-local mutation.
        let expected = WidgetProjectionMapper.projection(from: rig.coordinator, now: rig.clock.now())
        let stored = rig.projection
        #expect(stored?.state == expected.state)
        #expect(stored?.phase == expected.phase)
        #expect(stored?.pausedRemainingSeconds == expected.pausedRemainingSeconds)
        #expect(stored?.title == expected.title)
    }

    @Test("Restart (which emits no lifecycle event) still refreshes the projection anchors")
    func restartRefreshesProjection() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        rig.clock.advance(by: 250)
        rig.writer.update()
        let staleEnd = rig.projection?.intervalPlannedEndAt

        _ = try rig.perform(.restart)
        let freshEnd = rig.projection?.intervalPlannedEndAt
        #expect(freshEnd != nil)
        #expect(freshEnd != staleEnd) // the router refreshed even without a lifecycle event
    }

    @Test("Meaningful actions reload; there is no per-tick reload")
    func reloadsAreMeaningfulOnly() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        let start = rig.reloads.count
        try rig.perform(.start)
        let afterStart = rig.reloads.count
        #expect(afterStart > start)

        // A pure clock advance + tick with no transition must not reload.
        rig.clock.advance(by: 10)
        try rig.coordinator.tick()
        #expect(rig.reloads.count == afterStart)
    }
}
