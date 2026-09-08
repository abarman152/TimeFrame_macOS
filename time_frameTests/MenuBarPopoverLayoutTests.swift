//
//  MenuBarPopoverLayoutTests.swift
//  time_frameTests (Milestone 28)
//
//  The redesigned popover has an information hierarchy that has to hold in every state
//  (ADR-102), and most of it is asserted here at the level the popover actually switches on —
//  the authoritative `MenuBarPresentationState` — plus a source audit of the view tree for the
//  structural rules a value test cannot see:
//
//   • the secondary actions (Open Time Frame / Settings / History / Quit) appear ONLY in the
//     gear menu, never as permanent rows in the primary content;
//   • no part of the popover scrolls (ADR-107): the pinned list is capped and the remainder
//     moves into a More menu, so a long list can never push the controls off screen;
//   • the countdown block is still a repaint of the engine's derived value — the popover adds
//     no `Timer`, `Task.sleep`, `asyncAfter`, or decrement of its own;
//   • the status-item LABEL still contains no `TimelineView` (M26, ADR-101).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("Menu bar popover states")
@MainActor
struct MenuBarPopoverStateTests {

    @Test("Ready state: no session, so no transport controls and a Start fallback")
    func readyState() throws {
        let rig = try makeMenuBarRig()
        let state = rig.menuBar.presentation
        #expect(state.situation == .empty)
        #expect(state.hasActiveSession == false)
        #expect(state.phase == nil)
        _ = rig.container
    }

    @Test("Active state: the four running controls apply and the countdown is live")
    func activeState() throws {
        let rig = try makeMenuBarRig(focus: 1500, short: 300)
        _ = try rig.coordinator.startSession(configuration: rig.config, taskName: "Ship")

        let state = rig.menuBar.presentation
        #expect(state.situation == .running)
        #expect(state.hasActiveSession)
        #expect(state.phase == .focus)
        #expect(state.remaining == 1500)
        #expect(state.nextPhase == .shortBreak)
        #expect(state.nextDuration == 300)
        #expect(state.currentFocusNumber == 1)
        #expect(state.totalFocusSessions == 4)
        _ = rig.container
    }

    @Test("Paused state: still active, countdown frozen, controls still apply")
    func pausedState() throws {
        let rig = try makeMenuBarRig(focus: 1500)
        _ = try rig.coordinator.startSession(configuration: rig.config, taskName: "Ship")
        rig.clock.advance(by: 60)
        try rig.coordinator.pause()

        let state = rig.menuBar.presentation
        #expect(state.situation == .paused)
        #expect(state.hasActiveSession)
        #expect(state.remaining == 1440)

        rig.clock.advance(by: 120)
        #expect(rig.menuBar.presentation.remaining == 1440, "Paused time must stay frozen")
        _ = rig.container
    }

    @Test("Completed state: no live countdown, and Quick Start is still offered")
    func completedState() throws {
        let rig = try makeMenuBarRig(focus: 10, short: 5, long: 15, before: 4, total: 1)
        _ = try rig.coordinator.startSession(configuration: rig.config, taskName: "Ship")
        rig.clock.advance(by: 100)
        try rig.coordinator.tick()

        let state = rig.menuBar.presentation
        #expect(state.situation == .completed)
        #expect(state.hasActiveSession == false)
        #expect(state.remaining == 0)
        _ = rig.container
    }

    @Test("Restart is available while running, not only while paused")
    func restartAvailableWhileRunning() throws {
        let rig = try makeMenuBarRig(focus: 1500)
        _ = try rig.coordinator.startSession(configuration: rig.config, taskName: "Ship")
        rig.clock.advance(by: 300)
        #expect(rig.menuBar.presentation.remaining == 1200)

        rig.menuBar.restart()

        #expect(rig.coordinator.engine.state == .running)
        #expect(rig.menuBar.presentation.remaining == 1500, "Restart re-anchors the interval")
        _ = rig.container
    }
}

@Suite("Menu bar popover structure")
struct MenuBarPopoverStructureTests {

    private var menuBarViews: [URL] {
        SourceAudit.swiftSources(in: SourceAudit.appTarget().appendingPathComponent("Views/MenuBar"))
    }

    private func source(_ name: String) -> String {
        let url = SourceAudit.appTarget()
            .appendingPathComponent("Views/MenuBar")
            .appendingPathComponent(name)
        return SourceAudit.code(url)
    }

    @Test("The menu bar view tree exists where the audit expects it")
    func viewsAreFound() {
        #expect(menuBarViews.count >= 8)
    }

    @Test("Secondary actions live only in the gear menu, never in the primary content")
    func secondaryActionsOnlyInGearMenu() {
        // The four navigation actions are identified by the accessibility identifiers they
        // have carried since Milestone 8, so this survives copy changes.
        let ids = ["timeFrame.menuBar.openApp", "timeFrame.menuBar.settings",
                   "timeFrame.menuBar.history", "timeFrame.menuBar.quit"]
        let gear = SourceAudit.codeKeepingStrings(
            SourceAudit.appTarget().appendingPathComponent("Views/MenuBar/MenuBarGearMenu.swift"))
        for id in ids {
            #expect(gear.contains(id), "\(id) must be offered by the gear menu")
        }
        for url in menuBarViews where url.lastPathComponent != "MenuBarGearMenu.swift" {
            let text = SourceAudit.codeKeepingStrings(url)
            for id in ids {
                #expect(!text.contains(id),
                        "\(url.lastPathComponent) must not offer \(id) outside the gear menu")
            }
        }
    }

    @Test("The gear menu uses the documented SF Symbols and one accessibility label")
    func gearMenuSymbols() {
        let gear = SourceAudit.codeKeepingStrings(
            SourceAudit.appTarget().appendingPathComponent("Views/MenuBar/MenuBarGearMenu.swift"))
        for symbol in ["gearshape", "macwindow", "clock.arrow.circlepath", "power"] {
            #expect(gear.contains(symbol))
        }
        #expect(gear.contains("Settings and More"))
    }

    @Test("No part of the popover scrolls (Milestone 29, ADR-107)")
    func popoverNeverScrolls() {
        // The popover is a glance-and-go surface. A scroll view there is slow to hit, hides
        // its own contents, and turns the menu bar into a miniature of the app. Milestone 28
        // bounded the pinned list inside a ScrollView; Milestone 29 removes scrolling
        // entirely and caps the list instead.
        for url in menuBarViews {
            let text = SourceAudit.code(url)
            #expect(!text.contains("ScrollView"),
                    "\(url.lastPathComponent) must not scroll — the popover shows a fixed set of rows")
        }
    }

    @Test("The pinned list is capped, with the remainder offered by a More menu")
    func pinnedListIsCapped() {
        let quickStart = SourceAudit.codeKeepingStrings(
            SourceAudit.appTarget().appendingPathComponent("Views/MenuBar/MenuBarQuickStartView.swift"))
        #expect(quickStart.contains("visibleLimit"),
                "The number of rows drawn must be an explicit, bounded limit")
        #expect(quickStart.contains("prefix(Self.visibleLimit)"))
        #expect(quickStart.contains("dropFirst(Self.visibleLimit)"),
                "Pins beyond the limit must still be reachable, not dropped")
        #expect(quickStart.contains("timeFrame.menuBar.quickStart.more"),
                "The overflow needs its own identified control")
    }

    @Test("The visible-row cap keeps the popover a glance surface")
    func visibleLimitIsSmall() {
        #expect(MenuBarQuickStartView.visibleLimit >= 1)
        #expect(MenuBarQuickStartView.visibleLimit <= 5,
                "More than a handful of rows and the popover stops being a glance surface")
    }

    @Test("The popover introduces no clock of its own")
    func popoverHasNoClock() {
        for url in menuBarViews {
            let text = SourceAudit.code(url)
            for token in ["Timer(", "Task.sleep", "asyncAfter", "scheduledTimer", "DispatchSourceTimer"] {
                #expect(!text.contains(token),
                        "\(url.lastPathComponent) must not introduce a scheduling primitive")
            }
        }
    }

    @Test("The status-item label still contains no TimelineView (ADR-101)")
    func labelHasNoTimelineView() {
        let label = source("TimeFrameMenuBarLabel.swift")
        #expect(!label.contains("TimelineView"),
                "A TimelineView in a MenuBarExtra label re-renders unboundedly (ADR-101)")
    }

    @Test("Quick Start rows render the icon through the catalog, never a literal symbol")
    func rowsUseTheIconCatalog() {
        let row = SourceAudit.codeKeepingStrings(
            SourceAudit.appTarget()
                .appendingPathComponent("Views/MenuBar/MenuBarQuickStartRowView.swift"))
        #expect(row.contains("item.icon.symbolName"))
    }
}
