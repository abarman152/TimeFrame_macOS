//
//  PlanPreviewView.swift
//  time_frame
//
//  A read-only preview of a plan before it runs: totals plus a relative timeline
//  (0:00, 0:50, 1:00 …). Built from a `SessionPlanExecutionSnapshot`, so it shows
//  exactly what will execute — the same frozen values `startPlan` runs from. No
//  fake calendar date is invented (start time belongs to a later milestone).
//

import SwiftUI

struct PlanPreviewView: View {
    let snapshot: SessionPlanExecutionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: TFSpacing.s) {
            summaryLine

            VStack(spacing: 0) {
                let rows = timelineRows
                ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                    let row = pair.element
                    HStack(spacing: TFSpacing.m) {
                        Text("\(pair.offset + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                            .accessibilityHidden(true)

                        Text(row.offset)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .leading)
                            .accessibilityHidden(true)

                        Circle()
                            .fill(row.tint)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)

                        Image(systemName: row.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                            .accessibilityHidden(true)

                        Text(row.title)
                            .font(.callout)
                            .lineLimit(1)

                        Spacer(minLength: TFSpacing.m)

                        Text(row.duration)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, TFSpacing.l)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Interval \(pair.offset + 1) at \(row.offset), \(row.title), \(row.duration)")

                    if pair.offset < rows.count - 1 {
                        TFRowDivider(leadingInset: TFSpacing.l)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tfCard()
        }
    }

    private var summaryLine: some View {
        HStack(spacing: 6) {
            Text("^[\(snapshot.intervals.count) interval](inflect: true)")
            Text("·").foregroundStyle(.secondary)
            Text("^[\(snapshot.focusCount) focus session](inflect: true)")
            Text("·").foregroundStyle(.secondary)
            Text(TimeFormatting.compactDuration(snapshot.totalDuration))
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.intervals.count) intervals, \(snapshot.focusCount) focus sessions, \(TimeFormatting.compactDuration(snapshot.totalDuration)) total")
    }

    private struct Row {
        let offset: String
        let title: String
        let symbol: String
        let tint: Color
        let duration: String
    }

    private var timelineRows: [Row] {
        var rows: [Row] = []
        var elapsed: TimeInterval = 0
        for interval in snapshot.intervals {
            let title: String
            if interval.phase == .focus, !interval.configurationName.isEmpty {
                title = "\(interval.phase.displayLabel) · \(interval.configurationName)"
            } else {
                title = interval.phase.displayLabel
            }
            rows.append(Row(
                offset: Self.offsetLabel(elapsed),
                title: title,
                symbol: interval.phase.symbol,
                tint: interval.phase.tint,
                duration: TimeFormatting.minutesLabel(interval.duration)
            ))
            elapsed += interval.duration
        }
        return rows
    }

    /// A relative `H:MM` offset from the start of the plan.
    private static func offsetLabel(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded(.down))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%d:%02d", hours, minutes)
    }
}
