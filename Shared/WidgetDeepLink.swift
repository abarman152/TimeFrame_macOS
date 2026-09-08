//
//  WidgetDeepLink.swift
//  Time Frame — shared widget projection (Milestone 11)
//
//  The tiny, neutral vocabulary for widget taps. A widget attaches one of these URLs to a
//  view (`.widgetURL` / `Link`); tapping it brings the app forward and the app maps the URL
//  onto its *existing* sidebar section (the app-side `AppSection` mapping lives in the app
//  target, keeping this type free of any app navigation dependency).
//
//  Compiled into BOTH the app target and the widget extension. Foundation-only.
//

import Foundation

/// A destination a widget tap can request. Each maps 1:1 to an existing app screen.
public enum WidgetDeepLink: String, Sendable, CaseIterable, Hashable {
    case timer
    case today
    case statistics
    case history

    /// The custom URL scheme the app registers (`CFBundleURLTypes`).
    public static let scheme = "timeframe"

    /// The URL a widget attaches for this destination, e.g. `timeframe://timer`.
    public var url: URL {
        var components = URLComponents()
        components.scheme = WidgetDeepLink.scheme
        components.host = rawValue
        // Non-optional: the scheme + host are always valid, but fall back defensively.
        return components.url ?? URL(string: "\(WidgetDeepLink.scheme)://\(rawValue)")!
    }

    /// Parses a tapped URL back into a destination, or `nil` if it is not a recognised
    /// Time Frame widget link (unknown scheme or unknown host are both ignored safely).
    public init?(url: URL) {
        guard url.scheme == WidgetDeepLink.scheme else { return nil }
        // The destination is the host (`timeframe://today`); tolerate a path-only form
        // (`timeframe:///today`) as a fallback so a stray slash never drops the route.
        let key = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let match = WidgetDeepLink(rawValue: key) else { return nil }
        self = match
    }
}
