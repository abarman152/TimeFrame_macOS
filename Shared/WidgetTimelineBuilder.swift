//
//  WidgetTimelineBuilder.swift
//  Time Frame — shared widget projection (Milestone 14)
//
//  The pure bridge between "what the app wrote" and "what WidgetKit should render". Given a
//  frozen `WidgetProjection`, the user's `TimeFrameWidgetConfiguration`, and `now`, it produces the
//  ordered entry descriptors (each an instant + the projection + the configuration) and the
//  reload policy. The widget's provider does nothing but map these descriptors onto
//  WidgetKit's `Timeline` — all timing logic lives here where it is trivially testable.
//
//  Crucially, the configuration NEVER affects timing: the entry instants and reload policy
//  come solely from `WidgetTimelinePolicy` (the projection's state), so switching a widget
//  between Timer / Today / Statistics is a presentation change only and can never introduce
//  a second clock or a per-second reload (ADR-064). This keeps the "one timer, many
//  surfaces" invariant intact and provable (see `ConfiguredWidgetTimelineTests`).
//
//  Compiled into BOTH the app target and the widget extension. Foundation-only.
//

import Foundation

/// One point on the widget's timeline: the render instant, the read-only projection to
/// render, and the user's presentation configuration. A value type — it owns no timer.
public struct WidgetEntryDescriptor: Sendable, Equatable {
    /// The instant WidgetKit should present this entry.
    public let date: Date
    /// The read-only projection to render at that instant.
    public let projection: WidgetProjection
    /// The user's presentation configuration (content, destination, countdown).
    public let configuration: TimeFrameWidgetConfiguration

    public init(date: Date, projection: WidgetProjection, configuration: TimeFrameWidgetConfiguration) {
        self.date = date
        self.projection = projection
        self.configuration = configuration
    }
}

/// The pure timeline the widget provider renders: the ordered entries plus the reload policy.
public struct WidgetTimeline: Sendable, Equatable {
    public let entries: [WidgetEntryDescriptor]
    public let refresh: WidgetRefreshPolicy

    public init(entries: [WidgetEntryDescriptor], refresh: WidgetRefreshPolicy) {
        self.entries = entries
        self.refresh = refresh
    }
}

/// Builds a `WidgetTimeline` from a projection + configuration at `now`. Pure and
/// deterministic; the configuration is carried onto every entry but never alters the
/// entry instants or the reload policy (those come only from `WidgetTimelinePolicy`).
public enum WidgetTimelineBuilder {

    /// Assembles the timeline. The `configuration` decides *what* each entry renders and
    /// *where* a tap goes; `WidgetTimelinePolicy` decides *when* entries appear and when to
    /// reload — the two concerns never cross.
    public static func timeline(
        projection: WidgetProjection,
        configuration: TimeFrameWidgetConfiguration,
        now: Date
    ) -> WidgetTimeline {
        let plan = WidgetTimelinePolicy.plan(for: projection, now: now)
        let entries = plan.entryDates.map {
            WidgetEntryDescriptor(date: $0, projection: projection, configuration: configuration)
        }
        return WidgetTimeline(entries: entries, refresh: plan.refresh)
    }
}
