//
//  PlanItemRowView.swift
//  time_frame
//
//  One interval row inside the plan editor's timeline: its position, kind, focus
//  configuration (if any), and duration. Reads a value-typed `PlanItemDraft`.
//

import SwiftUI

struct PlanItemRowView: View {
    /// 1-based position for display.
    let number: Int
    let item: PlanItemDraft

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.phase.displayLabel)
                        .font(.body)
                    if item.isFocus {
                        Text(configurationLabel)
                            .font(.caption)
                            .foregroundStyle(configurationMissing ? .orange : .secondary)
                    }
                }
            } icon: {
                Image(systemName: item.phase.symbol)
                    .foregroundStyle(item.phase.tint)
            }

            Spacer()

            Text(TimeFormatting.minutesLabel(item.duration))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var configurationMissing: Bool {
        item.isFocus && item.configurationID == nil
    }

    private var configurationLabel: String {
        if configurationMissing { return "No configuration" }
        return item.configurationName.isEmpty ? "Configuration" : item.configurationName
    }

    private var accessibilityLabel: String {
        var parts = ["Interval \(number)", item.phase.displayLabel]
        if item.isFocus { parts.append(configurationLabel) }
        parts.append(TimeFormatting.minutesLabel(item.duration))
        return parts.joined(separator: ", ")
    }
}
