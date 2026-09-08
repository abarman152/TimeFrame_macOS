//
//  StatisticsTestSupport.swift
//  time_frameTests
//
//  Deterministic fixtures for the Milestone 10 statistics suites. Every helper builds
//  pure `SessionStatInput`/`IntervalStatInput` values from *fixed* dates and an
//  injected `Calendar`, so aggregation tests never depend on the machine's current
//  date, locale, or time zone.
//

import Foundation
@testable import time_frame

/// A fixed calendar for statistics tests. Monday-first so week ranges are
/// deterministic; time zone is explicit so midnight/DST behaviour is reproducible.
nonisolated func statCalendar(timeZone: String = "America/New_York") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZone)!
    calendar.firstWeekday = 2 // Monday
    return calendar
}

/// Builds a fixed date in the given calendar's time zone.
nonisolated func statDate(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 12, _ minute: Int = 0,
    calendar: Calendar = statCalendar()
) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components)!
}

/// A bounded range that comfortably spans every fixture (all fixtures live in 2026),
/// for "map everything" assertions. Kept bounded so the continuous daily-bucket axis
/// stays small — production ranges are always bounded too.
nonisolated let allTimeRange = StatisticsDateRange(
    start: statDate(2026, 1, 1, 0, 0),
    end: statDate(2027, 1, 1, 0, 0)
)

/// A completed (by default) focus interval attributed to `endedAt`.
nonisolated func statFocus(
    _ duration: TimeInterval = 25 * 60,
    status: IntervalStatus = .completed,
    endedAt: Date?,
    startedAt: Date? = nil,
    config: String = ""
) -> IntervalStatInput {
    IntervalStatInput(
        phase: .focus,
        status: status,
        plannedDuration: duration,
        startedAt: startedAt ?? endedAt,
        endedAt: endedAt,
        configurationName: config
    )
}

/// A completed (by default) break interval attributed to `endedAt`.
nonisolated func statBreak(
    _ duration: TimeInterval = 5 * 60,
    phase: TimerPhase = .shortBreak,
    status: IntervalStatus = .completed,
    endedAt: Date?,
    startedAt: Date? = nil
) -> IntervalStatInput {
    IntervalStatInput(
        phase: phase,
        status: status,
        plannedDuration: duration,
        startedAt: startedAt ?? endedAt,
        endedAt: endedAt,
        configurationName: ""
    )
}

/// A session wrapping the given intervals.
nonisolated func statSession(
    status: SessionStatus = .completed,
    startedAt: Date?,
    endedAt: Date? = nil,
    config: String = "Classic Pomodoro",
    task: String = "Focus",
    intervals: [IntervalStatInput] = []
) -> SessionStatInput {
    SessionStatInput(
        id: UUID(),
        taskName: task,
        configurationName: config,
        status: status,
        startedAt: startedAt,
        endedAt: endedAt,
        intervals: intervals
    )
}
