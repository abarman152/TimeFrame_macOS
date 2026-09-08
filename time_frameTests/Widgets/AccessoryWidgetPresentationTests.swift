//
//  AccessoryWidgetPresentationTests.swift
//  time_frameTests (Milestone 21)
//
//  `AccessoryWidgetPresentation` (Shared/) is the pure mapper behind the iOS Lock Screen accessory
//  widget. It compiles into every target that links `Shared/` (including the macOS app), so it is
//  guarded here too: it must map every projection to a legible presentation, carry the countdown
//  anchors through FROZEN, keep configuration presentation-only, and degrade malformed/stale
//  projections to a safe, non-negative reading. Foundation-only and WidgetKit-free — provably not a
//  second clock (ADR-087).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Accessory widget presentation — pure mapper")
struct AccessoryWidgetPresentationTests {

    private let now = Date(timeIntervalSinceReferenceDate: 760_000_000)

    private func running() -> WidgetProjection {
        WidgetProjection(generatedAt: now, state: .running, phase: .focus, title: "Alpha",
                         currentIntervalIndex: 1, totalIntervals: 3, completedFocusCount: 0,
                         intervalStartedAt: now, intervalPlannedEndAt: now.addingTimeInterval(900))
    }

    @Test("The countdown anchors equal the projection anchors for every accessory family")
    func frozenAnchors() {
        let p = running()
        let expected = AccessoryCountdown.live(start: now, end: now.addingTimeInterval(900))
        #expect(AccessoryWidgetPresentation.circular(for: p, configuration: .default, now: now).countdown == expected)
        #expect(AccessoryWidgetPresentation.rectangular(for: p, configuration: .default, now: now).countdown == expected)
        #expect(AccessoryWidgetPresentation.inline(for: p, configuration: .default, now: now).countdown == expected)
    }

    @Test("Display mode selects content; timing is never affected by configuration")
    func configurationIsPresentationOnly() {
        let p = running()
        // Timer mode draws the live countdown; today/statistics draw a glance with no countdown.
        #expect(AccessoryWidgetPresentation.rectangular(
            for: p, configuration: TimeFrameWidgetConfiguration(displayMode: .timer), now: now).countdown != AccessoryCountdown.none)
        #expect(AccessoryWidgetPresentation.rectangular(
            for: p, configuration: TimeFrameWidgetConfiguration(displayMode: .today), now: now).countdown == AccessoryCountdown.none)
        #expect(AccessoryWidgetPresentation.rectangular(
            for: p, configuration: TimeFrameWidgetConfiguration(displayMode: .statistics), now: now).countdown == AccessoryCountdown.none)
    }

    @Test("Every session state yields a non-empty, safe presentation across all families")
    func everyStateIsSafe() {
        let states: [WidgetSessionState] = [.idle, .running, .paused, .completed, .interrupted, .unavailable]
        for state in states {
            let p = WidgetProjection(generatedAt: now, state: state, phase: state == .running ? .focus : .none,
                                     intervalStartedAt: now, intervalPlannedEndAt: now.addingTimeInterval(60),
                                     pausedRemainingSeconds: state == .paused ? 120 : nil)
            #expect(!AccessoryWidgetPresentation.circular(for: p, configuration: .default, now: now).accessibilityLabel.isEmpty)
            #expect(!AccessoryWidgetPresentation.rectangular(for: p, configuration: .default, now: now).title.isEmpty)
            #expect(!AccessoryWidgetPresentation.inline(for: p, configuration: .default, now: now).prefix.isEmpty)
        }
    }

    @Test("Malformed running/paused projections never produce a countdown or a negative duration")
    func malformedDegradesSafely() {
        // Running with no planned end.
        let noEnd = WidgetProjection(generatedAt: now, state: .running, phase: .focus, intervalStartedAt: now)
        #expect(AccessoryWidgetPresentation.circular(for: noEnd, configuration: .default, now: now).countdown == AccessoryCountdown.none)
        // Paused with a negative remaining → clamped to zero.
        let negative = WidgetProjection(generatedAt: now, state: .paused, phase: .focus, pausedRemainingSeconds: -5)
        #expect(AccessoryWidgetPresentation.rectangular(for: negative, configuration: .default, now: now).countdown == .frozen(seconds: 0))
    }
}
