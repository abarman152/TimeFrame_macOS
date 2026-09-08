//
//  TimeFrameWidgetView.swift
//  TimeFrameWidgets (Milestone 11; configurable in Milestone 14; interactive in Milestone 15)
//
//  The widget's SwiftUI surface. It renders purely from the read-only `WidgetProjection` in
//  the entry and from WidgetKit-supported date-relative text — it owns no timer and
//  decrements nothing (ADR-055). The live countdown is `Text(timerInterval:)`, which
//  WidgetKit animates itself; the paused reading is the projection's *frozen* remaining.
//
//  Milestone 15 adds interactive controls in Timer mode: per-state `Button(intent:)` clusters
//  (running focus → Pause/Skip[/Stop]; break → Skip/Stop; paused → Resume/Restart/Stop;
//  idle/completed/interrupted → Start). Every button is a shared App Intent that the system runs
//  in the APP process, routing through `AppIntentSessionActions` to the one `SessionCoordinator`
//  (ADR-069). Which controls appear is derived solely from the projection's state/phase — the
//  widget still owns no timer state and mutates nothing. Today/Statistics modes stay read-only.
//
//  The user's `TimeFrameWidgetConfiguration` selects the presentation only (ADR-064):
//   • `displayMode` picks Timer / Today / Statistics content;
//   • `showsCountdown` hides the live countdown in Timer mode (a quiet variant);
//   • `destination` picks where a tap goes (an existing `timeframe://` deep link).
//  The configuration never changes what the projection *is* — only which slice is shown.
//
//  Accessibility: every state combines into a meaningful VoiceOver label/value; status is
//  never conveyed by colour alone (each phase/trend pairs a tint with a label and an SF
//  Symbol), decorative symbols are hidden from assistive technologies, and text uses system
//  styles so Dynamic Type and the widget's adaptive layout are respected.
//

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Root

/// Switches the widget on the chosen display mode and attaches the chosen deep link.
struct TimeFrameWidgetView: View {
    var entry: TimeFrameWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(entry.configuration.destination.deepLink.url)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.configuration.displayMode {
        case .timer:
            TimerModeView(
                projection: entry.projection,
                showsCountdown: entry.configuration.showsCountdown,
                family: family
            )
        case .today:
            TodayModeView(projection: entry.projection, family: family)
        case .statistics:
            StatisticsModeView(projection: entry.projection, family: family)
        }
    }
}

// MARK: - Timer mode (the Milestone 11 content, now countdown-aware)

private struct TimerModeView: View {
    let projection: WidgetProjection
    let showsCountdown: Bool
    let family: WidgetFamily

    var body: some View {
        switch projection.state {
        case .running, .paused:
            ActiveSessionView(projection: projection, showsCountdown: showsCountdown, family: family)
        case .idle:
            IdleView(projection: projection, family: family)
        case .completed:
            CompletedView(projection: projection, family: family)
        case .interrupted:
            InterruptedView(family: family)
        case .unavailable:
            UnavailableView()
        }
    }
}

// MARK: - Active (running / paused)

private struct ActiveSessionView: View {
    let projection: WidgetProjection
    let showsCountdown: Bool
    let family: WidgetFamily

    private var phase: PhasePresentation { PhasePresentation(projection.phase) }
    private var isPaused: Bool { projection.state == .paused }
    private var isSmall: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: isSmall ? 4 : 6) {
            // Informational block — combined into a single VoiceOver element so it reads as one
            // sentence. The controls below are kept OUT of this element so each button stays
            // individually focusable and actionable.
            VStack(alignment: .leading, spacing: isSmall ? 2 : 4) {
                header

                if !isSmall, let title = projection.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                countdown
                    .font(.system(isSmall ? .title2 : .title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if !isSmall {
                    IntervalProgressView(
                        current: projection.currentIntervalIndex,
                        total: projection.totalIntervals,
                        completed: projection.completedFocusCount,
                        showsDots: true
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)

            Spacer(minLength: 0)

            // Interactive controls (Milestone 15). Each routes through an App Intent →
            // AppIntentSessionActions → the one SessionCoordinator; the widget owns no state.
            SessionControlBar(state: projection.state, phase: projection.phase, family: family)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: phase.symbol)
                .foregroundStyle(phase.tint)
                .accessibilityHidden(true)
            Text(phase.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(phase.tint)
            Spacer(minLength: 0)
            if isPaused {
                Text("Paused")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if !showsCountdown {
            // Quiet variant: no live countdown, just the phase state as a calm word.
            Text(isPaused ? "Paused" : phase.statusWord)
        } else if isPaused {
            // Frozen: render the projection's remaining statically — no live ticking.
            Text(WidgetFormatting.clock(projection.pausedRemainingSeconds ?? 0))
        } else if let end = projection.intervalPlannedEndAt {
            // Live, WidgetKit-driven countdown to the frozen planned-end instant.
            Text(timerInterval: (projection.intervalStartedAt ?? projection.generatedAt)...end,
                 countsDown: true)
        } else {
            Text("—")
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        parts.append(isPaused ? "Paused" : "\(phase.label) in progress")
        if let title = projection.title, !title.isEmpty { parts.append(title) }
        if showsCountdown {
            if isPaused, let remaining = projection.pausedRemainingSeconds {
                parts.append("\(WidgetFormatting.spoken(remaining)) remaining")
            } else if let end = projection.intervalPlannedEndAt {
                parts.append("\(WidgetFormatting.spoken(max(0, end.timeIntervalSince(projection.generatedAt)))) remaining")
            }
        }
        if let current = projection.currentIntervalIndex, let total = projection.totalIntervals {
            parts.append("focus \(current) of \(total)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Idle

private struct IdleView: View {
    let projection: WidgetProjection
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Time Frame")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("Ready to focus")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                if family != .systemSmall {
                    TodaySummaryView(projection: projection)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Time Frame. Ready to focus.")

            Spacer(minLength: 0)

            // Start a session using the app's default configuration (Milestone 15).
            WidgetControlButton(
                title: "Start Timer",
                systemImage: "play.fill",
                intent: WidgetStartIntent(),
                role: .primary,
                accessibilityLabel: "Start a Time Frame session"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Completed

private struct CompletedView: View {
    let projection: WidgetProjection
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Session complete")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                if let title = projection.title, !title.isEmpty {
                    Text(title)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                } else {
                    Text("All intervals done")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                }

                if family != .systemSmall {
                    TodaySummaryView(projection: projection)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)

            Spacer(minLength: 0)

            // Begin a fresh session from the completed state (Milestone 15).
            WidgetControlButton(
                title: "Start New Session",
                systemImage: "arrow.clockwise",
                intent: WidgetStartIntent(),
                role: .primary,
                accessibilityLabel: "Start a new Time Frame session"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var accessibilityLabel: String {
        var parts = ["Session complete"]
        if let title = projection.title, !title.isEmpty { parts.append(title) }
        if let count = projection.completedSessionsToday {
            parts.append("\(count) \(count == 1 ? "session" : "sessions") completed today")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Interrupted

private struct InterruptedView: View {
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Session interrupted")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text("Couldn't resume your last session")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .minimumScaleFactor(0.6)
                    .lineLimit(family == .systemSmall ? 2 : 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Session interrupted. Couldn't resume your last session.")

            Spacer(minLength: 0)

            // Begin a fresh session after an interrupted one (Milestone 15).
            WidgetControlButton(
                title: "Start New Session",
                systemImage: "arrow.clockwise",
                intent: WidgetStartIntent(),
                role: .primary,
                accessibilityLabel: "Start a new Time Frame session"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Unavailable (stable fallback)

private struct UnavailableView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Time Frame")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("Open the app to get started")
                .font(.callout)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time Frame. Open the app to get started.")
    }
}

// MARK: - Today mode (Milestone 14)

/// The "Today's Focus" content: focus time today plus the two completed counts. Glanceable —
/// one primary metric (focus time) and one or two secondary metrics depending on family.
private struct TodayModeView: View {
    let projection: WidgetProjection
    let family: WidgetFamily

    private var hasData: Bool {
        projection.focusSecondsToday != nil
            || projection.completedSessionsToday != nil
            || projection.completedFocusIntervalsToday != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if hasData {
                Text(WidgetFormatting.focusDuration(projection.focusSecondsToday ?? 0))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("focused")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                MetricRow(
                    sessions: projection.completedSessionsToday,
                    intervals: family == .systemSmall ? nil : projection.completedFocusIntervalsToday
                )
            } else {
                Spacer(minLength: 0)
                Text("No focus yet today")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard hasData else { return "Today. No focus yet today." }
        var parts = ["Today"]
        parts.append("\(WidgetFormatting.spoken(projection.focusSecondsToday ?? 0)) focused")
        if let sessions = projection.completedSessionsToday {
            parts.append("\(sessions) \(sessions == 1 ? "session" : "sessions") completed")
        }
        if let intervals = projection.completedFocusIntervalsToday {
            parts.append("\(intervals) focus \(intervals == 1 ? "interval" : "intervals")")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Statistics mode (Milestone 14)

/// A compact statistics glance: today's focus (primary), sessions completed (secondary), and
/// a simple trend versus the prior day. Deliberately glanceable — not the full dashboard.
private struct StatisticsModeView: View {
    let projection: WidgetProjection
    let family: WidgetFamily

    private var hasData: Bool {
        projection.focusSecondsToday != nil || projection.completedSessionsToday != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text("Statistics")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let trend = projection.focusTrendToday {
                    TrendBadge(trend: trend)
                }
            }

            if hasData {
                Text(WidgetFormatting.focusDuration(projection.focusSecondsToday ?? 0))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("focused today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if family != .systemSmall {
                    MetricRow(
                        sessions: projection.completedSessionsToday,
                        intervals: projection.completedFocusIntervalsToday
                    )
                }
            } else {
                Spacer(minLength: 0)
                Text("No statistics yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard hasData else { return "Statistics. No statistics yet." }
        var parts = ["Statistics"]
        parts.append("\(WidgetFormatting.spoken(projection.focusSecondsToday ?? 0)) focused today")
        if let sessions = projection.completedSessionsToday {
            parts.append("\(sessions) \(sessions == 1 ? "session" : "sessions") completed")
        }
        if let trend = projection.focusTrendToday {
            parts.append("trend \(TrendPresentation(trend).label) the previous day")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Shared sub-views

/// "Focus n of N" plus optional progress dots. Never a clock — pure static projection.
private struct IntervalProgressView: View {
    let current: Int?
    let total: Int?
    let completed: Int
    let showsDots: Bool

    var body: some View {
        if let current, let total {
            HStack(spacing: 6) {
                Text("Focus \(current) of \(total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if showsDots {
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        ForEach(0..<max(total, 0), id: \.self) { index in
                            Circle()
                                .fill(index < completed ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
    }
}

/// The compact today summary footer (focus time + completed sessions), when available.
private struct TodaySummaryView: View {
    let projection: WidgetProjection

    var body: some View {
        if projection.focusSecondsToday != nil || projection.completedSessionsToday != nil {
            HStack(spacing: 10) {
                if let focus = projection.focusSecondsToday {
                    Label(WidgetFormatting.focusDuration(focus), systemImage: "hourglass")
                        .labelStyle(.titleAndIcon)
                }
                if let sessions = projection.completedSessionsToday {
                    Label("\(sessions)", systemImage: "checkmark.seal")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        var parts = ["Today"]
        if let focus = projection.focusSecondsToday {
            parts.append("\(WidgetFormatting.spoken(focus)) focused")
        }
        if let sessions = projection.completedSessionsToday {
            parts.append("\(sessions) \(sessions == 1 ? "session" : "sessions") completed")
        }
        return parts.joined(separator: ", ")
    }
}

/// A row of secondary metrics (completed sessions and optional completed focus intervals),
/// each an icon + number label so no metric is conveyed by position alone.
private struct MetricRow: View {
    let sessions: Int?
    let intervals: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let sessions {
                Label("\(sessions) \(sessions == 1 ? "session" : "sessions")", systemImage: "checkmark.seal")
                    .labelStyle(.titleAndIcon)
            }
            if let intervals {
                Label("\(intervals) \(intervals == 1 ? "interval" : "intervals")", systemImage: "hourglass")
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

/// A small trend badge (arrow + word) versus the prior day. The colour is always paired with
/// an SF Symbol and a word so the trend is never communicated by colour alone.
private struct TrendBadge: View {
    let trend: WidgetFocusTrend

    var body: some View {
        let presentation = TrendPresentation(trend)
        Label(presentation.label, systemImage: presentation.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(presentation.tint)
            .accessibilityHidden(true)
    }
}

// MARK: - Interactive controls (Milestone 15)

/// The per-state row of interactive buttons for Timer mode. Which controls appear is derived
/// *entirely* from the read-only projection state and phase (plus the widget family for how many
/// fit) — never from any widget-local timer or session state (ADR-069/070). Each button routes
/// through a shared App Intent to the one `SessionCoordinator`; the bar itself owns nothing.
private struct SessionControlBar: View {
    let state: WidgetSessionState
    let phase: WidgetPhase
    let family: WidgetFamily

    private var compact: Bool { family == .systemSmall }

    var body: some View {
        // The set of controls is a PURE function of the projection (state + phase) — the view
        // only maps each to its button. Only running/paused render a control row here; the
        // other states carry an inline Start button whose label varies by state.
        HStack(spacing: 6) {
            ForEach(WidgetControlSet.controls(for: state, phase: phase, compact: compact), id: \.self) { action in
                button(for: action)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func button(for action: WidgetControlAction) -> some View {
        switch action {
        case .pause:
            WidgetControlButton(title: "Pause", systemImage: "pause.fill",
                                intent: WidgetPauseIntent(), role: .primary,
                                accessibilityLabel: "Pause the Time Frame session")
        case .resume:
            WidgetControlButton(title: "Resume", systemImage: "play.fill",
                                intent: WidgetResumeIntent(), role: .primary,
                                accessibilityLabel: "Resume the Time Frame session")
        case .skip:
            WidgetControlButton(title: "Skip", systemImage: "forward.end.fill",
                                intent: WidgetSkipIntent(), role: phase.isBreak ? .primary : .secondary,
                                accessibilityLabel: phase.isBreak ? "Skip the current break" : "Skip the current interval")
        case .restart:
            WidgetControlButton(title: "Restart", systemImage: "arrow.counterclockwise",
                                intent: WidgetRestartIntent(), role: .secondary,
                                accessibilityLabel: "Restart the current interval")
        case .stop:
            WidgetControlButton(title: "Stop", systemImage: "stop.fill",
                                intent: WidgetStopIntent(), role: .destructive,
                                accessibilityLabel: "Stop the Time Frame session")
        case .start:
            // Not reached from running/paused; present for completeness of the mapping.
            WidgetControlButton(title: "Start Timer", systemImage: "play.fill",
                                intent: WidgetStartIntent(), role: .primary,
                                accessibilityLabel: "Start a Time Frame session")
        }
    }
}

/// One compact widget control button. Renders an SF Symbol *and* a short label (never
/// icon-only, so an action is never conveyed by icon or colour alone), and always carries an
/// explicit accessibility label describing the action. A uniform `.bordered` style keeps the
/// concrete view type stable; `role` only re-tints, it never changes the state math.
private struct WidgetControlButton<I: AppIntent>: View {
    enum Role { case primary, secondary, destructive }

    let title: String
    let systemImage: String
    let intent: I
    var role: Role = .secondary
    let accessibilityLabel: String

    var body: some View {
        Button(intent: intent) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .controlSize(.small)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var tint: Color {
        switch role {
        case .primary: return .accentColor
        case .secondary: return .secondary
        case .destructive: return .red
        }
    }
}

// MARK: - Presentation helpers

/// Maps a `WidgetPhase` to its label, SF Symbol, and tint. The tint is always paired with
/// the label and icon so state is never communicated by colour alone.
private struct PhasePresentation {
    let label: String
    let symbol: String
    let tint: Color
    /// A calm one-word status used by the quiet (countdown-hidden) variant.
    let statusWord: String

    init(_ phase: WidgetPhase) {
        switch phase {
        case .focus:
            label = "Focus"; symbol = "brain.head.profile"; tint = .orange; statusWord = "Focusing"
        case .shortBreak:
            label = "Short Break"; symbol = "cup.and.saucer"; tint = .teal; statusWord = "On a break"
        case .longBreak:
            label = "Long Break"; symbol = "figure.walk"; tint = .teal; statusWord = "On a break"
        case .none:
            label = "Session"; symbol = "timer"; tint = .gray; statusWord = "In session"
        }
    }
}

/// Maps a `WidgetFocusTrend` to a word, SF Symbol, and tint (paired, never colour-only).
private struct TrendPresentation {
    let label: String
    let symbol: String
    let tint: Color

    init(_ trend: WidgetFocusTrend) {
        switch trend {
        case .up:
            label = "Up"; symbol = "arrow.up.right"; tint = .green
        case .down:
            label = "Down"; symbol = "arrow.down.right"; tint = .red
        case .steady:
            label = "Steady"; symbol = "arrow.right"; tint = .secondary
        }
    }
}
