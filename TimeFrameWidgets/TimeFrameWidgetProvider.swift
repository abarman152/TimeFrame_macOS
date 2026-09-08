//
//  TimeFrameWidgetProvider.swift
//  TimeFrameWidgets (Milestone 11; configurable in Milestone 14)
//
//  The WidgetKit timeline provider. It is a thin, read-only adapter: it reads the last
//  projection the app wrote to the shared store, resolves the user's configuration from the
//  `TimeFrameWidgetConfigurationIntent`, and asks the pure `WidgetTimelineBuilder` for the
//  entries + reload policy. It creates NO timer, NO Combine publisher, NO async countdown
//  loop, and never touches SwiftData, `TimerEngine`, or `SessionCoordinator` (ADR-055/064).
//  A missing or corrupt projection degrades to a stable `.unavailable` entry, and a missing
//  or malformed configuration degrades to `TimeFrameWidgetConfiguration.default` — the
//  widget never crashes on bad data.
//
//  Configuration changes PRESENTATION only: the entry instants and reload policy come solely
//  from the projection's state (via `WidgetTimelineBuilder` → `WidgetTimelinePolicy`), never
//  from the configuration, so a config change can never introduce a second clock (ADR-064).
//

import WidgetKit
import Foundation

/// Supplies timeline entries for the Time Frame widgets from the shared projection store and
/// the user's widget configuration. `AppIntentTimelineProvider` — the modern, configurable
/// counterpart to M11's `TimelineProvider`.
struct TimeFrameWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = TimeFrameWidgetEntry
    typealias Intent = TimeFrameWidgetConfigurationIntent

    /// The shared store the app writes to. Read-only from here.
    private let store: WidgetProjectionStore

    init(store: WidgetProjectionStore = WidgetProjectionStore()) {
        self.store = store
    }

    /// A representative entry for the widget gallery / redacted placeholder. Uses the default
    /// configuration (the gallery has no user selection yet).
    func placeholder(in context: Context) -> TimeFrameWidgetEntry {
        TimeFrameWidgetEntry(
            date: Date(),
            projection: WidgetPreviewData.focusRunning,
            configuration: .default
        )
    }

    /// A single entry for transient snapshots (gallery preview, transitions). Reads the live
    /// projection when present; otherwise shows sample data in the gallery and the real
    /// fallback elsewhere. The passed intent supplies the user's chosen presentation.
    func snapshot(for configuration: Intent, in context: Context) async -> TimeFrameWidgetEntry {
        let projection = currentProjection(previewInGallery: context.isPreview)
        return TimeFrameWidgetEntry(
            date: Date(),
            projection: projection,
            configuration: configuration.configuration
        )
    }

    /// Builds the timeline from the last-written projection, the user's configuration, and
    /// the pure builder. Each entry renders the same snapshot at a meaningful instant; the
    /// live countdown between them is SwiftUI's `Text(timerInterval:)`, not per-second entries.
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<TimeFrameWidgetEntry> {
        let now = Date()
        let projection = currentProjection(previewInGallery: context.isPreview)
        let built = WidgetTimelineBuilder.timeline(
            projection: projection,
            configuration: configuration.configuration,
            now: now
        )
        let entries = built.entries.map {
            TimeFrameWidgetEntry(date: $0.date, projection: $0.projection, configuration: $0.configuration)
        }
        return Timeline(entries: entries, policy: reloadPolicy(for: built.refresh))
    }

    /// Reads the current projection, substituting a stable fallback when the store is
    /// unavailable or the payload is missing/corrupt. In the WidgetKit gallery (`isPreview`)
    /// a missing projection shows friendly sample data instead of the fallback.
    private func currentProjection(previewInGallery: Bool) -> WidgetProjection {
        if let projection = store.read() {
            return projection
        }
        if previewInGallery {
            return WidgetPreviewData.idle
        }
        return .unavailable(reason: "No session data available yet.")
    }

    /// Translates the pure refresh policy into WidgetKit's reload policy.
    private func reloadPolicy(for refresh: WidgetRefreshPolicy) -> TimelineReloadPolicy {
        switch refresh {
        case .after(let date): return .after(date)
        case .never: return .never
        }
    }
}
