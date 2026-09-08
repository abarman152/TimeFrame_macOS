//
//  InteractiveWidgetStateTests.swift
//  time_frameTests (Milestone 15)
//
//  The widget's controls are a PURE function of the read-only projection (state + phase) via
//  `WidgetControlSet` — never a second timer. These tests pin exactly which controls each
//  state/phase offers on the small and medium families, and that configuration never changes
//  that decision (it selects presentation only).
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Interactive widget state → controls")
struct InteractiveWidgetStateTests {

    private func controls(_ state: WidgetSessionState, _ phase: WidgetPhase, compact: Bool) -> [WidgetControlAction] {
        WidgetControlSet.controls(for: state, phase: phase, compact: compact)
    }

    @Test("Idle offers only Start")
    func idle() {
        #expect(controls(.idle, .none, compact: false) == [.start])
        #expect(controls(.idle, .none, compact: true) == [.start])
    }

    @Test("Running focus offers Pause and Skip, plus Stop where there is room")
    func runningFocus() {
        #expect(controls(.running, .focus, compact: false) == [.pause, .skip, .stop])
        #expect(controls(.running, .focus, compact: true) == [.pause, .skip])
    }

    @Test("Running short break offers Skip and Stop (no Pause)")
    func runningShortBreak() {
        #expect(controls(.running, .shortBreak, compact: false) == [.skip, .stop])
        #expect(controls(.running, .shortBreak, compact: true) == [.skip, .stop])
        #expect(!controls(.running, .shortBreak, compact: false).contains(.pause))
    }

    @Test("Running long break behaves like a break")
    func runningLongBreak() {
        #expect(controls(.running, .longBreak, compact: false) == [.skip, .stop])
        #expect(controls(.running, .longBreak, compact: true) == [.skip, .stop])
    }

    @Test("Paused offers Resume, Restart, Stop; small drops Restart")
    func paused() {
        #expect(controls(.paused, .focus, compact: false) == [.resume, .restart, .stop])
        #expect(controls(.paused, .focus, compact: true) == [.resume, .stop])
    }

    @Test("Completed and interrupted offer only Start (as an inline primary)")
    func completedInterrupted() {
        #expect(controls(.completed, .none, compact: false) == [.start])
        #expect(controls(.interrupted, .none, compact: false) == [.start])
        #expect(controls(.completed, .none, compact: true) == [.start])
        #expect(controls(.interrupted, .none, compact: true) == [.start])
    }

    @Test("Unavailable offers no controls")
    func unavailable() {
        #expect(controls(.unavailable, .none, compact: false).isEmpty)
        #expect(controls(.unavailable, .none, compact: true).isEmpty)
    }

    @Test("Live engine states map to the expected widget state and controls")
    func liveStatesMapCorrectly() throws {
        let rig = try makeInteractiveWidgetRig(focus: 600, short: 300, total: 4)

        // Idle → Start.
        #expect(rig.projection?.state == .idle)

        // Running focus → Pause/Skip/Stop.
        try rig.perform(.start)
        #expect(rig.projection?.state == .running)
        #expect(rig.projection?.phase == .focus)
        #expect(controls(.running, rig.projection!.phase, compact: false) == [.pause, .skip, .stop])

        // Running break → Skip/Stop.
        try rig.perform(.skip)
        #expect(rig.projection?.phase == .shortBreak)
        #expect(controls(.running, rig.projection!.phase, compact: false) == [.skip, .stop])

        // Paused → Resume/Restart/Stop.
        try rig.perform(.skip) // back to focus
        try rig.perform(.pause)
        #expect(rig.projection?.state == .paused)
        #expect(controls(.paused, rig.projection!.phase, compact: false) == [.resume, .restart, .stop])
    }
}

@MainActor
@Suite("Interactive widget configuration compatibility")
struct InteractiveWidgetConfigurationTests {

    private func runningProjection() -> WidgetProjection {
        let now = Date()
        return WidgetProjection(
            generatedAt: now, state: .running, phase: .focus,
            title: "Research", currentIntervalIndex: 1, totalIntervals: 4,
            intervalStartedAt: now, intervalPlannedEndAt: now.addingTimeInterval(600)
        )
    }

    @Test("Control availability ignores configuration (presentation vs availability are separate)")
    func controlsIgnoreConfiguration() {
        // The control set takes no configuration: display mode, destination, and countdown can
        // never change which controls a state offers. (The view shows controls only in Timer
        // mode; Today/Statistics stay read-only — a view-level presentation choice.)
        let focus = WidgetControlSet.controls(for: .running, phase: .focus, compact: false)
        #expect(focus == [.pause, .skip, .stop])
    }

    @Test("Adding interactivity does not couple configuration to timing")
    func timingIsConfigInvariant() {
        let projection = runningProjection()
        let now = projection.generatedAt
        let timer = TimeFrameWidgetConfiguration(displayMode: .timer, destination: .timer, showsCountdown: true)
        let noCountdown = TimeFrameWidgetConfiguration(displayMode: .timer, destination: .history, showsCountdown: false)
        let today = TimeFrameWidgetConfiguration(displayMode: .today, destination: .today, showsCountdown: true)
        let statistics = TimeFrameWidgetConfiguration(displayMode: .statistics, destination: .statistics, showsCountdown: false)

        let a = WidgetTimelineBuilder.timeline(projection: projection, configuration: timer, now: now)
        let b = WidgetTimelineBuilder.timeline(projection: projection, configuration: noCountdown, now: now)
        let c = WidgetTimelineBuilder.timeline(projection: projection, configuration: today, now: now)
        let d = WidgetTimelineBuilder.timeline(projection: projection, configuration: statistics, now: now)

        // Same instants and reload policy regardless of what/where/countdown the config selects.
        #expect(a.entries.map(\.date) == b.entries.map(\.date))
        #expect(a.entries.map(\.date) == c.entries.map(\.date))
        #expect(a.entries.map(\.date) == d.entries.map(\.date))
        #expect(a.refresh == b.refresh)
        #expect(a.refresh == c.refresh)
        #expect(a.refresh == d.refresh)
    }
}
