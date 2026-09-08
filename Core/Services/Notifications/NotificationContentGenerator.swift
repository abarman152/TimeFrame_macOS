//
//  NotificationContentGenerator.swift
//  time_frame
//
//  Pure conversion of a semantic transition (`Announcement`) into notification text.
//  It knows the task, phase, duration, configuration, and session progress — and
//  nothing about how to deliver to macOS (that is the adapter's job). Deterministic:
//  same input → identical content, so every string is unit-testable without touching
//  UserNotifications (§47/§54).
//

import Foundation

/// The meaning of a single notification: which transition it announces and the data
/// needed to phrase it. Pure and `Sendable`.
nonisolated enum NotificationAnnouncement: Equatable, Sendable {
    /// A focus interval is about to begin.
    case focus(task: String, duration: TimeInterval, configurationName: String)
    /// A short break is about to begin.
    case shortBreak(task: String, duration: TimeInterval)
    /// A long break is about to begin, after `completedFocusCount` focus sessions.
    case longBreak(task: String, completedFocusCount: Int)
    /// The whole session has completed with `focusCount` focus sessions.
    case sessionCompleted(task: String, focusCount: Int)

    /// The category this announcement maps to.
    var category: NotificationCategory {
        switch self {
        case .focus: return .focusStarted
        case .shortBreak: return .shortBreakStarted
        case .longBreak: return .longBreakStarted
        case .sessionCompleted: return .sessionCompleted
        }
    }
}

/// Turns a `NotificationAnnouncement` into concise `NotificationContent`.
///
/// Content is intentionally short (§13): a title, the task as subtitle, and a one-line
/// body. Never dumps internal timer state. Falls back to the app name when there is no
/// task, so titles are never empty (§14).
nonisolated enum NotificationContentGenerator {

    /// The app name shown when a session has no task.
    static let appName = "Time Frame"

    static func content(for announcement: NotificationAnnouncement) -> NotificationContent {
        switch announcement {
        case let .focus(task, duration, configurationName):
            return NotificationContent(
                title: "Time to focus",
                subtitle: subtitle(task),
                body: focusBody(duration: duration, configurationName: configurationName)
            )
        case let .shortBreak(task, duration):
            return NotificationContent(
                title: "Short break",
                subtitle: optionalSubtitle(task),
                body: "Focus session complete. Take \(TimeFormatting.minutesLabel(duration)) to recharge."
            )
        case let .longBreak(task, completedFocusCount):
            return NotificationContent(
                title: "Long break",
                subtitle: optionalSubtitle(task),
                body: "You've completed \(sessionCountPhrase(completedFocusCount)). Take a longer break."
            )
        case let .sessionCompleted(task, focusCount):
            return NotificationContent(
                title: "Session complete",
                subtitle: subtitle(task),
                body: "\(sessionCountPhrase(focusCount)) completed."
            )
        }
    }

    // MARK: Helpers

    /// A subtitle that is never empty (falls back to the app name — §14).
    private static func subtitle(_ task: String) -> String {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    /// A subtitle only when there is a real task (nil otherwise), used where the app
    /// name would add nothing (break notifications).
    private static func optionalSubtitle(_ task: String) -> String? {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The focus body: the duration, optionally with the configuration name (§15),
    /// kept concise.
    private static func focusBody(duration: TimeInterval, configurationName: String) -> String {
        let minutes = TimeFormatting.minutesLabel(duration)
        let config = configurationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return config.isEmpty ? minutes : "\(minutes) · \(config)"
    }

    /// "1 focus session" / "4 focus sessions".
    private static func sessionCountPhrase(_ count: Int) -> String {
        "\(count) focus session\(count == 1 ? "" : "s")"
    }
}
