//
//  StatisticsCharts.swift
//  time_frame
//
//  Native Swift Charts for the Statistics dashboard (Milestone 10). Every chart is a
//  read-only projection of an already-computed `StatisticsSnapshot` — no chart fetches
//  data, does timing, or holds a clock. Accessibility is first-class: each mark carries
//  a text label and value (so meaning never rides on colour alone), and each chart
//  handles empty and single-point data with an explicit placeholder rather than an
//  empty plot. Colours come from `TFPalette`, so light/dark and accent adapt for free.
//

import SwiftUI
import Charts

// MARK: - Focus time by day

/// A bar chart of completed focus time per day across the selected range.
struct FocusByDayChart: View {
    let daily: [DailyStatistics]
    /// A compact weekday axis (week ranges) vs. a day-number axis (longer ranges).
    var useWeekdayAxis: Bool

    private var hasFocus: Bool { daily.contains { $0.focusDuration > 0 } }

    var body: some View {
        StatisticsChartCard(title: "Focus by Day", systemImage: "chart.bar.fill") {
            if hasFocus {
                Chart(daily) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Focus (minutes)", day.focusDuration / 60)
                    )
                    .foregroundStyle(TFPalette.focus.gradient)
                    .cornerRadius(TFRadius.small / 2)
                    .accessibilityLabel(Self.axisDayLabel(day.date))
                    .accessibilityValue(TimeFormatting.accessibleClock(day.focusDuration))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(useWeekdayAxis
                                     ? date.formatted(.dateTime.weekday(.narrow))
                                     : date.formatted(.dateTime.day()))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text("\(Int(minutes))m")
                            }
                        }
                    }
                }
                .frame(height: 200)
                .accessibilityLabel("Focus time by day, in minutes")
            } else {
                ChartEmptyPlaceholder(message: "No focus recorded on any day in this period.")
            }
        }
    }

    static func axisDayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month().day())
    }
}

// MARK: - Sessions completed by day

/// A bar chart of completed sessions per day across the selected range.
struct SessionsByDayChart: View {
    let daily: [DailyStatistics]
    var useWeekdayAxis: Bool

    private var hasSessions: Bool { daily.contains { $0.completedSessions > 0 } }

    var body: some View {
        StatisticsChartCard(title: "Sessions Completed", systemImage: "checkmark.circle.fill") {
            if hasSessions {
                Chart(daily) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Sessions", day.completedSessions)
                    )
                    .foregroundStyle(TFPalette.completed.gradient)
                    .cornerRadius(TFRadius.small / 2)
                    .accessibilityLabel(FocusByDayChart.axisDayLabel(day.date))
                    .accessibilityValue(statisticsCount(day.completedSessions, "completed session"))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(useWeekdayAxis
                                     ? date.formatted(.dateTime.weekday(.narrow))
                                     : date.formatted(.dateTime.day()))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let count = value.as(Int.self) { Text("\(count)") }
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Completed sessions by day")
            } else {
                ChartEmptyPlaceholder(message: "No sessions completed in this period.")
            }
        }
    }
}

// MARK: - Configuration breakdown

/// A horizontal bar chart of focus time grouped by configuration name.
struct ConfigurationBreakdownChart: View {
    let configurations: [ConfigurationStatistics]

    var body: some View {
        StatisticsChartCard(title: "Focus by Configuration", systemImage: "slider.horizontal.3") {
            if configurations.isEmpty {
                ChartEmptyPlaceholder(message: "No completed focus intervals to attribute yet.")
            } else {
                Chart(configurations) { config in
                    BarMark(
                        x: .value("Focus (minutes)", config.focusDuration / 60),
                        y: .value("Configuration", config.configurationName)
                    )
                    .foregroundStyle(TFPalette.focus.gradient)
                    .cornerRadius(TFRadius.small / 2)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(TimeFormatting.compactDuration(config.focusDuration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(config.configurationName)
                    .accessibilityValue(TimeFormatting.accessibleClock(config.focusDuration))
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) { Text("\(Int(minutes))m") }
                        }
                    }
                }
                .frame(height: CGFloat(configurations.count) * 44 + 24)
                .accessibilityLabel("Focus time by configuration, in minutes")
            }
        }
    }
}

// MARK: - Shared chart chrome

/// A quiet titled container shared by every statistics chart, so charts sit on the
/// same calm surface as the rest of the dashboard.
struct StatisticsChartCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.m) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TFSpacing.l)
        .tfQuietSurface(cornerRadius: TFRadius.large)
    }
}

/// The explicit placeholder shown in place of an empty plot, so a chart never renders
/// as a blank, meaningless axis.
private struct ChartEmptyPlaceholder: View {
    let message: String

    var body: some View {
        HStack(spacing: TFSpacing.s) {
            Image(systemName: "chart.bar")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        .multilineTextAlignment(.center)
    }
}
