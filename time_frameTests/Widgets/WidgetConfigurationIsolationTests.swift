//
//  WidgetConfigurationIsolationTests.swift
//  time_frameTests (Milestone 14)
//
//  The strongest guarantee of the configurable widget: choosing or changing a widget
//  configuration is a PRESENTATION act that can never reach the timer. These tests wire the
//  REAL coordinator + engine (mock clock, heartbeat off) to a running session, then exercise
//  every widget-configuration path — building projections, building configured timelines,
//  and constructing configuration intents — and assert the coordinator, engine, session,
//  intervals, and SwiftData context are all left byte-for-byte untouched (ADR-064/068).
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Widget configuration isolation")
struct WidgetConfigurationIsolationTests {

    private let configs: [TimeFrameWidgetConfiguration] = [
        TimeFrameWidgetConfiguration(displayMode: .timer, destination: .timer, showsCountdown: true),
        TimeFrameWidgetConfiguration(displayMode: .today, destination: .today, showsCountdown: false),
        TimeFrameWidgetConfiguration(displayMode: .statistics, destination: .history, showsCountdown: true)
    ]

    @Test("Building configured timelines never mutates the coordinator, engine, session, or store")
    func configuringDoesNotMutateTimer() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 1500, total: 4)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)

        try coordinator.startSession(configuration: config, taskName: "Untouched")
        clock.advance(by: 42)

        // Capture authoritative state.
        let sessionID = coordinator.activeSession?.id
        let intervalCount = coordinator.activeSession?.intervals.count
        let stateBefore = coordinator.engine.state
        let indexBefore = coordinator.engine.currentIndex
        let remainingBefore = coordinator.engine.remaining
        // Persist any pending change from startSession first, so we can prove the widget
        // paths introduce NO further SwiftData writes.
        try? container.mainContext.save()
        #expect(container.mainContext.hasChanges == false)

        // Exercise every widget-configuration path.
        let now = clock.now()
        let projection = WidgetProjectionMapper.projection(
            from: coordinator, now: now,
            today: TodaySummary(focusSeconds: 600, completedSessions: 1,
                                completedFocusIntervals: 2, focusTrend: .up)
        )
        for config in configs {
            _ = WidgetTimelineBuilder.timeline(projection: projection, configuration: config, now: now)
            let intent = TimeFrameWidgetConfigurationIntent(
                content: .statistics, destination: .history, countdown: .hide
            )
            _ = intent.configuration
        }

        // Authoritative state is completely unchanged.
        #expect(coordinator.activeSession?.id == sessionID)
        #expect(coordinator.activeSession?.intervals.count == intervalCount)
        #expect(coordinator.engine.state == stateBefore)
        #expect(coordinator.engine.currentIndex == indexBefore)
        expectClose(coordinator.engine.remaining, remainingBefore)
        // And no SwiftData write happened as a side effect of any widget path.
        #expect(container.mainContext.hasChanges == false)
    }

    @Test("The projection is independent of configuration (the mapper never sees a config)")
    func projectionIndependentOfConfiguration() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 1500, total: 4)
        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        try coordinator.startSession(configuration: config, taskName: "Same")

        let now = clock.now()
        let projection = WidgetProjectionMapper.projection(from: coordinator, now: now)

        // The same projection drives every display mode; the config only changes rendering,
        // so the entries' underlying projection is identical across all configurations.
        for config in configs {
            let timeline = WidgetTimelineBuilder.timeline(projection: projection, configuration: config, now: now)
            #expect(timeline.entries.allSatisfy { $0.projection == projection })
        }
    }
}
