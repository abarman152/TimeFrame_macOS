//
//  WidgetProjectionFreshnessTests.swift
//  time_frameTests (Milestone 21)
//
//  The M21 freshness regression: proving that widget surfaces (Home Screen AND Lock Screen, which
//  share the one projection pipeline) refresh on MEANINGFUL transitions only — never on a per-second
//  countdown tick. The live countdown between refreshes is a repaint of the frozen anchors, so the
//  timeline stays efficient and there is never a second clock (ADR-055/087).
//
//  We wire the REAL coordinator exactly as the app does: `onMeaningfulTransition → writer.update()`
//  (the auto interval-advance path) plus the lifecycle fan-out (`writer.handle`). We then show that
//  sub-second ticks inside an interval cause NO projection write/reload, while an auto interval
//  boundary and each explicit lifecycle event do.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Widget projection freshness — meaningful transitions only")
struct WidgetProjectionFreshnessTests {

    private final class Counter { var count = 0 }

    private func scratchStore() -> WidgetProjectionStore {
        let suite = "test.widget.fresh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return WidgetProjectionStore(defaults: defaults)
    }

    @Test("Sub-second ticks within an interval perform no projection write; the auto boundary does")
    func ticksDoNotWriteButBoundaryDoes() throws {
        let container = try makeInMemoryContainer()
        // Short, deterministic durations: a 10s focus then a 5s break.
        let config = try insertConfiguration(container, focus: 10, short: 5, long: 15, before: 4, total: 4)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let store = scratchStore()
        let reloads = Counter()
        let writer = WidgetProjectionWriter(
            coordinator: coordinator, store: store, now: { clock.now() },
            reload: { reloads.count += 1 })
        // Wire the auto interval-advance seam exactly like the app.
        coordinator.onMeaningfulTransition = { [weak writer] in writer?.update() }

        try coordinator.startSession(configuration: config, taskName: "Focus")
        writer.update()            // the app writes once on the start lifecycle event
        reloads.count = 0          // isolate the tick behaviour

        // Nine 1s ticks INSIDE the focus interval — no state/index change, so no write.
        for _ in 0..<9 {
            clock.advance(by: 1)
            try coordinator.tick()
        }
        #expect(reloads.count == 0, "A countdown tick inside an interval must not write the projection")

        // Cross the focus→break boundary (focus is 10s; land at t=11, inside the 5s break): the
        // auto-advance fires the meaningful-transition hook exactly once for this single tick.
        clock.advance(by: 2)
        try coordinator.tick()
        #expect(reloads.count == 1, "The interval boundary must refresh the projection exactly once")
        #expect(store.read()?.phase == .shortBreak)
    }

    @Test("Each explicit lifecycle event refreshes the projection (pause / resume / stop)")
    func lifecycleEventsWrite() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 100)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let store = scratchStore()
        let reloads = Counter()
        let writer = WidgetProjectionWriter(
            coordinator: coordinator, store: store, now: { clock.now() },
            reload: { reloads.count += 1 })

        try coordinator.startSession(configuration: config)
        writer.handle(.started(coordinator.currentLifecycleContext()!))
        #expect(store.read()?.state == .running)

        clock.advance(by: 20)
        try coordinator.pause()
        writer.handle(.paused(coordinator.currentLifecycleContext()!))
        #expect(store.read()?.state == .paused)

        try coordinator.resume()
        writer.handle(.resumed(coordinator.currentLifecycleContext()!))
        #expect(store.read()?.state == .running)

        try coordinator.stop()
        // After stop there is no active lifecycle context; the writer re-mirrors current state.
        writer.update()
        #expect(store.read()?.state != .running)

        // Four meaningful refreshes happened (start, pause, resume, stop) — never one per tick.
        #expect(reloads.count >= 4)
    }

    @Test("Repeated widget writes never mutate the coordinator or engine")
    func writesAreReadOnly() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 100)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        let writer = WidgetProjectionWriter(coordinator: coordinator, store: scratchStore(), now: { clock.now() })

        try coordinator.startSession(configuration: config, taskName: "Untouched")
        let stateBefore = coordinator.engine.state
        let indexBefore = coordinator.engine.currentIndex

        for _ in 0..<50 { writer.update() }

        #expect(coordinator.engine.state == stateBefore)
        #expect(coordinator.engine.currentIndex == indexBefore)
    }
}
