//
//  InteractiveWidgetTestSupport.swift
//  time_frameTests (Milestone 15)
//
//  A wired rig for the interactive-widget suites. It reproduces the production path a widget
//  button takes — WidgetControlActions router → AppIntentSessionActions → the one
//  SessionCoordinator → the WidgetProjectionWriter → the shared store — over an in-memory
//  container with a mock clock (heartbeat off). No WidgetKit host, no Siri, no real time: the
//  same deterministic style as every other layer's tests.
//

import Foundation
import SwiftData
@testable import time_frame

/// Counts widget reloads without a WidgetKit host.
@MainActor
final class ReloadBox {
    var count = 0
}

@MainActor
struct InteractiveWidgetRig {
    let container: ModelContainer
    let clock: MockTimeSource
    let coordinator: SessionCoordinator
    let config: PomodoroConfiguration
    let store: WidgetProjectionStore
    let writer: WidgetProjectionWriter
    let router: WidgetControlActions
    let reloads: ReloadBox

    /// The projection currently in the shared store, if any.
    var projection: WidgetProjection? { store.read() }

    /// Convenience: perform a widget control action through the app-registered router,
    /// exactly as the shared intent's `perform()` would in the app process.
    @discardableResult
    func perform(_ action: WidgetControlAction) throws -> WidgetControlResult {
        try router.perform(action)
    }
}

/// A scratch, per-test App-Group-style store backed by a unique volatile suite.
@MainActor
func makeScratchWidgetStore() -> WidgetProjectionStore {
    let suite = "test.widget.control.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return WidgetProjectionStore(defaults: defaults)
}

/// Builds a fully-wired interactive-widget rig. The lifecycle fan-out and the router's own
/// post-action refresh both drive the writer, mirroring `time_frameApp` exactly.
@MainActor
func makeInteractiveWidgetRig(
    focus: TimeInterval = 600,
    short: TimeInterval = 300,
    long: TimeInterval = 900,
    before: Int = 4,
    total: Int = 4,
    seedDefault: Bool = true,
    today: TodaySummary? = nil
) throws -> InteractiveWidgetRig {
    let container = try makeInMemoryContainer()
    let clock = MockTimeSource()
    let coordinator = makeCoordinator(container, clock: clock)
    let config = try insertConfiguration(
        container, name: "Deep Work",
        focus: focus, short: short, long: long, before: before, total: total,
        isDefault: seedDefault
    )

    let store = makeScratchWidgetStore()
    let reloads = ReloadBox()
    let writer = WidgetProjectionWriter(
        coordinator: coordinator,
        store: store,
        now: { clock.now() },
        todayProvider: { today },
        reload: { reloads.count += 1 }
    )

    // Mirror the app: lifecycle events and auto-boundary transitions refresh the projection.
    coordinator.onLifecycleEvent = { [weak writer] event in writer?.handle(event) }
    coordinator.onMeaningfulTransition = { [weak writer] in writer?.update() }

    // The widget-control router: routes each action through the ONE AppIntentSessionActions
    // seam and refreshes the projection afterward — exactly as the app registers it.
    let router = WidgetControlRouting.makeActions(
        coordinator: coordinator,
        refreshProjection: { [weak writer] in writer?.update() }
    )

    // Publish an initial idle projection, like launch.
    writer.update()

    return InteractiveWidgetRig(
        container: container, clock: clock, coordinator: coordinator, config: config,
        store: store, writer: writer, router: router, reloads: reloads
    )
}
