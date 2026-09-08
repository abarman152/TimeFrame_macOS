//
//  WidgetDeepLink+AppSection.swift
//  time_frame (Milestone 11)
//
//  The app-side half of widget deep linking: it maps a neutral `WidgetDeepLink` (parsed
//  from a tapped `timeframe://…` URL) onto the app's *existing* `AppSection`, so a widget
//  tap reuses the one WindowGroup and its screens rather than any new navigation
//  architecture (§deep-links). Kept in the app target because `AppSection` is a UI-layer
//  type the widget never imports.
//

import Foundation

extension WidgetDeepLink {
    /// The existing sidebar section this deep link selects.
    var section: AppSection {
        switch self {
        case .timer: return .timer
        case .today: return .today
        case .statistics: return .statistics
        case .history: return .history
        }
    }

    /// Parses a URL and resolves it straight to a section, or `nil` for an unrecognised
    /// URL (which the app then ignores safely).
    static func section(for url: URL) -> AppSection? {
        WidgetDeepLink(url: url)?.section
    }
}
