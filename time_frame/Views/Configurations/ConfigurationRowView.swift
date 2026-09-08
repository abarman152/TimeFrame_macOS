//
//  ConfigurationRowView.swift
//  time_frame
//
//  A single row in the configuration list: the name, a clearly-labelled Default badge (text,
//  not colour alone), and the four numbers that define the configuration.
//
//  Milestone 29: the numbers moved from a stacked block of grey lines into one compact metric
//  strip, so a list of configurations can be compared at a glance instead of read line by
//  line. Content only — the list owns every action.
//

import SwiftUI

struct ConfigurationRowView: View {
    let configuration: PomodoroConfiguration

    var body: some View {
        HStack(alignment: .center, spacing: TFSpacing.m) {
            TFSymbolTile(systemImage: "slider.horizontal.3", size: .medium)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: TFSpacing.s) {
                    Text(configuration.name)
                        .font(.headline)
                        .lineLimit(1)
                    if configuration.isDefault {
                        TFDefaultMarker(accessibilityText: "Default configuration")
                    }
                }

                // Wide windows get the full strip; narrow ones fall back to a single summary
                // line rather than clipping or forcing the window to scroll sideways.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: TFSpacing.l) {
                        metric("Focus", TimeFormatting.minutesLabel(configuration.focusDuration))
                        metric("Short break", TimeFormatting.minutesLabel(configuration.shortBreakDuration))
                        metric("Long break", TimeFormatting.minutesLabel(configuration.longBreakDuration))
                        metric("Sessions", "\(configuration.defaultTotalSessions)")
                        metric("Long break every", "\(configuration.sessionsBeforeLongBreak)")
                    }

                    HStack(spacing: TFSpacing.l) {
                        metric("Focus", TimeFormatting.minutesLabel(configuration.focusDuration))
                        metric("Short break", TimeFormatting.minutesLabel(configuration.shortBreakDuration))
                        metric("Long break", TimeFormatting.minutesLabel(configuration.longBreakDuration))
                        metric("Sessions", "\(configuration.defaultTotalSessions)")
                    }

                    Text(compactSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .accessibilityHidden(true)
            }

            Spacer(minLength: TFSpacing.s)
        }
        .padding(.leading, TFSpacing.m)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// The narrow fallback: the same numbers, read as one sentence.
    private var compactSummary: String {
        [
            "\(TimeFormatting.minutesLabel(configuration.focusDuration)) focus",
            "\(TimeFormatting.minutesLabel(configuration.shortBreakDuration)) short break",
            "\(TimeFormatting.minutesLabel(configuration.longBreakDuration)) long break",
            "\(configuration.defaultTotalSessions) sessions",
            "long break every \(configuration.sessionsBeforeLongBreak)"
        ].joined(separator: " · ")
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.medium).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

/// The Configurations list's words in one place, so the row and VoiceOver agree.
enum ConfigurationRowPresentation {
    static func accessibilityLabel(for configuration: PomodoroConfiguration) -> String {
        let defaultNote = configuration.isDefault ? ", default configuration" : ""
        return """
        \(configuration.name)\(defaultNote), \
        \(TimeFormatting.minutesLabel(configuration.focusDuration)) focus, \
        \(TimeFormatting.minutesLabel(configuration.shortBreakDuration)) short break, \
        \(TimeFormatting.minutesLabel(configuration.longBreakDuration)) long break, \
        \(configuration.defaultTotalSessions) sessions, \
        long break every \(configuration.sessionsBeforeLongBreak)
        """
    }
}
