//
//  TimeFrameWidgetEntry.swift
//  TimeFrameWidgets (Milestone 11; configuration added in Milestone 14)
//
//  The WidgetKit timeline entry. It carries a timestamp, the read-only `WidgetProjection`
//  snapshot, and the user's `TimeFrameWidgetConfiguration` — the widget owns no timer state
//  (ADR-055) and the configuration only chooses *how* the snapshot is presented (ADR-064).
//

import WidgetKit
import Foundation

/// One point on the widget's timeline: a render instant, the projection to render, and the
/// presentation configuration chosen by the user in the widget editor.
struct TimeFrameWidgetEntry: TimelineEntry {
    /// The instant WidgetKit should present this entry.
    let date: Date
    /// The read-only projection to render at that instant.
    let projection: WidgetProjection
    /// The user's presentation configuration (content, tap destination, countdown).
    let configuration: TimeFrameWidgetConfiguration

    init(
        date: Date,
        projection: WidgetProjection,
        configuration: TimeFrameWidgetConfiguration = .default
    ) {
        self.date = date
        self.projection = projection
        self.configuration = configuration
    }
}
