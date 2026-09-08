//
//  MenuBarRecoveryTests.swift
//  time_frameTests
//
//  After relaunch the menu bar must immediately reflect the *recovered* authoritative
//  state — running continues, paused stays frozen, and a session that finished while the
//  app was away shows completed, never a stale running countdown (§35/§76). A "relaunch"
//  is a second coordinator restoring from the same store, exactly as in SessionRecoveryTests.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Menu bar recovery")
struct MenuBarRecoveryTests {

    private func menuBar(over coordinator: SessionCoordinator) -> MenuBarCoordinator {
        MenuBarCoordinator(session: coordinator,
                           preferences: MenuBarPreferencesStore(defaults: makeScratchDefaults()))
    }

    @Test("A recovered running session projects the running state with fast-forwarded time")
    func recoveredRunning() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 10) // [F10, S5, ...]
        let clockA = MockTimeSource()
        let coordA = makeCoordinator(container, clock: clockA)
        try coordA.startSession(configuration: config, taskName: "Resumed")

        // Relaunch 3s into the first focus interval.
        let clockB = MockTimeSource()
        clockB.set(to: clockA.now().addingTimeInterval(3))
        let coordB = makeCoordinator(container, clock: clockB)
        _ = try coordB.recover()

        let state = menuBar(over: coordB).presentation
        #expect(state.situation == .running)
        #expect(state.phase == .focus)
        #expect(state.taskName == "Resumed")
        expectClose(state.remaining, 7) // 10 − 3
    }

    @Test("A recovered paused session projects the paused state, frozen")
    func recoveredPaused() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 10)
        let clockA = MockTimeSource()
        let coordA = makeCoordinator(container, clock: clockA)
        try coordA.startSession(configuration: config)
        clockA.advance(by: 4)
        try coordA.pause() // remaining 6, frozen

        let clockB = MockTimeSource()
        clockB.set(to: clockA.now().addingTimeInterval(1000)) // long absence must not matter
        let coordB = makeCoordinator(container, clock: clockB)
        _ = try coordB.recover()

        let menu = menuBar(over: coordB)
        #expect(menu.presentation.situation == .paused)
        expectClose(menu.presentation.remaining, 6)
        clockB.advance(by: 500)
        expectClose(menu.presentation.remaining, 6) // still frozen (§18)
    }

    @Test("A session that completed while away projects completed, not stale running")
    func completedWhileAway() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, total: 1) // [F10, S5]
        let clockA = MockTimeSource()
        let coordA = makeCoordinator(container, clock: clockA)
        try coordA.startSession(configuration: config)

        let clockB = MockTimeSource()
        clockB.set(to: clockA.now().addingTimeInterval(100)) // whole plan elapsed
        let coordB = makeCoordinator(container, clock: clockB)
        _ = try coordB.recover()

        let state = menuBar(over: coordB).presentation
        #expect(state.situation == .completed)
        #expect(state.hasActiveSession == false)
        #expect(state.remaining == 0) // never a stale running countdown (§51)
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: true) == "Done")
    }
}
