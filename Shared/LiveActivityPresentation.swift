//
//  LiveActivityPresentation.swift
//  Time Frame — shared Live Activity presentation (Milestone 16)
//
//  The pure, Foundation-only mapping from a Live Activity's identity + content to the display
//  primitives the widget renders: a phase title, an SF Symbol name, an optional progress line,
//  whether a live countdown should show, and an accessibility label. Keeping this here (compiled
//  into both the widget extension and the app test target) means the Live Activity's *presentation
//  logic* is unit-testable with no ActivityKit or SwiftUI runtime, and the widget view stays a
//  thin renderer of these values (ADR-072).
//
//  It computes no time and owns no clock: the running countdown is rendered by SwiftUI from the
//  content's frozen `phaseStartedAt`/`phaseTargetEndAt`; this type only decides *whether* to show
//  it. Foundation-only — no ActivityKit, no WidgetKit, no SwiftUI, no domain.
//

import Foundation

/// A read-only, value-typed description of how to present one Live Activity content state.
public struct LiveActivityPresentation: Sendable, Equatable {

    /// The phase headline, e.g. "Focus", "Short Break", "Session Complete".
    public let phaseTitle: String
    /// The SF Symbol name that represents the phase/state (a plain string; the view builds the Image).
    public let symbolName: String
    /// The task label to show, or `nil`/empty when hidden or unset.
    public let taskName: String?
    /// The configuration/plan name to show, or `nil`/empty when hidden or unset.
    public let configurationName: String?
    /// A short progress line ("Session 2 of 4"), or `nil` when there is nothing meaningful.
    public let progressText: String?
    /// Whether a live `Text(timerInterval:)` countdown should be shown (running, with anchors).
    public let showsCountdown: Bool
    /// Whether the session is paused (the view shows the frozen remaining instead of a countdown).
    public let isPaused: Bool
    /// A composed VoiceOver label for the whole activity.
    public let accessibilityLabel: String

    public init(identity: LiveActivityIdentity, content: TimeFrameLiveActivityContent) {
        let title = Self.phaseTitle(for: content)
        self.phaseTitle = title
        self.symbolName = Self.symbolName(for: content)
        self.taskName = identity.taskName.isEmpty ? nil : identity.taskName
        self.configurationName = identity.configurationName.isEmpty ? nil : identity.configurationName
        self.progressText = Self.progressText(for: content)
        self.showsCountdown = content.runState == .running
            && content.phaseStartedAt != nil
            && content.phaseTargetEndAt != nil
        self.isPaused = content.isPaused

        var parts: [String] = ["Time Frame", title]
        if let task = self.taskName { parts.append(task) }
        if let progress = self.progressText { parts.append(progress) }
        if content.isPaused { parts.append("Paused") }
        self.accessibilityLabel = parts.joined(separator: ", ")
    }

    /// The phase/state headline.
    public static func phaseTitle(for content: TimeFrameLiveActivityContent) -> String {
        switch content.runState {
        case .completed: return "Session Complete"
        case .interrupted: return "Session Ended"
        case .running, .paused:
            switch content.phase {
            case .focus: return "Focus"
            case .shortBreak: return "Short Break"
            case .longBreak: return "Long Break"
            case .none: return "Time Frame"
            }
        }
    }

    /// The SF Symbol for the phase/state.
    public static func symbolName(for content: TimeFrameLiveActivityContent) -> String {
        switch content.runState {
        case .completed: return "checkmark.circle.fill"
        case .interrupted: return "stop.circle"
        case .running, .paused:
            switch content.phase {
            case .focus: return "brain.head.profile"
            case .shortBreak, .longBreak: return "cup.and.saucer.fill"
            case .none: return "timer"
            }
        }
    }

    /// A "Session i of n" line, shown only for a focus interval with a known count.
    public static func progressText(for content: TimeFrameLiveActivityContent) -> String? {
        guard content.runState.isActive,
              content.phase == .focus,
              content.totalFocusSessions > 0,
              content.sessionIndex > 0
        else { return nil }
        return "Session \(content.sessionIndex) of \(content.totalFocusSessions)"
    }
}
