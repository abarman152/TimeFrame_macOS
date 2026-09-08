//
//  MenuBarPreferencesTests.swift
//  time_frameTests
//
//  The only persisted menu-bar state is the visibility/countdown preference, stored in a
//  scratch UserDefaults (§46/§63/§64). Defaults ship "on"; changes persist; and the
//  countdown preference changes the compact title without ever touching the timer (§26/§65).
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Menu bar preferences")
struct MenuBarPreferencesTests {

    @Test("Menu bar is shown by default with the countdown on")
    func defaults() {
        let store = MenuBarPreferencesStore(defaults: makeScratchDefaults())
        #expect(store.showInMenuBar)
        #expect(store.showCountdownInLabel)
    }

    @Test("Toggling visibility persists across store instances")
    func visibilityPersists() {
        let defaults = makeScratchDefaults()
        let store = MenuBarPreferencesStore(defaults: defaults)
        store.showInMenuBar = false

        let reloaded = MenuBarPreferencesStore(defaults: defaults)
        #expect(reloaded.showInMenuBar == false)
        #expect(reloaded.showCountdownInLabel) // unrelated flag untouched
    }

    @Test("Toggling the countdown preference persists")
    func countdownPersists() {
        let defaults = makeScratchDefaults()
        let store = MenuBarPreferencesStore(defaults: defaults)
        store.showCountdownInLabel = false

        let reloaded = MenuBarPreferencesStore(defaults: defaults)
        #expect(reloaded.showCountdownInLabel == false)
    }

    @Test("With the countdown off the title shows only the phase word")
    func countdownOffTitle() throws {
        let rig = try makeMenuBarRig(focus: 1500, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        let state = rig.menuBar.presentation
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: false) == "Focus")
        #expect(MenuBarStatusPresentation.title(for: state, showCountdown: true) == "Focus 25:00")
    }

    @Test("Disabling the menu bar never disturbs a running timer")
    func disablingDoesNotAffectTimer() throws {
        let rig = try makeMenuBarRig()
        try rig.coordinator.startSession(configuration: rig.config)
        rig.menuBar.preferences.showInMenuBar = false
        #expect(rig.menuBar.isVisible == false)
        #expect(rig.coordinator.engine.state == .running) // timer untouched (§26)
        // The projection still reflects the live session even while hidden.
        #expect(rig.menuBar.presentation.situation == .running)
    }
}
