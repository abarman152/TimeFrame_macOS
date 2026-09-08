//
//  NavigationIntents.swift
//  time_frame (Milestone 12)
//
//  The two "open the app somewhere" intents — Open Time Frame and Show Statistics. Both reuse
//  the EXISTING navigation seam: they open a `timeframe://…` deep link (the same scheme the
//  widgets use), which the one `WindowGroup` handles in `ContentView.onOpenURL` by selecting
//  the matching existing `AppSection` (ADR-059). No second window and no parallel navigation
//  system are created.
//

import Foundation
import AppIntents

/// Bring Time Frame forward on the Timer screen.
struct OpenTimeFrameIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Time Frame"
    static let description = IntentDescription("Open Time Frame and show the timer.", categoryName: "Navigation")

    // Opening is delegated to the returned OpenURLIntent, which foregrounds the app via the
    // registered `timeframe://` scheme — so the intent itself needn't launch the UI directly.
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(WidgetDeepLink.timer.url))
    }
}

/// Bring Time Frame forward on the Statistics screen.
struct ShowTimeFrameStatisticsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Time Frame Statistics"
    static let description = IntentDescription("Open Time Frame and show your statistics.", categoryName: "Navigation")

    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(WidgetDeepLink.statistics.url))
    }
}
