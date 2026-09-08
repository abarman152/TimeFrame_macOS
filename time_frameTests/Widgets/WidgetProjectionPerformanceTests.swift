//
//  WidgetProjectionPerformanceTests.swift
//  time_frameTests (Milestone 14)
//
//  A bounded guard that widget projection + timeline generation stays cheap. The whole path
//  is pure value work — no database, no network, no I/O — so a realistic payload must build a
//  timeline (and round-trip through Codable) many thousands of times well within a generous
//  ceiling. The ceiling is deliberately loose so this never flakes on a busy CI machine; it
//  exists only to catch a pathological regression (e.g. accidental O(n²) or per-call I/O).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Widget projection performance")
struct WidgetProjectionPerformanceTests {

    private func realisticProjection(now: Date) -> WidgetProjection {
        WidgetProjection(
            generatedAt: now,
            state: .running,
            phase: .focus,
            title: "Write the milestone report",
            configurationName: "Deep Work",
            currentIntervalIndex: 3,
            totalIntervals: 6,
            completedFocusCount: 2,
            intervalStartedAt: now,
            intervalPlannedEndAt: now.addingTimeInterval(1500),
            focusSecondsToday: 7200,
            completedSessionsToday: 4,
            completedFocusIntervalsToday: 9,
            focusTrendToday: .up
        )
    }

    @Test("Building 10k configured timelines stays well within a generous ceiling")
    func timelineBuildingIsCheap() {
        let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let projection = realisticProjection(now: now)
        let config = TimeFrameWidgetConfiguration(displayMode: .statistics, destination: .history, showsCountdown: true)

        let start = Date()
        var entryCount = 0
        for _ in 0..<10_000 {
            let timeline = WidgetTimelineBuilder.timeline(projection: projection, configuration: config, now: now)
            entryCount += timeline.entries.count
        }
        let elapsed = Date().timeIntervalSince(start)

        #expect(entryCount == 20_000)          // 2 entries per running timeline × 10k
        #expect(elapsed < 2.0, "timeline building took \(elapsed)s")
    }

    @Test("Encoding + decoding 5k projections stays well within a generous ceiling")
    func codecIsCheap() throws {
        let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let projection = realisticProjection(now: now)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let start = Date()
        for _ in 0..<5_000 {
            let data = try encoder.encode(projection)
            let decoded = try decoder.decode(WidgetProjection.self, from: data)
            #expect(decoded.state == .running)
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 2.0, "codec round-trips took \(elapsed)s")
    }
}
