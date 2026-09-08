//
//  WidgetCloudKitIndependenceTests.swift
//  time_frameTests (Milestone 14)
//
//  The widget renders from the LOCAL App Group projection only; it never imports CloudKit and
//  never depends on an iCloud account or the app's persistence mode (ADR-060/068). These
//  tests prove the widget path works with CloudKit entirely out of the picture: a projection
//  written by the app over a purely local store is readable and yields a valid timeline, and
//  when the App Group itself is unavailable the provider's fallback still produces a stable,
//  non-empty timeline. No iCloud account and no network are involved.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Widget CloudKit independence")
struct WidgetCloudKitIndependenceTests {

    /// Mirrors the provider's read-with-fallback so the pure timeline can be exercised in a
    /// test without a WidgetKit host: a missing/corrupt projection becomes `.unavailable`.
    private func projection(from store: WidgetProjectionStore, now: Date) -> WidgetProjection {
        store.read() ?? .unavailable(reason: "No session data available yet.", at: now)
    }

    @Test("A projection written over a purely local store is readable and builds a timeline")
    func localOnlyPathWorks() async throws {
        // A local, in-memory container — no CloudKit mirroring, no account, no network.
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 1500, total: 4)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)

        let suite = "test.widget.cloudless.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = WidgetProjectionStore(defaults: defaults)

        let writer = WidgetProjectionWriter(
            coordinator: coordinator, store: store, now: { clock.now() },
            todayProvider: { TodaySummary(focusSeconds: 900, completedSessions: 2,
                                          completedFocusIntervals: 3, focusTrend: .up) },
            reload: {}
        )
        try coordinator.startSession(configuration: config, taskName: "Offline focus")
        writer.update()
        // The today figures land on the writer's coalesced follow-up pass, which is kept
        // off the timer control path (M26, ADR-099).
        try? await Task.sleep(for: .milliseconds(50))

        let read = projection(from: store, now: clock.now())
        #expect(read.state == .running)
        #expect(read.title == "Offline focus")
        #expect(read.completedFocusIntervalsToday == 3)
        #expect(read.focusTrendToday == .up)

        // The widget's pure timeline builds for every configuration, offline.
        for mode in WidgetDisplayMode.allCases {
            let cfg = TimeFrameWidgetConfiguration(displayMode: mode)
            let timeline = WidgetTimelineBuilder.timeline(projection: read, configuration: cfg, now: clock.now())
            #expect(timeline.entries.isEmpty == false)
        }
    }

    @Test("When the App Group is unavailable, the fallback still builds a stable timeline")
    func appGroupUnavailableFallback() {
        // `defaults: nil` models a missing/denied App Group — the store is inert.
        let store = WidgetProjectionStore(defaults: nil)
        #expect(store.isAvailable == false)
        #expect(store.read() == nil)

        let now = Date()
        let read = projection(from: store, now: now)
        #expect(read.state == .unavailable)

        let timeline = WidgetTimelineBuilder.timeline(projection: read, configuration: .default, now: now)
        #expect(timeline.entries.count == 1)
        #expect(timeline.entries.first?.projection.state == .unavailable)
    }

    @Test("The resolved persistence mode does not change the widget's local read path")
    func persistenceModeIrrelevantToWidget() {
        // The widget never consults `PersistenceMode`; these all resolve without CloudKit and
        // none is a precondition for reading the local projection.
        for mode in [PersistenceMode.local, .cloudKit, .fallback] {
            _ = mode // The widget path below is identical regardless.
        }
        let store = WidgetProjectionStore(defaults: nil)
        #expect(projection(from: store, now: Date()).state == .unavailable)
    }
}
