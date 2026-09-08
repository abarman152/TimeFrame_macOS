//
//  MenuBarTimerView.swift
//  time_frame
//
//  The countdown block of the popover: phase, the large remaining time, the focus
//  progress dots, the "Session X of N" line, and the next interval. Like the main
//  `TimerDisplay`, it derives everything from the authoritative projection on every
//  redraw and owns no counter of its own. A `TimelineView` schedules ~1 Hz redraws
//  only while running; paused/finished states are frozen (§10/§11/§18/§33).
//

import SwiftUI

struct MenuBarTimerView: View {
    let menuBar: MenuBarCoordinator

    var body: some View {
        let state = menuBar.presentation
        if state.state == .running {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                content(menuBar.presentation)
            }
        } else {
            content(state)
        }
    }

    private func content(_ state: MenuBarPresentationState) -> some View {
        VStack(spacing: TFSpacing.s) {
            if let phase = state.phase {
                Label(phase.displayLabel, systemImage: phase.symbol)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .foregroundStyle(phase.tint)
                    .labelStyle(.titleAndIcon)
            }

            Text(TimeFormatting.clock(state.remaining))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel("Time remaining")
                .accessibilityValue(TimeFormatting.accessibleClock(state.remaining))
                .accessibilityAddTraits(.updatesFrequently)

            if state.state == .paused {
                // Paused is conveyed by an explicit label + icon, never colour alone (a11y §48).
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TFPalette.paused)
            }

            focusProgress(state)

            nextUp(state)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Focus progress dots + session line

    @ViewBuilder
    private func focusProgress(_ state: MenuBarPresentationState) -> some View {
        if let total = state.totalFocusSessions, total > 0 {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { index in
                        Circle()
                            .strokeBorder(dotIsCurrent(index, state) ? Color.accentColor : Color.secondary.opacity(0.5),
                                          lineWidth: 1.5)
                            .background(Circle().fill(dotIsFilled(index, state) ? Color.accentColor : Color.clear))
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityHidden(true)

                Text(sessionLine(state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(sessionLine(state))
        }
    }

    /// A dot is filled once its focus session has fully completed.
    private func dotIsFilled(_ index: Int, _ state: MenuBarPresentationState) -> Bool {
        index < state.completedFocusCount
    }

    /// The current focus session's dot is highlighted (ring) while that focus runs.
    private func dotIsCurrent(_ index: Int, _ state: MenuBarPresentationState) -> Bool {
        state.currentPhaseIsFocus && index == state.completedFocusCount
    }

    private func sessionLine(_ state: MenuBarPresentationState) -> String {
        guard let total = state.totalFocusSessions else { return "" }
        if state.currentPhaseIsFocus, let current = state.currentFocusNumber {
            return "Session \(current) of \(total)"
        }
        // On a break: the focus sessions completed so far.
        let done = state.completedFocusCount
        if done == total {
            return "\(total) focus session\(total == 1 ? "" : "s") complete"
        }
        return "Session \(done) complete"
    }

    // MARK: Next interval

    @ViewBuilder
    private func nextUp(_ state: MenuBarPresentationState) -> some View {
        if let phase = state.nextPhase, let duration = state.nextDuration {
            HStack(spacing: 6) {
                Text("Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Label(phase.displayLabel, systemImage: phase.symbol)
                    .font(.caption)
                Text("· \(TimeFormatting.minutesLabel(duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Next: \(phase.displayLabel), \(TimeFormatting.minutesLabel(duration))")
        }
    }
}
