//
//  WidgetTimelinePolicy.swift
//  Time Frame — shared widget projection (Milestone 11)
//
//  The pure decision of *when* the widget's timeline should show new entries and when it
//  should ask WidgetKit to reload. It contains no WidgetKit types (so it is trivially
//  testable and shared) — the widget's provider translates a `WidgetTimelinePlan` into
//  WidgetKit's `Timeline`/`TimelineReloadPolicy`.
//
//  The policy never invents a countdown: the live "ticking" is done by SwiftUI's
//  date-relative `Text(_:style:.timer)` between the anchor timestamps in the projection,
//  not by scheduling one entry per second (ADR-055). Entries mark only *meaningful*
//  boundaries; reloads are scheduled around the interval's planned end (running) or held
//  conservatively (idle / paused / completed / interrupted / unavailable).
//
//  Compiled into BOTH the app target and the widget extension. Foundation-only.
//

import Foundation

/// When WidgetKit should next reload the widget's timeline.
public enum WidgetRefreshPolicy: Sendable, Equatable {
    /// Reload at (or shortly after) this instant — used to re-read the store once the
    /// running interval has reached its planned end.
    case after(Date)
    /// Do not schedule a reload; the app will push a fresh timeline (via `WidgetCenter`)
    /// the moment authoritative state changes. Used while paused, where nothing advances.
    case never
}

/// The pure timeline plan: the entry instants to render, and the reload policy.
public struct WidgetTimelinePlan: Sendable, Equatable {
    /// The instants at which the widget presents an entry, ascending. Always non-empty and
    /// always starts at "now" so there is an immediate entry.
    public let entryDates: [Date]
    /// When to reload after the last entry.
    public let refresh: WidgetRefreshPolicy

    public init(entryDates: [Date], refresh: WidgetRefreshPolicy) {
        self.entryDates = entryDates
        self.refresh = refresh
    }
}

/// Derives a `WidgetTimelinePlan` from a projection. Pure and deterministic given `now`.
public enum WidgetTimelinePolicy {

    /// A conservative heartbeat for states that are not actively counting down. Long
    /// enough that idle/completed widgets are not woken needlessly, short enough that a
    /// missed push still self-heals within the hour.
    public static let conservativeRefreshInterval: TimeInterval = 60 * 60

    /// Builds the timeline plan for a projection at `now`.
    public static func plan(for projection: WidgetProjection, now: Date) -> WidgetTimelinePlan {
        switch projection.state {
        case .running:
            // Anchor an immediate entry now, and a second entry at the interval's planned
            // end so the widget flips to a "reached the end" reading exactly there. The
            // live countdown between them is rendered by `Text(style:.timer)`, not by
            // extra entries. Reload just after the planned end to re-read the store (which
            // the app rewrites at the boundary).
            if let end = projection.intervalPlannedEndAt, end > now {
                return WidgetTimelinePlan(entryDates: [now, end], refresh: .after(end))
            }
            // No usable end anchor (or it is already past): show one entry and re-read
            // soon so we recover once the app writes the next interval.
            return WidgetTimelinePlan(
                entryDates: [now],
                refresh: .after(now.addingTimeInterval(conservativeRefreshInterval))
            )

        case .paused:
            // Frozen: exactly one entry and NO scheduled tick — the widget must never
            // pretend a paused interval is advancing. The app pushes a reload on resume.
            return WidgetTimelinePlan(entryDates: [now], refresh: .never)

        case .idle, .completed, .interrupted, .unavailable:
            // Settled states: a single entry and a conservative heartbeat. The app pushes
            // an immediate reload when a new session starts, so this only backstops.
            return WidgetTimelinePlan(
                entryDates: [now],
                refresh: .after(now.addingTimeInterval(conservativeRefreshInterval))
            )
        }
    }
}
