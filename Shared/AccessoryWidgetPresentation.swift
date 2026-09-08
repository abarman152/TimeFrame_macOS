//
//  AccessoryWidgetPresentation.swift
//  Time Frame — shared widget projection (Milestone 21)
//
//  The pure presentation mapper for the iOS Lock Screen accessory widget families
//  (`.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline`). Given the frozen
//  `WidgetProjection` the app wrote, the user's `TimeFrameWidgetConfiguration`, and `now`, it
//  answers "what should this accessory family show?" — the SF Symbol, the short/long text, whether
//  a live countdown should be drawn (and between which frozen anchors), and a single spoken
//  accessibility sentence. Nothing here computes elapsed time or advances a clock: the live
//  "ticking" is left to WidgetKit's `Text(timerInterval:)` / `ProgressView(timerInterval:)` in the
//  view, driven by the projection's frozen `intervalStartedAt`/`intervalPlannedEndAt` anchors, and
//  the paused reading is the projection's frozen remaining (ADR-055/087).
//
//  It is deliberately WidgetKit-free (so it compiles into BOTH the app and the widget and is
//  unit-testable without a WidgetKit host) and Foundation-only. `AccessoryWidgetFamily` is the
//  mapper's own neutral family vocabulary — the widget view maps WidgetKit's `WidgetFamily` onto it
//  — so this file never imports WidgetKit and can never drift into a second timer (ADR-087).
//
//  Compiled into BOTH the app target and the widget extension (explicit membership; `Shared/` is
//  not a synchronized group). Foundation-only: `Sendable`, `Equatable`.
//

import Foundation

// MARK: - Neutral family vocabulary

/// The accessory families this mapper serves. Neutral (WidgetKit-free) so the mapper stays pure and
/// testable; the widget view translates `WidgetFamily` → this at the boundary.
public enum AccessoryWidgetFamily: String, Sendable, CaseIterable, Hashable {
    case circular
    case rectangular
    case inline
}

/// How (if at all) a live countdown should be rendered by the view — expressed without any WidgetKit
/// type. The view realises `.live` as `Text(timerInterval:)` / `ProgressView(timerInterval:)` between
/// the frozen anchors, and `.frozen` as a static clock string; neither introduces a clock here.
public enum AccessoryCountdown: Sendable, Equatable {
    /// No countdown — a settled or countdown-hidden state renders a word/glyph instead.
    case none
    /// A live, WidgetKit-driven countdown between two frozen instants (`start < end`).
    case live(start: Date, end: Date)
    /// A frozen remaining reading (paused) — never advances; the view prints it statically.
    case frozen(seconds: TimeInterval)
}

// MARK: - Per-family presentation models

/// The circular (Lock Screen / StandBy) presentation: a single glyph plus, when running, a live
/// countdown ring; when paused, the frozen remaining; otherwise just the glyph. Deliberately sparse
/// — no task names are ever crammed into the circular family.
public struct AccessoryCircularPresentation: Sendable, Equatable {
    public let symbolName: String
    public let countdown: AccessoryCountdown
    /// A very short glanceable word (e.g. "Focus", "Break", "45m") used only where the family has
    /// room beneath the glyph; `nil` when the countdown ring already carries the reading.
    public let shortText: String?
    public let accessibilityLabel: String

    public init(symbolName: String, countdown: AccessoryCountdown, shortText: String?, accessibilityLabel: String) {
        self.symbolName = symbolName
        self.countdown = countdown
        self.shortText = shortText
        self.accessibilityLabel = accessibilityLabel
    }
}

/// The rectangular (Lock Screen) presentation: a titled header line, an optional trailing badge
/// (e.g. "2/4"), a prominent countdown or status line, and an optional detail line (task/summary).
public struct AccessoryRectangularPresentation: Sendable, Equatable {
    public let symbolName: String
    public let title: String
    /// A short trailing badge on the header line (e.g. interval progress "2/4"), or `nil`.
    public let trailing: String?
    public let countdown: AccessoryCountdown
    /// The status word shown when there is no countdown to draw (idle/completed/countdown-hidden).
    public let statusLine: String?
    /// A secondary detail line (task name, "n sessions today"), or `nil`.
    public let detail: String?
    public let accessibilityLabel: String

    public init(
        symbolName: String,
        title: String,
        trailing: String?,
        countdown: AccessoryCountdown,
        statusLine: String?,
        detail: String?,
        accessibilityLabel: String
    ) {
        self.symbolName = symbolName
        self.title = title
        self.trailing = trailing
        self.countdown = countdown
        self.statusLine = statusLine
        self.detail = detail
        self.accessibilityLabel = accessibilityLabel
    }
}

/// The inline (Lock Screen, above the clock) presentation: one image + one concise text run. When a
/// live countdown applies, the view concatenates `Text(prefix)` + `Text(timerInterval:)`.
public struct AccessoryInlinePresentation: Sendable, Equatable {
    public let symbolName: String
    /// The leading text (e.g. "Focus · ") shown before a live/frozen countdown; the full text when
    /// `countdown == .none`.
    public let prefix: String
    public let countdown: AccessoryCountdown
    public let accessibilityLabel: String

    public init(symbolName: String, prefix: String, countdown: AccessoryCountdown, accessibilityLabel: String) {
        self.symbolName = symbolName
        self.prefix = prefix
        self.countdown = countdown
        self.accessibilityLabel = accessibilityLabel
    }
}

// MARK: - Mapper

/// Derives the accessory presentation for a projection + configuration. Pure and deterministic given
/// `now` (used only for the *snapshot* spoken-remaining in accessibility labels — never to advance a
/// countdown). Timer mode renders the session; Today/Statistics modes render a compact daily glance,
/// degrading information density rather than inventing a second projection (ADR-088).
public enum AccessoryWidgetPresentation {

    // MARK: Circular

    public static func circular(
        for projection: WidgetProjection,
        configuration: TimeFrameWidgetConfiguration = .default,
        now: Date = Date()
    ) -> AccessoryCircularPresentation {
        switch configuration.displayMode {
        case .today, .statistics:
            return circularGlance(for: projection, statistics: configuration.displayMode == .statistics)
        case .timer:
            break
        }

        switch projection.state {
        case .running:
            let phase = PhaseVocabulary(projection.phase)
            if configuration.showsCountdown, let live = liveCountdown(projection) {
                return AccessoryCircularPresentation(
                    symbolName: phase.symbol,
                    countdown: live,
                    shortText: nil,
                    accessibilityLabel: runningAccessibility(projection, phase: phase, showsCountdown: true, now: now)
                )
            }
            // Countdown hidden (or no anchor): glyph + a calm status word.
            return AccessoryCircularPresentation(
                symbolName: phase.symbol,
                countdown: .none,
                shortText: phase.shortWord,
                accessibilityLabel: runningAccessibility(projection, phase: phase, showsCountdown: false, now: now)
            )

        case .paused:
            let phase = PhaseVocabulary(projection.phase)
            let remaining = max(0, projection.pausedRemainingSeconds ?? 0)
            return AccessoryCircularPresentation(
                symbolName: "pause.circle.fill",
                countdown: configuration.showsCountdown ? .frozen(seconds: remaining) : .none,
                shortText: configuration.showsCountdown ? nil : "Paused",
                accessibilityLabel: pausedAccessibility(projection, phase: phase, showsCountdown: configuration.showsCountdown)
            )

        case .idle:
            return AccessoryCircularPresentation(
                symbolName: "timer", countdown: .none, shortText: "Focus",
                accessibilityLabel: "Time Frame, ready to focus")
        case .completed:
            return AccessoryCircularPresentation(
                symbolName: "checkmark.circle.fill", countdown: .none, shortText: "Done",
                accessibilityLabel: "Focus complete")
        case .interrupted:
            return AccessoryCircularPresentation(
                symbolName: "exclamationmark.triangle.fill", countdown: .none, shortText: "Ended",
                accessibilityLabel: "Session ended")
        case .unavailable:
            return AccessoryCircularPresentation(
                symbolName: "timer", countdown: .none, shortText: nil,
                accessibilityLabel: "Time Frame")
        }
    }

    private static func circularGlance(for projection: WidgetProjection, statistics: Bool) -> AccessoryCircularPresentation {
        let symbol = statistics ? "chart.bar.xaxis" : "sun.max.fill"
        if let focus = projection.focusSecondsToday {
            return AccessoryCircularPresentation(
                symbolName: symbol,
                countdown: .none,
                shortText: DurationText.compact(focus),
                accessibilityLabel: "\(statistics ? "Statistics" : "Today"), \(DurationText.spoken(focus)) focused today")
        }
        return AccessoryCircularPresentation(
            symbolName: symbol, countdown: .none, shortText: "0m",
            accessibilityLabel: "\(statistics ? "Statistics" : "Today"), no focus yet today")
    }

    // MARK: Rectangular

    public static func rectangular(
        for projection: WidgetProjection,
        configuration: TimeFrameWidgetConfiguration = .default,
        now: Date = Date()
    ) -> AccessoryRectangularPresentation {
        switch configuration.displayMode {
        case .today, .statistics:
            return rectangularGlance(for: projection, statistics: configuration.displayMode == .statistics)
        case .timer:
            break
        }

        switch projection.state {
        case .running:
            let phase = PhaseVocabulary(projection.phase)
            let live = configuration.showsCountdown ? liveCountdown(projection) : nil
            return AccessoryRectangularPresentation(
                symbolName: phase.symbol,
                title: phase.title,
                trailing: intervalBadge(projection),
                countdown: live ?? .none,
                statusLine: live == nil ? phase.statusWord : nil,
                detail: detailLine(projection),
                accessibilityLabel: runningAccessibility(projection, phase: phase, showsCountdown: configuration.showsCountdown, now: now))

        case .paused:
            let phase = PhaseVocabulary(projection.phase)
            let remaining = max(0, projection.pausedRemainingSeconds ?? 0)
            return AccessoryRectangularPresentation(
                symbolName: "pause.circle.fill",
                title: "Paused",
                trailing: intervalBadge(projection),
                countdown: configuration.showsCountdown ? .frozen(seconds: remaining) : .none,
                statusLine: configuration.showsCountdown ? nil : "Paused",
                detail: detailLine(projection),
                accessibilityLabel: pausedAccessibility(projection, phase: phase, showsCountdown: configuration.showsCountdown))

        case .idle:
            return AccessoryRectangularPresentation(
                symbolName: "timer", title: "Time Frame", trailing: nil, countdown: .none,
                statusLine: "Ready to focus", detail: nil,
                accessibilityLabel: "Time Frame, ready to focus")
        case .completed:
            return AccessoryRectangularPresentation(
                symbolName: "checkmark.circle.fill", title: "Focus complete", trailing: nil, countdown: .none,
                statusLine: detailLine(projection) == nil ? "All intervals done" : nil,
                detail: detailLine(projection),
                accessibilityLabel: completedAccessibility(projection))
        case .interrupted:
            return AccessoryRectangularPresentation(
                symbolName: "exclamationmark.triangle.fill", title: "Session ended", trailing: nil, countdown: .none,
                statusLine: "Couldn't resume", detail: nil,
                accessibilityLabel: "Session ended, couldn't resume your last session")
        case .unavailable:
            return AccessoryRectangularPresentation(
                symbolName: "timer", title: "Time Frame", trailing: nil, countdown: .none,
                statusLine: "Open the app to start", detail: nil,
                accessibilityLabel: "Time Frame, open the app to get started")
        }
    }

    private static func rectangularGlance(for projection: WidgetProjection, statistics: Bool) -> AccessoryRectangularPresentation {
        let title = statistics ? "Statistics" : "Today"
        let symbol = statistics ? "chart.bar.xaxis" : "sun.max.fill"
        guard let focus = projection.focusSecondsToday else {
            return AccessoryRectangularPresentation(
                symbolName: symbol, title: title, trailing: nil, countdown: .none,
                statusLine: "No focus yet today", detail: nil,
                accessibilityLabel: "\(title), no focus yet today")
        }
        var detailParts: [String] = []
        if let sessions = projection.completedSessionsToday {
            detailParts.append("\(sessions) \(sessions == 1 ? "session" : "sessions")")
        }
        if statistics, let trend = projection.focusTrendToday {
            detailParts.append(TrendVocabulary(trend).word)
        } else if let intervals = projection.completedFocusIntervalsToday {
            detailParts.append("\(intervals) \(intervals == 1 ? "interval" : "intervals")")
        }
        return AccessoryRectangularPresentation(
            symbolName: symbol,
            title: title,
            trailing: statistics ? projection.focusTrendToday.map { TrendVocabulary($0).arrow } : nil,
            countdown: .none,
            statusLine: DurationText.compact(focus) + " focused",
            detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
            accessibilityLabel: glanceAccessibility(projection, title: title, statistics: statistics))
    }

    // MARK: Inline

    public static func inline(
        for projection: WidgetProjection,
        configuration: TimeFrameWidgetConfiguration = .default,
        now: Date = Date()
    ) -> AccessoryInlinePresentation {
        switch configuration.displayMode {
        case .today, .statistics:
            let title = configuration.displayMode == .statistics ? "Statistics" : "Today"
            let symbol = configuration.displayMode == .statistics ? "chart.bar.xaxis" : "sun.max.fill"
            if let focus = projection.focusSecondsToday {
                return AccessoryInlinePresentation(
                    symbolName: symbol, prefix: "\(title) · \(DurationText.compact(focus))", countdown: .none,
                    accessibilityLabel: "\(title), \(DurationText.spoken(focus)) focused today")
            }
            return AccessoryInlinePresentation(
                symbolName: symbol, prefix: "No focus yet", countdown: .none,
                accessibilityLabel: "\(title), no focus yet today")
        case .timer:
            break
        }

        switch projection.state {
        case .running:
            let phase = PhaseVocabulary(projection.phase)
            if configuration.showsCountdown, let live = liveCountdown(projection) {
                return AccessoryInlinePresentation(
                    symbolName: phase.symbol, prefix: "\(phase.title) · ", countdown: live,
                    accessibilityLabel: runningAccessibility(projection, phase: phase, showsCountdown: true, now: now))
            }
            return AccessoryInlinePresentation(
                symbolName: phase.symbol, prefix: phase.statusWord, countdown: .none,
                accessibilityLabel: runningAccessibility(projection, phase: phase, showsCountdown: false, now: now))
        case .paused:
            let phase = PhaseVocabulary(projection.phase)
            let remaining = max(0, projection.pausedRemainingSeconds ?? 0)
            if configuration.showsCountdown {
                return AccessoryInlinePresentation(
                    symbolName: "pause.circle.fill", prefix: "Paused · ", countdown: .frozen(seconds: remaining),
                    accessibilityLabel: pausedAccessibility(projection, phase: phase, showsCountdown: true))
            }
            return AccessoryInlinePresentation(
                symbolName: "pause.circle.fill", prefix: "Paused", countdown: .none,
                accessibilityLabel: pausedAccessibility(projection, phase: phase, showsCountdown: false))
        case .idle:
            return AccessoryInlinePresentation(
                symbolName: "timer", prefix: "Ready to focus", countdown: .none,
                accessibilityLabel: "Time Frame, ready to focus")
        case .completed:
            return AccessoryInlinePresentation(
                symbolName: "checkmark.circle.fill", prefix: "Focus complete", countdown: .none,
                accessibilityLabel: "Focus complete")
        case .interrupted:
            return AccessoryInlinePresentation(
                symbolName: "exclamationmark.triangle.fill", prefix: "Session ended", countdown: .none,
                accessibilityLabel: "Session ended")
        case .unavailable:
            return AccessoryInlinePresentation(
                symbolName: "timer", prefix: "Time Frame", countdown: .none,
                accessibilityLabel: "Time Frame")
        }
    }

    // MARK: - Shared derivations

    /// The live countdown anchors for a running projection, or `nil` when the anchor is missing or
    /// already past (the caller then shows a calm word instead — never a negative duration).
    private static func liveCountdown(_ projection: WidgetProjection) -> AccessoryCountdown? {
        guard let end = projection.intervalPlannedEndAt else { return nil }
        let start = projection.intervalStartedAt ?? projection.generatedAt
        guard end > start else { return nil }
        return .live(start: start, end: end)
    }

    /// The "n/N" interval badge, or `nil` when the plan indices are unknown.
    private static func intervalBadge(_ projection: WidgetProjection) -> String? {
        guard let current = projection.currentIntervalIndex, let total = projection.totalIntervals else { return nil }
        return "\(current)/\(total)"
    }

    /// The rectangular detail line: the task title if present, else a compact today summary.
    private static func detailLine(_ projection: WidgetProjection) -> String? {
        if let title = projection.title, !title.isEmpty { return title }
        if let sessions = projection.completedSessionsToday {
            return "\(sessions) \(sessions == 1 ? "session" : "sessions") today"
        }
        return nil
    }

    // MARK: Accessibility sentences (single spoken element per family)

    private static func runningAccessibility(_ projection: WidgetProjection, phase: PhaseVocabulary, showsCountdown: Bool, now: Date) -> String {
        var parts = [phase.title]
        if let title = projection.title, !title.isEmpty { parts.append(title) }
        if showsCountdown, let end = projection.intervalPlannedEndAt {
            let remaining = max(0, end.timeIntervalSince(now))
            parts.append("\(DurationText.spoken(remaining)) remaining")
        }
        if let current = projection.currentIntervalIndex, let total = projection.totalIntervals {
            parts.append("focus \(current) of \(total)")
        }
        return parts.joined(separator: ", ")
    }

    private static func pausedAccessibility(_ projection: WidgetProjection, phase: PhaseVocabulary, showsCountdown: Bool) -> String {
        var parts = ["Paused"]
        if let title = projection.title, !title.isEmpty { parts.append(title) }
        if showsCountdown, let remaining = projection.pausedRemainingSeconds {
            parts.append("\(DurationText.spoken(max(0, remaining))) remaining")
        }
        return parts.joined(separator: ", ")
    }

    private static func completedAccessibility(_ projection: WidgetProjection) -> String {
        var parts = ["Focus complete"]
        if let title = projection.title, !title.isEmpty { parts.append(title) }
        if let sessions = projection.completedSessionsToday {
            parts.append("\(sessions) \(sessions == 1 ? "session" : "sessions") completed today")
        }
        return parts.joined(separator: ", ")
    }

    private static func glanceAccessibility(_ projection: WidgetProjection, title: String, statistics: Bool) -> String {
        var parts = [title]
        if let focus = projection.focusSecondsToday {
            parts.append("\(DurationText.spoken(focus)) focused today")
        } else {
            return "\(title), no focus yet today"
        }
        if let sessions = projection.completedSessionsToday {
            parts.append("\(sessions) \(sessions == 1 ? "session" : "sessions") completed")
        }
        if statistics, let trend = projection.focusTrendToday {
            parts.append("trend \(TrendVocabulary(trend).word) the previous day")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Vocabulary

/// Phase → title / short word / status word / SF Symbol. Kept private to the mapper so all accessory
/// phrasing lives in one place; the tint is intentionally omitted (accessory families render in the
/// system's vibrant/monochrome mode, so state is carried by the word and glyph, never colour).
private struct PhaseVocabulary {
    let title: String
    let shortWord: String
    let statusWord: String
    let symbol: String

    init(_ phase: WidgetPhase) {
        switch phase {
        case .focus:
            title = "Focus"; shortWord = "Focus"; statusWord = "Focusing"; symbol = "brain.head.profile"
        case .shortBreak:
            title = "Short Break"; shortWord = "Break"; statusWord = "On a break"; symbol = "cup.and.saucer.fill"
        case .longBreak:
            title = "Long Break"; shortWord = "Break"; statusWord = "On a break"; symbol = "figure.walk"
        case .none:
            title = "Session"; shortWord = "Timer"; statusWord = "In session"; symbol = "timer"
        }
    }
}

/// Trend → spoken word + arrow glyph text (accessory has no room for symbols in every slot).
private struct TrendVocabulary {
    let word: String
    let arrow: String

    init(_ trend: WidgetFocusTrend) {
        switch trend {
        case .up: word = "up"; arrow = "↑"
        case .down: word = "down"; arrow = "↓"
        case .steady: word = "steady"; arrow = "→"
        }
    }
}

/// Pure duration formatting for accessory text (compact) and VoiceOver (spoken). Mirrors the home
/// widget's formatters so the two surfaces speak identically; kept local so the mapper stays
/// WidgetKit-free and self-contained.
enum DurationText {
    /// A compact focus-duration string: `45m`, `1h 20m`, `2h`, `<1m`, `0m`.
    static func compact(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return total > 0 ? "<1m" : "0m"
    }

    /// A clock string for the frozen paused reading: `MM:SS`, or `H:MM:SS` past an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
    }

    /// A VoiceOver-friendly spoken duration. Below an hour, seconds are spoken alongside minutes
    /// ("24 minutes 31 seconds") so the Lock Screen reading is precise; at hour granularity seconds
    /// are dropped ("1 hour 20 minutes"). Zero reads as "0 seconds".
    static func spoken(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        if hours == 0, secs > 0 { parts.append("\(secs) \(secs == 1 ? "second" : "seconds")") }
        if parts.isEmpty { parts.append("0 seconds") }
        return parts.joined(separator: " ")
    }
}
