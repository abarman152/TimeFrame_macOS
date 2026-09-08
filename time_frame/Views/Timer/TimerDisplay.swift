//
//  TimerDisplay.swift
//  time_frame
//
//  The large countdown readout. It derives the remaining time from the engine on
//  every redraw; it never owns or decrements a counter of its own. A
//  `TimelineView` merely schedules ~1 Hz redraws so the derived value visibly
//  ticks — the authoritative time still lives in the engine's timeline.
//

import SwiftUI

struct TimerDisplay: View {
    /// The shared engine (observed). The display reads its derived state; it is
    /// never the source of truth.
    let engine: TimerEngine

    var body: some View {
        // Only schedule live redraws while running (a paused/idle interval is
        // frozen, so no per-second refresh is needed — observation still
        // re-renders on the next state change).
        if engine.state == .running {
            TimelineView(.periodic(from: .now, by: 1)) { _ in content }
        } else {
            content
        }
    }

    private var content: some View {
        let remaining = engine.remaining
        let phase = engine.currentPhase
        return VStack(spacing: TFSpacing.m) {
            // Phase: a small, uppercase semantic label carrying the phase's subtle
            // colour identity (§11/§13). The label — never colour alone — is the
            // authoritative carrier of the phase (§48).
            if let phase {
                Label(phase.displayLabel, systemImage: phase.symbol)
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(phase.tint)
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("timeFrame.timer.phase")
                    .tfAnimation(TFMotion.phase, value: phase)
            }

            // The centrepiece countdown: very large, high-contrast, monospaced digits.
            // The value is derived from the engine on every redraw; the numericText
            // content transition animates only the digits that change, never a
            // per-second layout/scale animation (§13/§14/§39).
            Text(TimeFormatting.clock(remaining))
                .font(.system(size: 88, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
                .accessibilityIdentifier("timeFrame.timer.countdown")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.map { "\($0.displayLabel), time remaining" } ?? "Time remaining")
        .accessibilityValue(TimeFormatting.accessibleClock(remaining))
        // The countdown re-derives every second while running; tell assistive tech the
        // value updates often so it is not treated as a discrete change to interrupt with.
        .accessibilityAddTraits(.updatesFrequently)
    }
}
