//
//  MenuBarControlTests.swift
//  time_frameTests
//
//  Every menu-bar control routes through the shared `SessionCoordinator` and never
//  touches the engine directly (§20/§47/§59). Also: the projected countdown is derived
//  from the authoritative clock (§58), and controls that don't apply are safe no-ops
//  (§60). All deterministic via the mock clock — no second clock exists.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Menu bar controls")
struct MenuBarControlTests {

    // MARK: Routing (§59)

    @Test("Pause routes through the coordinator")
    func pauseRoutes() throws {
        let rig = try makeMenuBarRig()
        try rig.coordinator.startSession(configuration: rig.config)
        rig.menuBar.pause()
        #expect(rig.coordinator.engine.state == .paused)
    }

    @Test("Resume routes through the coordinator")
    func resumeRoutes() throws {
        let rig = try makeMenuBarRig()
        try rig.coordinator.startSession(configuration: rig.config)
        rig.menuBar.pause()
        rig.menuBar.resume()
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("Skip routes through the coordinator and advances the interval")
    func skipRoutes() throws {
        let rig = try makeMenuBarRig(focus: 1500, total: 2)
        try rig.coordinator.startSession(configuration: rig.config)
        #expect(rig.coordinator.engine.currentIndex == 0)
        rig.menuBar.skip()
        #expect(rig.coordinator.engine.currentIndex == 1)
        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.menuBar.presentation.phase == .shortBreak)
    }

    @Test("Stop routes through the coordinator")
    func stopRoutes() throws {
        let rig = try makeMenuBarRig()
        try rig.coordinator.startSession(configuration: rig.config)
        rig.menuBar.stop()
        #expect(rig.coordinator.engine.state == .cancelled)
    }

    @Test("Restart routes through the coordinator and re-anchors the interval")
    func restartRoutes() throws {
        let rig = try makeMenuBarRig(focus: 1500, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 60)
        expectClose(rig.menuBar.presentation.remaining, 1440)
        rig.menuBar.restart()
        #expect(rig.coordinator.engine.state == .running)
        expectClose(rig.menuBar.presentation.remaining, 1500)
    }

    @Test("Start New Session clears a finished run back to idle")
    func startNewSessionResets() throws {
        let rig = try makeMenuBarRig(focus: 10, short: 5, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 100)
        try rig.coordinator.tick()
        #expect(rig.coordinator.engine.state == .completed)

        rig.menuBar.prepareForNewSession()
        #expect(rig.coordinator.engine.state == .idle)
        #expect(rig.menuBar.presentation.situation == .empty)
    }

    // MARK: Countdown derives from the authoritative clock (§58)

    @Test("Advancing the clock updates the projected countdown without a tick")
    func countdownDerivesFromClock() throws {
        let rig = try makeMenuBarRig(focus: 1500, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        #expect(MenuBarStatusPresentation.title(for: rig.menuBar.presentation, showCountdown: true) == "Focus 25:00")

        // No tick, no second clock — the projection re-derives remaining from the engine's
        // timeline against the advanced mock clock.
        rig.clock.advance(by: 60)
        #expect(MenuBarStatusPresentation.title(for: rig.menuBar.presentation, showCountdown: true) == "Focus 24:00")
    }

    // MARK: Safe no-ops (§60)

    @Test("Pause with no active session is ignored, never crashes")
    func pauseWithNoSessionIgnored() throws {
        let rig = try makeMenuBarRig()
        rig.menuBar.pause()
        #expect(rig.coordinator.engine.state == .idle)
        #expect(rig.menuBar.presentation.situation == .empty)
    }

    @Test("Resume on a completed session is ignored, never crashes")
    func resumeOnCompletedIgnored() throws {
        let rig = try makeMenuBarRig(focus: 10, short: 5, total: 1)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 100)
        try rig.coordinator.tick()
        #expect(rig.coordinator.engine.state == .completed)

        rig.menuBar.resume()
        #expect(rig.coordinator.engine.state == .completed) // unchanged
    }

    @Test("Stop with no active session is ignored, never crashes")
    func stopWithNoSessionIgnored() throws {
        let rig = try makeMenuBarRig()
        rig.menuBar.stop()
        #expect(rig.coordinator.engine.state == .idle)
    }
}
