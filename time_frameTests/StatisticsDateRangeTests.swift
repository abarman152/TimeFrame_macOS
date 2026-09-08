//
//  StatisticsDateRangeTests.swift
//  time_frameTests
//
//  Tests for `StatisticsPeriod` range resolution: today/yesterday/week/month/custom,
//  midnight boundaries, time-zone correctness, and DST-sensitive spans. All ranges are
//  resolved against an injected fixed reference date and calendar, so results never
//  depend on when the suite runs.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Statistics date ranges — fixed periods")
struct StatisticsFixedRangeTests {

    @Test("Today is midnight to next midnight in the user's calendar")
    func today() {
        let cal = statCalendar()
        let ref = statDate(2026, 8, 14, 15, 30, calendar: cal)
        let range = StatisticsPeriod.today.range(reference: ref, calendar: cal)
        #expect(range.start == cal.startOfDay(for: ref))
        #expect(range.end == cal.date(byAdding: .day, value: 1, to: range.start))
        #expect(range.contains(ref))
        #expect(range.dayCount(calendar: cal) == 1)
    }

    @Test("Yesterday is the full prior day and ends where today begins")
    func yesterday() {
        let cal = statCalendar()
        let ref = statDate(2026, 8, 14, 15, 30, calendar: cal)
        let yesterday = StatisticsPeriod.yesterday.range(reference: ref, calendar: cal)
        let today = StatisticsPeriod.today.range(reference: ref, calendar: cal)
        #expect(yesterday.end == today.start)
        #expect(yesterday.dayCount(calendar: cal) == 1)
        #expect(!yesterday.contains(ref))
    }

    @Test("This week contains the reference and spans seven days")
    func thisWeek() {
        let cal = statCalendar()
        let ref = statDate(2026, 8, 14, 15, 30, calendar: cal)
        let range = StatisticsPeriod.thisWeek.range(reference: ref, calendar: cal)
        #expect(range.contains(ref))
        #expect(range.dayCount(calendar: cal) == 7)
        #expect(cal.component(.weekday, from: range.start) == cal.firstWeekday)
        #expect(range.start == cal.startOfDay(for: range.start))
    }

    @Test("Last week immediately precedes this week")
    func lastWeek() {
        let cal = statCalendar()
        let ref = statDate(2026, 8, 14, 15, 30, calendar: cal)
        let thisWeek = StatisticsPeriod.thisWeek.range(reference: ref, calendar: cal)
        let lastWeek = StatisticsPeriod.lastWeek.range(reference: ref, calendar: cal)
        #expect(lastWeek.end == thisWeek.start)
        #expect(lastWeek.dayCount(calendar: cal) == 7)
    }

    @Test("This month is the whole calendar month")
    func thisMonth() {
        let cal = statCalendar()
        let ref = statDate(2026, 8, 14, 15, 30, calendar: cal)
        let range = StatisticsPeriod.thisMonth.range(reference: ref, calendar: cal)
        #expect(range.start == statDate(2026, 8, 1, 0, 0, calendar: cal))
        #expect(range.end == statDate(2026, 9, 1, 0, 0, calendar: cal))
        #expect(range.dayCount(calendar: cal) == 31)
    }

    @Test("Last month immediately precedes this month and respects month length")
    func lastMonth() {
        let cal = statCalendar()
        let ref = statDate(2026, 8, 14, 15, 30, calendar: cal)
        let range = StatisticsPeriod.lastMonth.range(reference: ref, calendar: cal)
        #expect(range.start == statDate(2026, 7, 1, 0, 0, calendar: cal))
        #expect(range.end == statDate(2026, 8, 1, 0, 0, calendar: cal))
        #expect(range.dayCount(calendar: cal) == 31) // July
    }

    @Test("Custom range is inclusive of both chosen days")
    func customInclusive() {
        let cal = statCalendar()
        let start = statDate(2026, 8, 10, 9, 0, calendar: cal)
        let end = statDate(2026, 8, 12, 21, 0, calendar: cal)
        let range = StatisticsPeriod.custom(start: start, end: end).range(calendar: cal)
        #expect(range.start == cal.startOfDay(for: start))
        #expect(range.end == cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)))
        #expect(range.dayCount(calendar: cal) == 3) // 10th, 11th, 12th
    }
}

@Suite("Statistics date ranges — boundaries and time zones")
struct StatisticsBoundaryTests {

    @Test("An interval ending exactly at midnight belongs to the new day")
    func midnightBoundary() {
        let cal = statCalendar()
        // 00:00 on the 14th is the start of "today" and the end of "yesterday" (half-open).
        let midnight = cal.startOfDay(for: statDate(2026, 8, 14, 1, 0, calendar: cal))
        let today = StatisticsPeriod.today.range(reference: statDate(2026, 8, 14, 12, 0, calendar: cal), calendar: cal)
        let yesterday = StatisticsPeriod.yesterday.range(reference: statDate(2026, 8, 14, 12, 0, calendar: cal), calendar: cal)
        #expect(today.contains(midnight))       // included in today
        #expect(!yesterday.contains(midnight))  // excluded from yesterday
    }

    @Test("Aggregation groups by the calendar's time zone, not UTC")
    func timeZoneGrouping() {
        let cal = statCalendar(timeZone: "America/New_York")
        // 23:30 local on the 14th — a late-night focus that is already the 15th in UTC.
        let lateNight = statDate(2026, 8, 14, 23, 30, calendar: cal)
        let session = statSession(startedAt: lateNight, intervals: [statFocus(30 * 60, endedAt: lateNight)])
        let today = StatisticsPeriod.today.range(reference: statDate(2026, 8, 14, 12, 0, calendar: cal), calendar: cal)
        let snapshot = StatisticsAggregator.aggregate(sessions: [session], range: today, calendar: cal)
        #expect(snapshot.focusDuration == 30 * 60) // lands on the local day, not the UTC one
    }

    @Test("A week spanning a spring-forward DST change still has seven day buckets")
    func dstWeekHasSevenDays() {
        // US spring-forward 2026: Sunday 8 March. The week containing it still has 7 days.
        let cal = statCalendar(timeZone: "America/New_York")
        let ref = statDate(2026, 3, 9, 12, 0, calendar: cal) // Monday after the change
        let range = StatisticsPeriod.thisWeek.range(reference: ref, calendar: cal)
        // Aggregate an empty set just to exercise the DST-correct day-bucket stepping.
        let snapshot = StatisticsAggregator.aggregate(sessions: [], range: range, calendar: cal)
        #expect(snapshot.daily.count == 7)
        // Every bucket is the start of its own local day (no drift from a 23-hour day).
        for day in snapshot.daily {
            #expect(day.date == cal.startOfDay(for: day.date))
        }
    }

    @Test("A focus interval on a spring-forward day is attributed to that day")
    func dstDayAttribution() {
        let cal = statCalendar(timeZone: "America/New_York")
        let dstDay = statDate(2026, 3, 8, 10, 0, calendar: cal) // the 23-hour day, 10am local
        let session = statSession(startedAt: dstDay, intervals: [statFocus(45 * 60, endedAt: dstDay)])
        let range = StatisticsPeriod.custom(start: dstDay, end: dstDay).range(calendar: cal)
        let snapshot = StatisticsAggregator.aggregate(sessions: [session], range: range, calendar: cal)
        #expect(snapshot.daily.count == 1)
        #expect(snapshot.daily[0].focusDuration == 45 * 60)
    }
}
