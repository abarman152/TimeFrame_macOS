//
//  LiveActivityRoutingTests.swift
//  time_frameTests (Milestone 16)
//
//  A Live Activity control is just another command surface. It must reuse the SAME action seam a
//  companion iOS target already has via Milestone 15 — `WidgetControlActions` →
//  `AppIntentSessionActions` → `SessionCoordinator` → `TimerEngine` — never a bespoke
//  `LiveActivitySessionActions` (ADR-069/074). These tests drive that shared router and assert it
//  moves the ONE authoritative coordinator, proving no second action path is needed.
//

import Foundation
import Testing
@testable import time_frame

@Suite("LiveActivityAppIntentRoutingTests")
@MainActor
struct LiveActivityAppIntentRoutingTests {

    /// Builds the shared Milestone-15 router over a rig's coordinator, plus a refresh spy.
    private func makeRouter(_ rig: LiveActivityRig, refreshed: @escaping @MainActor () -> Void) -> WidgetControlActions {
        WidgetControlRouting.makeActions(coordinator: rig.coordinator, refreshProjection: refreshed)
    }

    @Test("Pause/Resume through the shared router move the one coordinator")
    func pauseResumeRoutes() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config)

        var refreshes = 0
        let router = makeRouter(rig) { refreshes += 1 }

        _ = try router.perform(.pause)
        #expect(rig.coordinator.engine.state == .paused)
        _ = try router.perform(.resume)
        #expect(rig.coordinator.engine.state == .running)
        #expect(refreshes == 2)   // each action refreshes the read-only surface
    }

    @Test("Stop through the shared router ends the session on the one coordinator")
    func stopRoutes() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config)
        let router = makeRouter(rig) {}
        _ = try router.perform(.stop)
        #expect(!rig.coordinator.engine.state.isActive)
    }

    @Test("The router surfaces the app's confirmation vocabulary (no duplicated phrasing)")
    func routerReusesDialog() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config)
        let router = makeRouter(rig) {}
        let result = try router.perform(.pause)
        #expect(result.confirmation == AppIntentDialogText.paused)
    }

    @Test("The control action type is the shared WidgetControlAction, not a Live-Activity-specific one")
    func sharedActionType() {
        // Compile-time proof the vocabulary is shared: these are the M15 cases, reused verbatim.
        let all = WidgetControlAction.allCases
        #expect(Set(all) == [.pause, .resume, .skip, .restart, .stop, .start])
    }
}
