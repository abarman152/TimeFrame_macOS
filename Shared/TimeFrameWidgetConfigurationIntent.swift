//
//  TimeFrameWidgetConfigurationIntent.swift
//  Time Frame — configurable widget (Milestone 14)
//
//  The `WidgetConfigurationIntent` that backs the widget's `AppIntentConfiguration`. It is
//  the ONLY owner of a widget's configuration: WidgetKit presents its parameters in the
//  standard widget-editing UI and persists the user's choices against the installed widget.
//  The app stores nothing (no UserDefaults, no SwiftData) for widget configuration (ADR-065).
//
//  It is a *configuration* intent, not a command: it has no side effects and never touches
//  the timer, the coordinator, the store, or any model. Its only job is to translate the
//  three user choices into the pure `TimeFrameWidgetConfiguration` the provider/view read (ADR-064).
//
//  User-facing strings are deliberately plain ("Current Timer", "Today's Focus", …): the
//  configuration UI must read without any technical vocabulary, and each option carries a
//  `DisplayRepresentation` (title + subtitle) so VoiceOver announces a meaningful label.
//
//  Compiled into BOTH the app and the widget extension so the widget can reference it in its
//  `AppIntentConfiguration` and the app-side test target can exercise it deterministically.
//

import Foundation
import AppIntents

// MARK: - Content (what the widget shows)

/// The widget-content choice, surfaced in the widget editor. Raw values are stable
/// identifiers WidgetKit persists — do not rename them.
public enum WidgetContentOption: String, AppEnum, CaseIterable {
    case currentTimer
    case todaysFocus
    case statistics

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Widget Content")
    }

    public static var caseDisplayRepresentations: [WidgetContentOption: DisplayRepresentation] {
        [
            .currentTimer: DisplayRepresentation(
                title: "Current Timer",
                subtitle: "Your active session and countdown"
            ),
            .todaysFocus: DisplayRepresentation(
                title: "Today's Focus",
                subtitle: "Focus time and sessions completed today"
            ),
            .statistics: DisplayRepresentation(
                title: "Statistics",
                subtitle: "Today's focus at a glance, with a trend"
            )
        ]
    }

    /// The pure display mode this choice maps to.
    public var displayMode: WidgetDisplayMode {
        switch self {
        case .currentTimer: return .timer
        case .todaysFocus: return .today
        case .statistics: return .statistics
        }
    }
}

// MARK: - Destination (where a tap goes)

/// The tap-destination choice, surfaced in the widget editor. Raw values are stable
/// identifiers WidgetKit persists — do not rename them.
public enum WidgetDestinationOption: String, AppEnum, CaseIterable {
    case timer
    case today
    case statistics
    case history

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Open When Tapped")
    }

    public static var caseDisplayRepresentations: [WidgetDestinationOption: DisplayRepresentation] {
        [
            .timer: DisplayRepresentation(title: "Timer", subtitle: "Open the timer"),
            .today: DisplayRepresentation(title: "Today", subtitle: "Open today's summary"),
            .statistics: DisplayRepresentation(title: "Statistics", subtitle: "Open your statistics"),
            .history: DisplayRepresentation(title: "History", subtitle: "Open your session history")
        ]
    }

    /// The pure destination this choice maps to.
    public var destination: WidgetDestination {
        switch self {
        case .timer: return .timer
        case .today: return .today
        case .statistics: return .statistics
        case .history: return .history
        }
    }
}

// MARK: - Countdown (show / hide)

/// The countdown-visibility choice, surfaced in the widget editor as two plain options
/// rather than a bare switch, so the label reads clearly in the editor and to VoiceOver.
public enum WidgetCountdownOption: String, AppEnum, CaseIterable {
    case show
    case hide

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Countdown")
    }

    public static var caseDisplayRepresentations: [WidgetCountdownOption: DisplayRepresentation] {
        [
            .show: DisplayRepresentation(title: "Show Countdown", subtitle: "Display the remaining time"),
            .hide: DisplayRepresentation(title: "Hide Countdown", subtitle: "Keep the widget quiet")
        ]
    }

    /// Whether the countdown should be shown.
    public var showsCountdown: Bool { self == .show }
}

// MARK: - Configuration intent

/// Backs the configurable Time Frame widget. Presented by WidgetKit in the widget editor;
/// it holds the user's three choices and maps them into the pure `TimeFrameWidgetConfiguration`.
public struct TimeFrameWidgetConfigurationIntent: WidgetConfigurationIntent {

    public static var title: LocalizedStringResource { "Time Frame Widget" }

    public static var description: IntentDescription {
        IntentDescription("Choose what the widget shows, where a tap takes you, and whether the countdown is visible.")
    }

    /// What the widget displays.
    @Parameter(title: "Display", default: .currentTimer)
    public var content: WidgetContentOption

    /// Where a tap on the widget goes.
    @Parameter(title: "Open When Tapped", default: .timer)
    public var destination: WidgetDestinationOption

    /// Whether the live countdown is shown (only affects the Current Timer display).
    @Parameter(title: "Countdown", default: .show)
    public var countdown: WidgetCountdownOption

    public init() {}

    /// A convenience for tests/previews to construct a fully-specified intent.
    public init(
        content: WidgetContentOption,
        destination: WidgetDestinationOption,
        countdown: WidgetCountdownOption
    ) {
        self.content = content
        self.destination = destination
        self.countdown = countdown
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$content)") {
            \.$destination
            \.$countdown
        }
    }

    /// The pure, WidgetKit-independent configuration this intent represents.
    public var configuration: TimeFrameWidgetConfiguration {
        TimeFrameWidgetConfiguration(
            displayMode: content.displayMode,
            destination: destination.destination,
            showsCountdown: countdown.showsCountdown
        )
    }
}
