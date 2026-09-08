//
//  TimeFormatting.swift
//  time_frame
//
//  Pure, deterministic string formatting for durations and countdowns. Kept free
//  of SwiftUI so the timer/history views share one vocabulary and the formatting
//  is unit-testable without launching the UI.
//

import Foundation

/// Formats time intervals for display. All functions are pure and clamp negative
/// input to zero, so a momentarily-negative derived remaining never renders as a
/// minus sign.
nonisolated enum TimeFormatting {

    /// A countdown clock: `MM:SS`, or `H:MM:SS` once an hour or more remains.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    /// A compact human total: `3h 20m`, `50m`, or `45s`.
    static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(secs)s"
    }

    /// A precise human total that keeps seconds: `1h 5m`, `24m 52s`, or `45s`. Used
    /// where a rounded-to-minutes figure would hide meaningful detail — e.g. the
    /// average focus-interval statistic.
    static func preciseDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m" }
        return "\(secs)s"
    }

    /// A minutes-first label for plan/interval rows: `50 min`, or `30 sec` for
    /// sub-minute durations (used by the short test configurations).
    static func minutesLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes > 0 { return "\(minutes) min" }
        return "\(max(0, Int(seconds.rounded()))) sec"
    }

    /// A spoken-friendly countdown for VoiceOver: `42 minutes 18 seconds`.
    static func accessibleClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        parts.append("\(secs) second\(secs == 1 ? "" : "s")")
        return parts.joined(separator: " ")
    }
}
