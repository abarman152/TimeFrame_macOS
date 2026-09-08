//
//  TimeFrameWidgetConfiguration.swift
//  Time Frame — shared widget configuration (Milestone 14)
//
//  The pure, user-chosen presentation configuration for a Time Frame widget. It answers
//  three questions and nothing else: *what* the widget shows, *where* a tap goes, and
//  whether the live countdown is visible. It is a value copy — WidgetKit owns the real
//  configuration (via the `AppIntentConfiguration` intent); this is the neutral model the
//  widget's provider/view read (ADR-064).
//
//  It changes PRESENTATION only. It carries no timer state, no clock, no session identity,
//  and can never mutate the engine, the coordinator, or the store. It is deliberately
//  independent of both SwiftData and WidgetKit, and imports only Foundation, so it compiles
//  into BOTH the app target and the widget extension and is trivially testable.
//
//  Every enum decodes **defensively**: an unknown raw value degrades to the safe default
//  rather than throwing, so a forward-incompatible payload never crashes the widget and the
//  timer is never involved (ADR-066).
//

import Foundation

/// What a configured widget displays. Each case is a read-only projection of the SAME
/// authoritative state — never a second data source.
public enum WidgetDisplayMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// The current (or most recent) timer/session — the M11 behaviour.
    case timer
    /// Today's focus summary (focus time, completed focus intervals, completed sessions).
    case today
    /// A compact statistics glance (today's focus + a simple trend).
    case statistics

    /// The default content shown by a freshly-added or misconfigured widget.
    public static let `default`: WidgetDisplayMode = .timer

    /// Decodes defensively: an unknown string resolves to `.default` instead of throwing.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetDisplayMode(rawValue: raw) ?? .default
    }
}

/// Where a tap on the widget takes the user. Each maps 1:1 to an existing app screen via
/// the neutral `timeframe://` deep-link vocabulary — no new navigation mechanism (ADR-065).
public enum WidgetDestination: String, Codable, Sendable, CaseIterable, Hashable {
    case timer
    case today
    case statistics
    case history

    /// The default destination for a freshly-added or misconfigured widget.
    public static let `default`: WidgetDestination = .timer

    /// The existing deep link this destination opens. The app maps it onto its existing
    /// `AppSection` (reusing the one window), exactly like the M11 widget tap.
    public var deepLink: WidgetDeepLink {
        switch self {
        case .timer: return .timer
        case .today: return .today
        case .statistics: return .statistics
        case .history: return .history
        }
    }

    /// Decodes defensively: an unknown string resolves to `.default` instead of throwing.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetDestination(rawValue: raw) ?? .default
    }
}

/// The complete, deterministic widget configuration: content, tap destination, and whether
/// the countdown is shown. `Codable`/`Hashable`/`Sendable` and pure — it is never persisted
/// by the app (WidgetKit stores it against the widget); the `Codable` conformance exists so
/// the value round-trips cleanly and is easy to test.
public struct TimeFrameWidgetConfiguration: Codable, Sendable, Hashable {
    /// What the widget shows.
    public var displayMode: WidgetDisplayMode
    /// Where a tap goes.
    public var destination: WidgetDestination
    /// Whether the live countdown is visible (only meaningful for `.timer`).
    public var showsCountdown: Bool

    public init(
        displayMode: WidgetDisplayMode = .default,
        destination: WidgetDestination = .default,
        showsCountdown: Bool = true
    ) {
        self.displayMode = displayMode
        self.destination = destination
        self.showsCountdown = showsCountdown
    }

    /// The safe fallback used whenever no trustworthy configuration is available (a missing
    /// or malformed intent): show the current timer, open the Timer screen, countdown on.
    public static let `default` = TimeFrameWidgetConfiguration(
        displayMode: .default,
        destination: .default,
        showsCountdown: true
    )

    // MARK: Defensive decoding

    private enum CodingKeys: String, CodingKey {
        case displayMode, destination, showsCountdown
    }

    /// Decodes defensively: any missing or malformed field falls back to its default, so a
    /// partial or forward-incompatible payload yields a usable configuration, never a throw.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.displayMode = try container.decodeIfPresent(WidgetDisplayMode.self, forKey: .displayMode) ?? .default
        self.destination = try container.decodeIfPresent(WidgetDestination.self, forKey: .destination) ?? .default
        self.showsCountdown = try container.decodeIfPresent(Bool.self, forKey: .showsCountdown) ?? true
    }
}
