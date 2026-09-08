//
//  StatisticsView.swift
//  time_frame
//
//  The Statistics & Productivity Analytics dashboard (Milestone 10). It reads the
//  same persisted session history History browses (via `@Query`), projects it into
//  pure inputs, and asks the deterministic `StatisticsAggregator` for a snapshot of
//  the selected period. The view is a **read-only projection**: it never starts,
//  stops, or mutates a session, a configuration, a plan, or the timer. All figures
//  come from one in-memory aggregation per body evaluation (no per-chart, per-day, or
//  per-second fetch), and there is no `Timer`/`TimelineView`/clock anywhere here.
//

import SwiftUI
import SwiftData


/// Pluralises a count with its noun for statistics captions.
///
/// These captions are built as Swift `String`s and handed to `Text(_: String)` and
/// `accessibilityValue(_:)`, which use the non-localized initializers and therefore do
/// **not** apply automatic grammar agreement. Using `^[…](inflect: true)` markup here
/// showed the raw markup to the user verbatim (found on screen during the M27
/// documentation pass), so the plural is formed explicitly instead.
nonisolated func statisticsCount(_ count: Int, _ singular: String) -> String {
    "\(count) \(singular)\(count == 1 ? "" : "s")"
}

struct StatisticsView: View {
    /// Navigates to the Timer area (used by the new-user empty state).
    var openTimer: () -> Void

    @Query(sort: \FocusSession.startedAt, order: .reverse)
    private var sessions: [FocusSession]

    @State private var choice: StatisticsPeriodChoice = .today
    @State private var customStart: Date = Calendar.current
        .date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var customEnd: Date = .now

    private var period: StatisticsPeriod {
        choice.period(customStart: customStart, customEnd: customEnd)
    }

    var body: some View {
        // One aggregation per body evaluation, from a single in-memory projection of
        // the queried history. Body re-evaluates only when the store or the selected
        // period changes — there is no timer driving repaints here.
        let calendar = Calendar.current
        let range = period.range(calendar: calendar)
        let previousRange = period.previousRange(calendar: calendar)
        // Map only the sessions that can contribute to the shown period or its comparison
        // period. `SessionStatInput` faults in a session's intervals, so mapping all of
        // history made every redraw — including the one each timer transition triggers via
        // `@Query` — cost O(lifetime history) (M26, ADR-100). Excluded sessions could not
        // have contributed, so both snapshots are unchanged.
        let inputs = sessions
            .filter {
                range.mayContainActivity(startedAt: $0.startedAt, endedAt: $0.endedAt)
                    || previousRange.mayContainActivity(startedAt: $0.startedAt, endedAt: $0.endedAt)
            }
            .map { SessionStatInput($0) }
        let snapshot = StatisticsAggregator.aggregate(sessions: inputs, range: range, calendar: calendar)
        let previous = StatisticsAggregator.aggregate(sessions: inputs, range: previousRange, calendar: calendar)
        let comparison = StatisticsComparison(current: snapshot.focusDuration, previous: previous.focusDuration)
        // "Has the user ever recorded anything?" is a lifetime question, so it is answered
        // from the queried rows directly rather than from the period-bounded inputs.
        let hasHistory = sessions.contains { $0.startedAt != nil }

        return ScrollView {
            VStack(alignment: .leading, spacing: TFSpacing.xl) {
                // The same page header every other screen opens with (Milestone 29), so the
                // dashboard reads as part of the app rather than a separate report.
                TFPageHeader(title: "Statistics",
                             subtitle: "How your focus time is trending.")

                StatisticsPeriodPicker(choice: $choice, customStart: $customStart, customEnd: $customEnd)

                if !hasHistory {
                    newUserEmptyState
                } else {
                    Text(rangeText(range))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Showing \(rangeText(range))")

                    if snapshot.isEmpty {
                        periodEmptyNote
                    } else {
                        dashboard(snapshot: snapshot, comparison: comparison)
                    }
                }
            }
            .padding(TFSpacing.xxl)
            .frame(maxWidth: TFSpacing.wideColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Statistics")
    }

    // MARK: - Dashboard

    @ViewBuilder
    private func dashboard(snapshot: StatisticsSnapshot, comparison: StatisticsComparison) -> some View {
        let useWeekdayAxis = snapshot.daily.count <= 8
        let multiDay = snapshot.daily.count > 1

        primaryMetrics(snapshot)

        trendCard(comparison)

        if multiDay, let best = snapshot.mostProductiveDay {
            mostProductiveCard(best)
        }

        if multiDay {
            FocusByDayChart(daily: snapshot.daily, useWeekdayAxis: useWeekdayAxis)
            SessionsByDayChart(daily: snapshot.daily, useWeekdayAxis: useWeekdayAxis)
        }

        if !snapshot.configurations.isEmpty {
            ConfigurationBreakdownChart(configurations: snapshot.configurations)
        }

        secondaryMetrics(snapshot)
    }

    private func primaryMetrics(_ s: StatisticsSnapshot) -> some View {
        LazyVGrid(columns: metricColumns, spacing: TFSpacing.m) {
            metricCard(
                title: "Focus Time", systemImage: "brain.head.profile",
                value: TimeFormatting.compactDuration(s.focusDuration),
                caption: statisticsCount(s.completedFocusIntervals, "focus interval"))
            metricCard(
                title: "Sessions", systemImage: "checkmark.circle",
                value: "\(s.completedSessions)",
                caption: "completed of \(s.startedSessions) started")
            metricCard(
                title: "Completion Rate", systemImage: "percent",
                value: s.completionRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                caption: s.completionRate == nil ? "No sessions started" : nil)
            metricCard(
                title: "Average Focus", systemImage: "timer",
                value: s.averageFocusInterval.map(TimeFormatting.preciseDuration) ?? "—",
                caption: "per completed interval")
        }
    }

    private func secondaryMetrics(_ s: StatisticsSnapshot) -> some View {
        LazyVGrid(columns: metricColumns, spacing: TFSpacing.m) {
            metricCard(
                title: "Break Time", systemImage: "cup.and.saucer",
                value: TimeFormatting.compactDuration(s.breakDuration), caption: "completed breaks")
            metricCard(
                title: "Longest Session", systemImage: "flame",
                value: TimeFormatting.preciseDuration(s.longestFocusSession), caption: "most focus in one session")
            metricCard(
                title: "Stopped", systemImage: "stop.circle",
                value: "\(s.stoppedSessions)", caption: "sessions stopped early")
            if s.interruptedSessions > 0 {
                metricCard(
                    title: "Interrupted", systemImage: "exclamationmark.triangle",
                    value: "\(s.interruptedSessions)", caption: "could not resume")
            }
        }
    }

    private func trendCard(_ comparison: StatisticsComparison) -> some View {
        let diff = comparison.absoluteDifference
        let diffText = "\(signPrefix(diff))\(TimeFormatting.compactDuration(abs(diff)))"
        let pctText: String = comparison.percentageChange
            .map { "\(signPrefix($0))\(abs($0).formatted(.percent.precision(.fractionLength(1))))" }
            ?? "New activity"
        let (icon, tint) = directionStyle(comparison.direction)

        return VStack(alignment: .leading, spacing: TFSpacing.m) {
            Label("Focus Trend", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
            HStack(spacing: TFSpacing.xxl) {
                trendColumn("This \(periodNoun)", TimeFormatting.compactDuration(comparison.current))
                trendColumn("Previous", TimeFormatting.compactDuration(comparison.previous))
            }
            Label("\(diffText) · \(pctText)", systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TFSpacing.l)
        .tfQuietSurface(cornerRadius: TFRadius.large)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Focus trend. This \(periodNoun) \(TimeFormatting.accessibleClock(comparison.current)), "
            + "previous \(TimeFormatting.accessibleClock(comparison.previous)). Change \(diffText), \(pctText).")
    }

    private func trendColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func mostProductiveCard(_ day: DailyStatistics) -> some View {
        HStack(spacing: TFSpacing.m) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(TFPalette.completed)
            VStack(alignment: .leading, spacing: TFSpacing.xs) {
                Text("Most Productive Day")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(day.date.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.title3.weight(.semibold))
                Text(TimeFormatting.compactDuration(day.focusDuration)
                     + " · " + statisticsCount(day.completedFocusIntervals, "focus interval"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TFSpacing.l)
        .tfQuietSurface(cornerRadius: TFRadius.large)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Most productive day: "
            + "\(day.date.formatted(.dateTime.weekday(.wide).month().day())), "
            + TimeFormatting.accessibleClock(day.focusDuration))
    }

    // MARK: - Empty states

    private var newUserEmptyState: some View {
        EmptyStateView(
            title: "No Focus Sessions Yet",
            systemImage: "chart.bar.xaxis",
            message: "Complete your first focus session to start seeing your productivity trends.",
            actionTitle: "Start Timer",
            action: openTimer
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var periodEmptyNote: some View {
        VStack(alignment: .leading, spacing: TFSpacing.s) {
            Label("No Focus in This Period", systemImage: "moon.zzz")
                .font(.headline)
            Text("There are no completed focus sessions in the selected range. Try a different period.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TFSpacing.l)
        .tfQuietSurface(cornerRadius: TFRadius.large)
    }

    // MARK: - Helpers

    private let metricColumns = [GridItem(.adaptive(minimum: 150), spacing: TFSpacing.m)]

    private func metricCard(title: String, systemImage: String, value: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: TFSpacing.xs) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(TFSpacing.l)
        .tfQuietSurface(cornerRadius: TFRadius.large)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)" + (caption.map { ", \($0)" } ?? ""))
    }

    /// The noun used in the trend card, e.g. "day"/"week"/"month"/"range".
    private var periodNoun: String {
        switch choice {
        case .today, .yesterday: "day"
        case .thisWeek, .lastWeek: "week"
        case .thisMonth, .lastMonth: "month"
        case .custom: "range"
        }
    }

    private func signPrefix<V: Comparable & AdditiveArithmetic>(_ value: V) -> String {
        if value > .zero { return "+" }
        if value < .zero { return "−" }
        return "±"
    }

    private func directionStyle(_ direction: StatisticsComparison.Direction) -> (icon: String, tint: Color) {
        switch direction {
        case .up: ("arrow.up.forward", TFPalette.running)
        case .down: ("arrow.down.forward", .secondary)
        case .flat: ("equal", .secondary)
        }
    }

    /// Human text for the resolved range: a single weekday+date, or a start–end span.
    private func rangeText(_ range: StatisticsDateRange, calendar: Calendar = .current) -> String {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.start
        if calendar.isDate(range.start, inSameDayAs: lastDay) {
            return range.start.formatted(.dateTime.weekday(.wide).month().day())
        }
        let sameYear = calendar.component(.year, from: range.start) == calendar.component(.year, from: lastDay)
        let startText = range.start.formatted(.dateTime.month().day())
        let endText = sameYear
            ? lastDay.formatted(.dateTime.month().day())
            : lastDay.formatted(.dateTime.year().month().day())
        return "\(startText) – \(endText)"
    }
}
