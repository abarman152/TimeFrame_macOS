//
//  CompletionView.swift
//  time_frame
//
//  Shown when a run finishes all of its intervals. The persisted session already
//  holds the final state (this screen creates no new history); it just summarizes
//  the completed run and offers a fresh start.
//

import SwiftUI

struct CompletionView: View {
    let coordinator: SessionCoordinator

    private var engine: TimerEngine { coordinator.engine }

    /// Completed focus intervals from the just-finished run.
    private var completedFocus: [IntervalRecord] {
        engine.completedIntervals.filter { $0.phase == .focus && $0.outcome == .completed }
    }

    private var totalFocusTime: TimeInterval {
        completedFocus.reduce(0) { $0 + $1.plannedDuration }
    }

    private var taskName: String {
        let name = coordinator.activeSession?.taskName ?? ""
        return name.isEmpty ? "Focus session" : name
    }

    var body: some View {
        VStack(spacing: TFSpacing.l) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(TFPalette.completed)
                .accessibilityHidden(true)

            VStack(spacing: TFSpacing.xs) {
                Text("Session Complete")
                    .font(.largeTitle.weight(.bold))
                Text(taskName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // A restrained glass summary card: the headline metrics grouped on a single
            // floating surface (§18). Rewarding but professional, not gamified.
            VStack(spacing: TFSpacing.m) {
                Text("^[\(completedFocus.count) of \(max(completedFocus.count, engine.totalFocusSessions)) focus session](inflect: true) completed.")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                VStack(spacing: TFSpacing.xs) {
                    Text("Total focus time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(TimeFormatting.compactDuration(totalFocusTime))
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, TFSpacing.xxl)
            .padding(.vertical, TFSpacing.xl)
            .tfGlassSurface(cornerRadius: TFRadius.large)

            Button {
                coordinator.prepareForNewSession()
            } label: {
                Label("Start New Session", systemImage: "arrow.clockwise")
                    .font(.headline)
            }
            .controlSize(.large)
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("timeFrame.timer.startNew")
            .padding(.top, TFSpacing.s)
        }
        .padding(TFSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
