//
//  WidgetFormatting.swift
//  TimeFrameWidgets (Milestone 11)
//
//  Small, pure display formatters for the widget. Kept local to the widget target (the
//  app has its own `TimeFormatting`); these render the projection's numbers and never
//  compute time themselves.
//

import Foundation

enum WidgetFormatting {

    /// A clock-style remaining string: `MM:SS`, or `H:MM:SS` past an hour. Used for the
    /// *frozen* paused reading (the running countdown uses SwiftUI's live timer text).
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// A compact focus-duration string for the today summary: `45m`, `1h 20m`, `2h`.
    static func focusDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 { return "\(minutes)m" }
        return total > 0 ? "<1m" : "0m"
    }

    /// A VoiceOver-friendly spoken duration, e.g. "1 hour 20 minutes", "5 minutes".
    static func spoken(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        if hours == 0, minutes == 0 { parts.append("\(secs) \(secs == 1 ? "second" : "seconds")") }
        return parts.joined(separator: " ")
    }
}
