//
//  TimeFrameWidgetPreviewData.swift
//  TimeFrameWidgets (Milestone 11)
//
//  Deterministic sample projections for previews. Every value is a fixed constant — no
//  `Date.now`, no SwiftData, no `UserDefaults`, no live engine — so previews render the
//  same way every time and exercise each widget state in isolation.
//

import Foundation

enum WidgetPreviewData {

    /// A fixed reference instant so previews are fully deterministic.
    static let base = Date(timeIntervalSinceReferenceDate: 760_000_000)

    // MARK: Sample configurations (Milestone 14)

    static let timerConfig = TimeFrameWidgetConfiguration(
        displayMode: .timer, destination: .timer, showsCountdown: true
    )
    static let timerNoCountdownConfig = TimeFrameWidgetConfiguration(
        displayMode: .timer, destination: .timer, showsCountdown: false
    )
    static let todayConfig = TimeFrameWidgetConfiguration(
        displayMode: .today, destination: .today, showsCountdown: true
    )
    static let statisticsConfig = TimeFrameWidgetConfiguration(
        displayMode: .statistics, destination: .statistics, showsCountdown: true
    )

    // MARK: Sample projections

    static let idle = WidgetProjection.idle(
        at: base,
        focusSecondsToday: 75 * 60,
        completedSessionsToday: 2,
        completedFocusIntervalsToday: 3,
        focusTrendToday: .up
    )

    static let focusRunning = WidgetProjection(
        generatedAt: base,
        state: .running,
        phase: .focus,
        title: "Write milestone report",
        configurationName: "Classic Pomodoro",
        currentIntervalIndex: 2,
        totalIntervals: 4,
        completedFocusCount: 1,
        intervalStartedAt: base,
        intervalPlannedEndAt: base.addingTimeInterval(25 * 60),
        focusSecondsToday: 50 * 60,
        completedSessionsToday: 1,
        completedFocusIntervalsToday: 2,
        focusTrendToday: .up
    )

    static let breakRunning = WidgetProjection(
        generatedAt: base,
        state: .running,
        phase: .shortBreak,
        title: "Write milestone report",
        configurationName: "Classic Pomodoro",
        currentIntervalIndex: 2,
        totalIntervals: 4,
        completedFocusCount: 2,
        intervalStartedAt: base,
        intervalPlannedEndAt: base.addingTimeInterval(5 * 60),
        focusSecondsToday: 75 * 60,
        completedSessionsToday: 1
    )

    static let paused = WidgetProjection(
        generatedAt: base,
        state: .paused,
        phase: .focus,
        title: "Design review",
        configurationName: "Deep Work",
        currentIntervalIndex: 3,
        totalIntervals: 5,
        completedFocusCount: 2,
        pausedRemainingSeconds: 12 * 60 + 34,
        focusSecondsToday: 90 * 60,
        completedSessionsToday: 2
    )

    static let completed = WidgetProjection(
        generatedAt: base,
        state: .completed,
        phase: .none,
        title: "Write milestone report",
        configurationName: "Classic Pomodoro",
        totalIntervals: 4,
        completedFocusCount: 4,
        focusSecondsToday: 100 * 60,
        completedSessionsToday: 3
    )

    static let interrupted = WidgetProjection(
        generatedAt: base,
        state: .interrupted,
        phase: .none,
        title: "Interrupted task"
    )

    static let unavailable = WidgetProjection.unavailable(
        reason: "No session data available yet.",
        at: base
    )
}
