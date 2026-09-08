//
//  HistoryDetailView.swift
//  time_frame
//
//  A read-only inspector for one past session. Everything shown comes from the
//  persisted session/interval rows — never reconstructed from the current
//  configuration — so historical timing stays accurate after edits.
//

import SwiftUI

struct HistoryDetailView: View {
    let session: FocusSession

    private var intervals: [SessionInterval] { session.orderedIntervals }

    var body: some View {
        List {
            Section {
                LabeledContent("Configuration", value: session.displayConfigurationName)
                if let started = session.startedAt {
                    LabeledContent("Started", value: started.formatted(date: .abbreviated, time: .shortened))
                }
                if let ended = session.endedAt {
                    LabeledContent("Ended", value: ended.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Status") {
                    Label(session.status.displayLabel, systemImage: session.status.symbol)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(session.status.tint)
                }
                LabeledContent("Focus completed",
                               value: "\(session.completedFocusCount) of \(session.plannedFocusCount)")
                LabeledContent("Total focus time",
                               value: TimeFormatting.compactDuration(session.completedFocusDuration))
            }

            Section("Intervals") {
                if intervals.isEmpty {
                    Text("No intervals recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(intervals) { interval in
                        HStack(spacing: 12) {
                            Label(interval.phase.displayLabel, systemImage: interval.phase.symbol)
                                .labelStyle(.titleAndIcon)
                            Spacer()
                            Text(TimeFormatting.minutesLabel(interval.plannedDuration))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(interval.status.displayLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 84, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(interval.phase.displayLabel), \(TimeFormatting.minutesLabel(interval.plannedDuration)), \(interval.status.displayLabel)")
                    }
                }
            }
        }
        .navigationTitle(session.taskName.isEmpty ? "Focus Session" : session.taskName)
    }
}
