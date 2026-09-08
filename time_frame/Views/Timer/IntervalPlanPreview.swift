//
//  IntervalPlanPreview.swift
//  time_frame
//
//  A lightweight, read-only preview of the interval sequence a *single-run* setup
//  will produce. Generated from the selected configuration and session count (never
//  hardcoded). This is the Timer setup screen's preview of an engine `IntervalPlan`;
//  the full Session Planner has its own `PlanPreviewView`.
//
//  Milestone 29: the rows moved into the shared card surface and gained an optional
//  presentation-only filter, so "Focus Only" / "Breaks Only" narrows what is *listed*
//  without touching the plan the engine will run.
//

import SwiftUI

struct IntervalPlanPreview: View {
    let plan: IntervalPlan
    /// Which phases to list. Presentation-only — the plan itself is unchanged.
    var includes: (TimerPhase) -> Bool = { _ in true }

    /// The plan's intervals paired with their real 1-based position, so a filtered list
    /// still says which step of the run each row is.
    private var rows: [(step: Int, interval: PlannedInterval)] {
        plan.intervals.enumerated()
            .filter { includes($0.element.phase) }
            .map { (step: $0.offset + 1, interval: $0.element) }
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            if rows.isEmpty {
                Text("No intervals of this kind in the plan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TFSpacing.l)
                    .padding(.vertical, TFSpacing.m)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                    row(step: pair.element.step, interval: pair.element.interval)
                    if pair.offset < rows.count - 1 {
                        TFRowDivider(leadingInset: TFSpacing.l)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tfCard()
        .accessibilityIdentifier("timeFrame.timer.planPreview")
    }

    private func row(step: Int, interval: PlannedInterval) -> some View {
        HStack(spacing: TFSpacing.m) {
            // A small phase-tinted marker plus the phase's own symbol: the colour groups,
            // the symbol and the words identify (§48).
            Circle()
                .fill(interval.phase.tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Image(systemName: interval.phase.symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(interval.phase.displayLabel)
                .font(.callout)

            Spacer(minLength: TFSpacing.m)

            Text(TimeFormatting.minutesLabel(interval.duration))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, TFSpacing.l)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step), \(interval.phase.displayLabel), \(TimeFormatting.minutesLabel(interval.duration))")
    }
}
