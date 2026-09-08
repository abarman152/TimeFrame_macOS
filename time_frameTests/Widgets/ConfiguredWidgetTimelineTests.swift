//
//  ConfiguredWidgetTimelineTests.swift
//  time_frameTests (Milestone 14)
//
//  The pure `WidgetTimelineBuilder` turns a projection + configuration + now into the entry
//  descriptors and reload policy the widget provider renders. These tests pin the entries and
//  reload policy for every state (idle / running / paused / completed / interrupted /
//  unavailable) AND prove the crucial invariant: the configuration changes *presentation*
//  only — switching Timer / Today / Statistics never alters the entry instants or the reload
//  policy, so a configuration change can never introduce a second clock (ADR-064).
//
//  Widget *families* (small / medium) are a rendering concern handled by the SwiftUI view and
//  exercised by the extension's deterministic `#Preview`s; the timeline itself is
//  family-independent (the builder takes no family), which these tests make explicit.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Configured widget timeline")
struct ConfiguredWidgetTimelineTests {

    private let now = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func running(endInMinutes minutes: Double) -> WidgetProjection {
        WidgetProjection(
            generatedAt: now,
            state: .running,
            phase: .focus,
            title: "Deep work",
            currentIntervalIndex: 1,
            totalIntervals: 4,
            intervalStartedAt: now,
            intervalPlannedEndAt: now.addingTimeInterval(minutes * 60)
        )
    }

    private let allConfigs: [TimeFrameWidgetConfiguration] = [
        TimeFrameWidgetConfiguration(displayMode: .timer, destination: .timer, showsCountdown: true),
        TimeFrameWidgetConfiguration(displayMode: .today, destination: .today, showsCountdown: true),
        TimeFrameWidgetConfiguration(displayMode: .statistics, destination: .statistics, showsCountdown: false)
    ]

    // MARK: Per-state timelines

    @Test("A running interval yields now + planned-end entries and reloads at the end")
    func runningTimeline() {
        let projection = running(endInMinutes: 25)
        let end = projection.intervalPlannedEndAt!
        let timeline = WidgetTimelineBuilder.timeline(
            projection: projection, configuration: .default, now: now
        )
        #expect(timeline.entries.map(\.date) == [now, end])
        #expect(timeline.refresh == .after(end))
        // Each entry carries the same projection + configuration.
        #expect(timeline.entries.allSatisfy { $0.projection == projection })
        #expect(timeline.entries.allSatisfy { $0.configuration == .default })
    }

    @Test("A paused projection yields one frozen entry and never schedules a tick")
    func pausedTimeline() {
        let projection = WidgetProjection(
            generatedAt: now, state: .paused, phase: .focus, pausedRemainingSeconds: 600
        )
        let timeline = WidgetTimelineBuilder.timeline(
            projection: projection, configuration: .default, now: now
        )
        #expect(timeline.entries.map(\.date) == [now])
        #expect(timeline.refresh == .never)
    }

    @Test("Settled states yield one entry and a conservative heartbeat")
    func settledTimelines() {
        let states: [WidgetSessionState] = [.idle, .completed, .interrupted, .unavailable]
        let heartbeat = now.addingTimeInterval(WidgetTimelinePolicy.conservativeRefreshInterval)
        for state in states {
            let projection = WidgetProjection(generatedAt: now, state: state, phase: .none)
            let timeline = WidgetTimelineBuilder.timeline(
                projection: projection, configuration: .default, now: now
            )
            #expect(timeline.entries.map(\.date) == [now], "state \(state)")
            #expect(timeline.refresh == .after(heartbeat), "state \(state)")
        }
    }

    // MARK: Configuration is presentation-only (never timing)

    @Test("Display mode never changes the entry instants or reload policy")
    func configurationDoesNotAffectTiming() {
        let projections = [
            running(endInMinutes: 25),
            WidgetProjection(generatedAt: now, state: .paused, phase: .focus, pausedRemainingSeconds: 300),
            WidgetProjection(generatedAt: now, state: .idle, phase: .none),
            WidgetProjection(generatedAt: now, state: .completed, phase: .none),
            WidgetProjection(generatedAt: now, state: .interrupted, phase: .none),
            .unavailable(reason: "x", at: now)
        ]
        for projection in projections {
            let timelines = allConfigs.map {
                WidgetTimelineBuilder.timeline(projection: projection, configuration: $0, now: now)
            }
            let dates = timelines.map { $0.entries.map(\.date) }
            let refreshes = timelines.map(\.refresh)
            // All three display modes produce identical timing for the same projection.
            #expect(dates.allSatisfy { $0 == dates[0] }, "timing differs by config for \(projection.state)")
            #expect(refreshes.allSatisfy { $0 == refreshes[0] }, "reload differs by config for \(projection.state)")
        }
    }

    @Test("The chosen configuration is carried onto every entry unchanged")
    func configurationCarried() {
        let projection = running(endInMinutes: 25)
        for config in allConfigs {
            let timeline = WidgetTimelineBuilder.timeline(
                projection: projection, configuration: config, now: now
            )
            #expect(timeline.entries.allSatisfy { $0.configuration == config })
        }
    }

    @Test("A running interval already past its end recovers with a conservative reload")
    func runningPastEnd() {
        let projection = running(endInMinutes: -5)   // planned end already behind now
        let timeline = WidgetTimelineBuilder.timeline(
            projection: projection, configuration: .default, now: now
        )
        #expect(timeline.entries.map(\.date) == [now])
        #expect(timeline.refresh == .after(now.addingTimeInterval(WidgetTimelinePolicy.conservativeRefreshInterval)))
    }
}
