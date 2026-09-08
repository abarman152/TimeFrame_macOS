//
//  MenuBarTestSupport.swift
//  time_frameTests
//
//  A wired rig: a real `SessionCoordinator` (driven by a mock clock, heartbeat off) with
//  a `MenuBarCoordinator` observing it — exactly as the app wires them. Lets the menu-bar
//  tests exercise the real authoritative engine deterministically, proving the menu bar
//  is a projection of that one timer and never a second one (§55/§57/§58).
//

import Foundation
import SwiftData
@testable import time_frame

@MainActor
struct MenuBarRig {
    let container: ModelContainer
    let clock: MockTimeSource
    let coordinator: SessionCoordinator
    let menuBar: MenuBarCoordinator
    let config: PomodoroConfiguration
}

@MainActor
func makeMenuBarRig(
    focus: TimeInterval = 1500,
    short: TimeInterval = 300,
    long: TimeInterval = 900,
    before: Int = 4,
    total: Int = 4
) throws -> MenuBarRig {
    let container = try makeInMemoryContainer()
    let clock = MockTimeSource()
    let coordinator = makeCoordinator(container, clock: clock)
    let config = try insertConfiguration(
        container, focus: focus, short: short, long: long, before: before, total: total)
    let prefs = MenuBarPreferencesStore(defaults: makeScratchDefaults())
    let menuBar = MenuBarCoordinator(session: coordinator, preferences: prefs)
    return MenuBarRig(container: container, clock: clock, coordinator: coordinator,
                      menuBar: menuBar, config: config)
}
