//
//  TimeFrameWidgetsBundle.swift
//  TimeFrameWidgets (Milestone 11; configurable in Milestone 14)
//
//  The widget extension's entry point. A single, focused widget backed by an
//  `AppIntentConfiguration` (Milestone 14): the user chooses what it shows, where a tap goes,
//  and whether the countdown is visible, all through the standard macOS widget-editing UI.
//  It renders a read-only projection the app writes — never a second timer (ADR-055/064).
//
//  The widget `kind` is UNCHANGED from M11 ("TimeFrameTimerWidget") so existing installed
//  widgets migrate in place; only the configuration mechanism changed (Static → AppIntent).
//

import WidgetKit
import SwiftUI

/// The configurable Time Frame widget: current session, today's focus, or a statistics
/// glance — the user's choice — plus a chosen tap destination and countdown visibility.
struct TimeFrameTimerWidget: Widget {
    /// UNCHANGED from Milestone 11 so installed widgets keep their identity (ADR-067).
    let kind = "TimeFrameTimerWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: TimeFrameWidgetConfigurationIntent.self,
            provider: TimeFrameWidgetProvider()
        ) { entry in
            TimeFrameWidgetView(entry: entry)
        }
        .configurationDisplayName("Time Frame")
        .description("Your timer, today's focus, or a statistics glance — your choice.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TimeFrameWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TimeFrameTimerWidget()
    }
}

// MARK: - Previews (deterministic; fixed sample data, no Date.now / store / engine)

#Preview("Timer — running", as: .systemMedium) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.focusRunning,
                         configuration: WidgetPreviewData.timerConfig)
}

#Preview("Timer — running (small)", as: .systemSmall) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.focusRunning,
                         configuration: WidgetPreviewData.timerConfig)
}

#Preview("Timer — countdown hidden", as: .systemMedium) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.focusRunning,
                         configuration: WidgetPreviewData.timerNoCountdownConfig)
}

#Preview("Today", as: .systemMedium) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.focusRunning,
                         configuration: WidgetPreviewData.todayConfig)
}

#Preview("Today (small)", as: .systemSmall) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.idle,
                         configuration: WidgetPreviewData.todayConfig)
}

#Preview("Statistics", as: .systemMedium) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.idle,
                         configuration: WidgetPreviewData.statisticsConfig)
}

#Preview("Statistics (small)", as: .systemSmall) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.idle,
                         configuration: WidgetPreviewData.statisticsConfig)
}

#Preview("Paused", as: .systemMedium) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.paused,
                         configuration: WidgetPreviewData.timerConfig)
}

#Preview("Completed", as: .systemMedium) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.completed,
                         configuration: WidgetPreviewData.timerConfig)
}

#Preview("Interrupted", as: .systemMedium) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.interrupted,
                         configuration: WidgetPreviewData.timerConfig)
}

#Preview("Unavailable", as: .systemMedium) {
    TimeFrameTimerWidget()
} timeline: {
    TimeFrameWidgetEntry(date: WidgetPreviewData.base,
                         projection: WidgetPreviewData.unavailable,
                         configuration: WidgetPreviewData.timerConfig)
}
