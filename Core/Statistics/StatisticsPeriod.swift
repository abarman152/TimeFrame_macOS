//
//  StatisticsPeriod.swift
//  time_frame
//
//  Date-range semantics for statistics (Milestone 10). Every range is resolved with
//  the user's own `Calendar` so grouping respects the local time zone, midnight
//  boundaries, and DST transitions — day/week/month steps go through `Calendar`
//  arithmetic (`dateInterval`, `date(byAdding:)`), never a hard-coded 86 400 seconds,
//  so a 23- or 25-hour DST day is handled correctly. Pure and Sendable: no SwiftData,
//  SwiftUI, or `Date.now` capture inside the type (the reference date is injected),
//  which makes range resolution deterministically testable.
//

import Foundation

/// A resolved half-open date range `[start, end)`. Half-open so adjacent periods
/// (yesterday/today, last week/this week) never double-count the boundary instant.
nonisolated struct StatisticsDateRange: Equatable, Sendable, Hashable {
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        self.start = start
        // Defend against an inverted range (e.g. a custom end before its start).
        self.end = Swift.max(start, end)
    }

    /// Whether `date` falls in `[start, end)`.
    func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// Whether a session with these bounds could contribute **any** metric to this
    /// range — the single definition of "relevant to a period" (M26, ADR-100).
    ///
    /// The aggregator attributes session-level metrics by `startedAt` and
    /// interval-level metrics by a completed interval's end instant. Every interval
    /// end necessarily lies within `[session.startedAt, session.endedAt]` (a session's
    /// `endedAt` is stamped from its last completed interval), and an open session has
    /// no end yet. So a session can only contribute when
    /// `startedAt < range.end` **and** `(endedAt ?? .distantFuture) >= range.start`.
    ///
    /// This is an exact **superset** test: it admits every session that could
    /// contribute and excludes only sessions whose entire span lies outside the
    /// range. Aggregating the admitted subset therefore yields byte-identical results
    /// to aggregating all of history, while the caller avoids faulting in the
    /// intervals of every session it can never need.
    func mayContainActivity(startedAt: Date?, endedAt: Date?) -> Bool {
        guard let startedAt, startedAt < end else { return false }
        return (endedAt ?? .distantFuture) >= start
    }

    /// The number of whole calendar days the range spans, in the given calendar.
    func dayCount(calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

/// A statistics reporting period. Calendar-natural cases resolve against the user's
/// calendar; `.custom` carries user-picked day bounds (inclusive of both days, then
/// normalised to day boundaries when resolved).
nonisolated enum StatisticsPeriod: Hashable, Sendable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    /// Inclusive `[startDay ... endDay]`, normalised to `[startOfDay(start), startOfDay(end)+1day)`.
    case custom(start: Date, end: Date)

    /// Resolves the period to a concrete half-open range in the given calendar,
    /// relative to `reference` (defaults to now for live use; injected in tests).
    func range(reference: Date = .now, calendar: Calendar = .current) -> StatisticsDateRange {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: reference)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return StatisticsDateRange(start: start, end: end)

        case .yesterday:
            let today = calendar.startOfDay(for: reference)
            let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return StatisticsDateRange(start: start, end: today)

        case .thisWeek:
            let interval = calendar.dateInterval(of: .weekOfYear, for: reference)
                ?? DateInterval(start: calendar.startOfDay(for: reference), duration: 0)
            return StatisticsDateRange(start: interval.start, end: interval.end)

        case .lastWeek:
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: reference)
                ?? DateInterval(start: calendar.startOfDay(for: reference), duration: 0)
            let start = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start) ?? thisWeek.start
            return StatisticsDateRange(start: start, end: thisWeek.start)

        case .thisMonth:
            let interval = calendar.dateInterval(of: .month, for: reference)
                ?? DateInterval(start: calendar.startOfDay(for: reference), duration: 0)
            return StatisticsDateRange(start: interval.start, end: interval.end)

        case .lastMonth:
            let thisMonth = calendar.dateInterval(of: .month, for: reference)
                ?? DateInterval(start: calendar.startOfDay(for: reference), duration: 0)
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonth.start) ?? thisMonth.start
            return StatisticsDateRange(start: start, end: thisMonth.start)

        case let .custom(start, end):
            let s = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: end)
            let e = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return StatisticsDateRange(start: s, end: e)
        }
    }

    /// The immediately-preceding equivalent range, used for trend comparison. Each
    /// calendar-natural period maps to the natural prior period (so month/week length
    /// differences are respected); a custom range shifts back by its own day span.
    func previousRange(reference: Date = .now, calendar: Calendar = .current) -> StatisticsDateRange {
        switch self {
        case .today:
            return StatisticsPeriod.yesterday.range(reference: reference, calendar: calendar)

        case .yesterday:
            let today = calendar.startOfDay(for: reference)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: yesterday) ?? yesterday
            return StatisticsDateRange(start: dayBefore, end: yesterday)

        case .thisWeek:
            return StatisticsPeriod.lastWeek.range(reference: reference, calendar: calendar)

        case .lastWeek:
            let last = StatisticsPeriod.lastWeek.range(reference: reference, calendar: calendar)
            let start = calendar.date(byAdding: .weekOfYear, value: -1, to: last.start) ?? last.start
            return StatisticsDateRange(start: start, end: last.start)

        case .thisMonth:
            return StatisticsPeriod.lastMonth.range(reference: reference, calendar: calendar)

        case .lastMonth:
            let last = StatisticsPeriod.lastMonth.range(reference: reference, calendar: calendar)
            let start = calendar.date(byAdding: .month, value: -1, to: last.start) ?? last.start
            return StatisticsDateRange(start: start, end: last.start)

        case .custom:
            let current = range(reference: reference, calendar: calendar)
            let days = current.dayCount(calendar: calendar)
            let start = calendar.date(byAdding: .day, value: -days, to: current.start) ?? current.start
            return StatisticsDateRange(start: start, end: current.start)
        }
    }
}
