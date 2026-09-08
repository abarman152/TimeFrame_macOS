//
//  AppIntentDialogText.swift
//  time_frame (Milestone 12)
//
//  The single place that turns a pure `AppIntentSessionState` (or a start descriptor) into
//  the short, natural-language sentences Siri/Shortcuts speak back. Kept pure and
//  Foundation-only so every phrase is unit-testable without invoking an intent, and so all
//  user-facing App Intent copy lives in one file — the single edit point when the app adopts
//  a localization catalog (today the app hardcodes English strings throughout the UI; the
//  App Intents layer follows that existing convention, centralized here).
//

import Foundation

/// Builds the spoken/on-screen sentences for the App Intents layer. Pure and deterministic.
nonisolated enum AppIntentDialogText {

    // MARK: Phase vocabulary

    /// A phase as a bare noun for mid-sentence use: "focus", "a short break", "a long break".
    static func phaseNoun(_ phase: TimerPhase) -> String {
        switch phase {
        case .focus: return "focus"
        case .shortBreak: return "a short break"
        case .longBreak: return "a long break"
        }
    }

    /// A phase capitalised for sentence starts: "Focus", "Short break", "Long break".
    static func phaseTitle(_ phase: TimerPhase) -> String {
        switch phase {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    // MARK: Status (GetCurrentTimeFrameStatusIntent)

    /// The answer to "What's my Time Frame status?", derived entirely from authoritative
    /// state. Example: "You're focusing on Research Paper. Session 2 of 4. You have 18
    /// minutes remaining."
    static func status(_ state: AppIntentSessionState) -> String {
        switch state.situation {
        case .idle:
            return "No Time Frame session is running."
        case .completed:
            return "Your Time Frame session is complete."
        case .interrupted:
            return "Your last Time Frame session was interrupted and couldn't be resumed."
        case .running, .paused:
            return activeStatus(state)
        }
    }

    private static func activeStatus(_ state: AppIntentSessionState) -> String {
        var parts: [String] = []

        let task = trimmedTask(state.taskName)
        if let phase = state.phase, phase.isFocus {
            parts.append(task.map { "You're focusing on \($0)." } ?? "You're in a focus interval.")
        } else if let phase = state.phase {
            let noun = phaseNoun(phase)
            parts.append(task.map { "You're on \(noun) from \($0)." } ?? "You're on \(noun).")
        }

        if let index = state.sessionIndex, let total = state.totalSessions {
            parts.append("Session \(index) of \(total).")
        }

        if state.situation == .paused {
            parts.append("The timer is paused with \(remainingClause(state.remaining)) left.")
        } else {
            parts.append("You have \(remainingClause(state.remaining)) remaining.")
        }

        return parts.joined(separator: " ")
    }

    // MARK: Start confirmations

    /// "Started Research Paper using Deep Work. Session 1 of 4."
    static func started(task: String, configurationName: String, sessionCount: Int) -> String {
        let trimmed = trimmedTask(task)
        let lead = trimmed.map { "Started \($0) using \(configurationName)." }
            ?? "Started a \(configurationName) session."
        return "\(lead) \(sessionCount == 1 ? "1 session." : "Session 1 of \(sessionCount).")"
    }

    /// "Started your Morning Deep Work plan." (Plans mix configurations, so no single count.)
    static func startedPlan(task: String, planName: String) -> String {
        let trimmed = trimmedTask(task)
        return trimmed.map { "Started \($0) from your \(planName) plan." }
            ?? "Started your \(planName) plan."
    }

    // MARK: Control confirmations

    static let paused = "Time Frame is paused."
    static let resumed = "Time Frame has resumed."
    static let skipped = "Skipped the current interval."
    static let restarted = "Restarted the current interval."
    static let stopped = "Time Frame session stopped."
    static let completedBySkip = "That was the last interval — your Time Frame session is complete."

    // MARK: Helpers

    /// A spoken remaining-time clause rounded to whole minutes, e.g. "18 minutes",
    /// "1 minute", or "less than a minute". Never negative.
    static func remainingClause(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let minutes = Int((clamped / 60).rounded())
        if minutes <= 0 { return "less than a minute" }
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    /// A non-empty, trimmed task name, or `nil` if the session has no meaningful title.
    private static func trimmedTask(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
