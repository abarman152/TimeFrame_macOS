//
//  ConfigurationSummaryView.swift
//  time_frame
//
//  A compact, read-only summary of a configuration's durations and counts,
//  reused by the setup picker and the configuration list.
//

import SwiftUI

/// Shows a configuration's key numbers (focus / breaks / sessions) without
/// duplicating the configuration's *values* — it reads them straight off the
/// passed model.
struct ConfigurationSummaryView: View {
    let configuration: PomodoroConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            summaryLine("\(TimeFormatting.minutesLabel(configuration.focusDuration)) focus")
            summaryLine("\(TimeFormatting.minutesLabel(configuration.shortBreakDuration)) short break")
            summaryLine("\(TimeFormatting.minutesLabel(configuration.longBreakDuration)) long break")
            summaryLine("\(configuration.defaultTotalSessions) sessions · long break every \(configuration.sessionsBeforeLongBreak)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func summaryLine(_ text: String) -> some View {
        Text(text)
    }
}
