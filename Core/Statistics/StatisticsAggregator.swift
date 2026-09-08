//
//  StatisticsAggregator.swift
//  time_frame
//
//  The pure statistics engine (Milestone 10). It turns persisted history
//  (`[SessionStatInput]`) into an immutable `StatisticsSnapshot` for a date range,
//  using the user's `Calendar` for all day/period grouping. It is deterministic,
//  `nonisolated`, and free of SwiftData/SwiftUI/timer dependencies, so it is tested
//  without a store or a running UI and can never affect timer correctness.
//
//  Attribution rules (documented in docs/19-STATISTICS.md):
//  • Session-level metrics (started / completed / stopped / interrupted, completion
//    rate, longest session) count a session when its `startedAt` falls in the range.
//  • Interval-level metrics (focus/break time, focus-interval count, daily and
//    configuration breakdowns) count a *completed* interval when its end instant
//    (`endedAt`, falling back to `startedAt`) falls in the range. Attributing by the
//    interval's own timestamp — not the session's — is what makes a session that
//    crosses midnight bank its focus on the correct day.
//

import Foundation

/// Deterministic aggregation of persisted history into a `StatisticsSnapshot`.
nonisolated enum StatisticsAggregator {

    /// Produces the snapshot for `range` from `sessions`, grouping by `calendar`.
    static func aggregate(
        sessions: [SessionStatInput],
        range: StatisticsDateRange,
        calendar: Calendar = .current
    ) -> StatisticsSnapshot {

        // MARK: Session-level metrics (attributed by session start)
        let started = sessions.filter { session in
            guard let start = session.startedAt else { return false }
            return range.contains(start)
        }

        var completedSessions = 0
        var stoppedSessions = 0
        var interruptedSessions = 0
        var longestFocusSession: TimeInterval = 0
        // Completed sessions per day, for the "sessions completed" chart.
        var completedSessionsByDay: [Date: Int] = [:]

        for session in started {
            switch session.status {
            case .completed: completedSessions += 1
            case .cancelled: stoppedSessions += 1
            case .interrupted: interruptedSessions += 1
            case .planned, .running, .paused: break
            }
            longestFocusSession = Swift.max(longestFocusSession, session.completedFocusDuration)

            if session.status == .completed, let start = session.startedAt {
                let day = calendar.startOfDay(for: start)
                completedSessionsByDay[day, default: 0] += 1
            }
        }

        // MARK: Interval-level metrics (attributed by interval end)
        var focusDuration: TimeInterval = 0
        var breakDuration: TimeInterval = 0
        var completedFocusIntervals = 0
        var focusByDay: [Date: TimeInterval] = [:]
        var breakByDay: [Date: TimeInterval] = [:]
        var focusIntervalsByDay: [Date: Int] = [:]
        var focusByConfiguration: [String: (duration: TimeInterval, count: Int)] = [:]

        for session in sessions {
            for interval in session.intervals {
                guard interval.isCompleted else { continue }
                guard let instant = interval.attributionDate, range.contains(instant) else { continue }
                let day = calendar.startOfDay(for: instant)

                if interval.phase == .focus {
                    focusDuration += interval.plannedDuration
                    completedFocusIntervals += 1
                    focusByDay[day, default: 0] += interval.plannedDuration
                    focusIntervalsByDay[day, default: 0] += 1

                    let name = configurationName(for: interval, in: session)
                    var entry = focusByConfiguration[name] ?? (0, 0)
                    entry.duration += interval.plannedDuration
                    entry.count += 1
                    focusByConfiguration[name] = entry
                } else {
                    breakDuration += interval.plannedDuration
                    breakByDay[day, default: 0] += interval.plannedDuration
                }
            }
        }

        // MARK: Daily breakdown — one continuous bucket per calendar day in the range.
        let daily = dailyBuckets(
            range: range,
            calendar: calendar,
            focusByDay: focusByDay,
            breakByDay: breakByDay,
            focusIntervalsByDay: focusIntervalsByDay,
            completedSessionsByDay: completedSessionsByDay
        )

        // MARK: Configuration breakdown — descending by focus time, then name for stability.
        let configurations = focusByConfiguration
            .map { ConfigurationStatistics(configurationName: $0.key,
                                           focusDuration: $0.value.duration,
                                           completedFocusIntervals: $0.value.count) }
            .sorted {
                $0.focusDuration != $1.focusDuration
                    ? $0.focusDuration > $1.focusDuration
                    : $0.configurationName < $1.configurationName
            }

        return StatisticsSnapshot(
            range: range,
            startedSessions: started.count,
            completedSessions: completedSessions,
            stoppedSessions: stoppedSessions,
            interruptedSessions: interruptedSessions,
            focusDuration: focusDuration,
            breakDuration: breakDuration,
            completedFocusIntervals: completedFocusIntervals,
            longestFocusSession: longestFocusSession,
            daily: daily,
            configurations: configurations
        )
    }

    /// Convenience: aggregate current and previous ranges and pair the focus totals
    /// into a trend comparison in one call.
    static func comparison(
        sessions: [SessionStatInput],
        period: StatisticsPeriod,
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> StatisticsComparison {
        let current = aggregate(sessions: sessions,
                                range: period.range(reference: reference, calendar: calendar),
                                calendar: calendar)
        let previous = aggregate(sessions: sessions,
                                 range: period.previousRange(reference: reference, calendar: calendar),
                                 calendar: calendar)
        return StatisticsComparison(current: current.focusDuration, previous: previous.focusDuration)
    }

    // MARK: - Helpers

    /// The configuration name a focus interval is attributed to: its own frozen name
    /// when present (multi-configuration plans), otherwise the session-level frozen
    /// name, otherwise a neutral label. Always a frozen value, so a later rename or
    /// delete of the configuration never rewrites history.
    private static func configurationName(for interval: IntervalStatInput, in session: SessionStatInput) -> String {
        if !interval.configurationName.isEmpty { return interval.configurationName }
        if !session.configurationName.isEmpty { return session.configurationName }
        return "No configuration"
    }

    /// Builds a continuous day-by-day breakdown covering `[range.start, range.end)`.
    /// Days are stepped with `Calendar` (DST-correct), and every day in the span is
    /// present so charts render a gap-free axis even for days with no activity.
    private static func dailyBuckets(
        range: StatisticsDateRange,
        calendar: Calendar,
        focusByDay: [Date: TimeInterval],
        breakByDay: [Date: TimeInterval],
        focusIntervalsByDay: [Date: Int],
        completedSessionsByDay: [Date: Int]
    ) -> [DailyStatistics] {
        var days: [DailyStatistics] = []
        var cursor = calendar.startOfDay(for: range.start)
        let limit = range.end
        // Guard against a pathological non-advancing cursor.
        var safety = 0
        while cursor < limit && safety < 100_000 {
            days.append(DailyStatistics(
                date: cursor,
                focusDuration: focusByDay[cursor] ?? 0,
                breakDuration: breakByDay[cursor] ?? 0,
                completedFocusIntervals: focusIntervalsByDay[cursor] ?? 0,
                completedSessions: completedSessionsByDay[cursor] ?? 0
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
            safety += 1
        }
        return days
    }
}
