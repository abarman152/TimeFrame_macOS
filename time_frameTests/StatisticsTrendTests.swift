//
//  StatisticsTrendTests.swift
//  time_frameTests
//
//  Tests for `StatisticsComparison` and the aggregator's period-over-period trend:
//  positive/negative change, a zero previous period (nil percentage), and identical
//  periods. Also verifies `previousRange` picks the correct immediately-preceding span.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Statistics trend — comparison arithmetic")
struct StatisticsComparisonTests {

    @Test("Positive change reports the right difference and percentage")
    func positiveChange() {
        let c = StatisticsComparison(current: 12 * 3600 + 40 * 60, previous: 10 * 3600 + 20 * 60)
        #expect(c.absoluteDifference == 2 * 3600 + 20 * 60) // +2h20m
        let pct = try! #require(c.percentageChange)
        #expect(abs(pct - (140.0 / 620.0)) < 0.0001)        // +22.58%
        #expect(c.direction == .up)
    }

    @Test("Negative change is reported as a downward direction")
    func negativeChange() {
        let c = StatisticsComparison(current: 1 * 3600, previous: 2 * 3600)
        #expect(c.absoluteDifference == -1 * 3600)
        let pct = try! #require(c.percentageChange)
        #expect(abs(pct - (-0.5)) < 0.0001)
        #expect(c.direction == .down)
    }

    @Test("A zero previous period yields a nil percentage (no divide by zero)")
    func zeroPreviousNilPercentage() {
        let c = StatisticsComparison(current: 3600, previous: 0)
        #expect(c.percentageChange == nil)
        #expect(c.absoluteDifference == 3600)
        #expect(c.direction == .up)
    }

    @Test("Identical periods report flat with zero change")
    func identicalPeriodsFlat() {
        let c = StatisticsComparison(current: 3600, previous: 3600)
        #expect(c.absoluteDifference == 0)
        #expect(c.percentageChange == 0)
        #expect(c.direction == .flat)
    }
}

@Suite("Statistics trend — period-over-period")
struct StatisticsPeriodTrendTests {

    @Test("Comparison pairs this period's focus against the previous equivalent period")
    func todayVsYesterday() {
        let cal = statCalendar()
        let ref = statDate(2026, 8, 14, 12, 0, calendar: cal)
        let today = statDate(2026, 8, 14, 10, 0, calendar: cal)
        let yesterday = statDate(2026, 8, 13, 10, 0, calendar: cal)
        let sessions = [
            statSession(startedAt: today, intervals: [statFocus(60 * 60, endedAt: today)]),
            statSession(startedAt: yesterday, intervals: [statFocus(30 * 60, endedAt: yesterday)])
        ]
        let c = StatisticsAggregator.comparison(sessions: sessions, period: .today, reference: ref, calendar: cal)
        #expect(c.current == 60 * 60)
        #expect(c.previous == 30 * 60)
        #expect(c.direction == .up)
    }

    @Test("previousRange for this week is exactly last week")
    func previousRangeThisWeek() {
        let cal = statCalendar()
        let ref = statDate(2026, 8, 14, 12, 0, calendar: cal)
        let previous = StatisticsPeriod.thisWeek.previousRange(reference: ref, calendar: cal)
        let lastWeek = StatisticsPeriod.lastWeek.range(reference: ref, calendar: cal)
        #expect(previous == lastWeek)
    }

    @Test("previousRange for a custom span shifts back by its own day count")
    func previousRangeCustom() {
        let cal = statCalendar()
        let start = statDate(2026, 8, 10, calendar: cal)
        let end = statDate(2026, 8, 12, calendar: cal) // 3-day span
        let period = StatisticsPeriod.custom(start: start, end: end)
        let current = period.range(calendar: cal)
        let previous = period.previousRange(calendar: cal)
        #expect(previous.end == current.start)
        #expect(previous.dayCount(calendar: cal) == 3)
    }
}
