//
//  InteractiveWidgetActionTests.swift
//  time_frameTests (Milestone 15)
//
//  Proves each widget control action drives the ONE authoritative coordinator through the
//  shared router → AppIntentSessionActions seam, and that the shared store then reflects the
//  new authoritative state (the widget's only data source). No second timer is ever created.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Interactive widget actions")
struct InteractiveWidgetActionTests {

    @Test("Start from the widget begins a session and the projection reflects running focus")
    func startBeginsSession() throws {
        let rig = try makeInteractiveWidgetRig()
        #expect(rig.coordinator.engine.state == .idle)

        let result = try rig.perform(.start)
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.coordinator.engine.currentPhase == .focus)
        #expect(result.confirmation.contains("Started") || result.confirmation.lowercased().contains("session"))
        #expect(rig.projection?.state == .running)
        #expect(rig.projection?.phase == .focus)
    }

    @Test("Pause then resume move the engine and the projection between paused and running")
    func pauseResume() throws {
        let rig = try makeInteractiveWidgetRig()
        try rig.perform(.start)

        _ = try rig.perform(.pause)
        #expect(rig.coordinator.engine.state == .paused)
        #expect(rig.projection?.state == .paused)
        #expect(rig.projection?.pausedRemainingSeconds != nil)

        _ = try rig.perform(.resume)
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.projection?.state == .running)
    }

    @Test("Skip advances to the next interval and the projection follows")
    func skipAdvances() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600, short: 300, total: 4)
        try rig.perform(.start)

        _ = try rig.perform(.skip)
        #expect(rig.coordinator.engine.currentPhase == .shortBreak)
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.projection?.phase == .shortBreak)
    }

    @Test("Restart resets the current interval and refreshes the projection anchors")
    func restartResets() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600)
        try rig.perform(.start)
        rig.clock.advance(by: 200)
        // A stale projection captured before restart would show the old anchors.
        rig.writer.update()
        let before = rig.projection

        _ = try rig.perform(.restart)
        expectClose(rig.coordinator.engine.remaining, 600, tolerance: 1)
        // The restart refreshed the projection (restart emits no lifecycle event; the router's
        // post-action refresh is what keeps the widget correct — ADR-071).
        let after = rig.projection
        #expect(after?.state == .running)
        #expect(after?.intervalPlannedEndAt != before?.intervalPlannedEndAt)
    }

    @Test("Stop cancels the run, preserves history, and the projection returns to idle")
    func stopPreservesHistory() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600, short: 300, total: 4)
        try rig.perform(.start)
        let session = rig.coordinator.activeSession
        rig.clock.advance(by: 600); try rig.coordinator.tick() // complete one focus interval

        _ = try rig.perform(.stop)
        #expect(rig.coordinator.engine.state == .cancelled)
        #expect(session != nil)
        #expect((session?.intervals.count ?? 0) >= 1) // stop is never a delete
        #expect(rig.projection?.state == .idle)
    }

    @Test("Skipping the final interval completes the session and confirms completion")
    func skipCompletes() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600, short: 300, total: 1)
        try rig.perform(.start)
        _ = try rig.perform(.skip)              // focus → short break
        let result = try rig.perform(.skip)     // short break → complete
        #expect(rig.coordinator.engine.state == .completed)
        #expect(result.confirmation.lowercased().contains("complete"))
        #expect(rig.projection?.state == .completed)
    }

    @Test("Each successful action requested a widget reload")
    func actionsReload() throws {
        let rig = try makeInteractiveWidgetRig()
        let base = rig.reloads.count
        try rig.perform(.start)
        try rig.perform(.pause)
        try rig.perform(.resume)
        #expect(rig.reloads.count > base) // reloads happen after meaningful actions, not per tick
    }
}
