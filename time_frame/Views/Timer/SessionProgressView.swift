//
//  SessionProgressView.swift
//  time_frame
//
//  Focus-session progress dots plus a "Session X of Y" label. Derived entirely
//  from the engine — there is no UI-only session counter.
//

import SwiftUI

struct SessionProgressView: View {
    let engine: TimerEngine

    private var total: Int { max(0, engine.totalFocusSessions) }

    /// The 1-based focus session currently in progress (0 during a break before
    /// the first focus, or when idle).
    private var current: Int { engine.currentFocusNumber }

    /// Focus intervals already completed, for filled/empty dot state.
    private var completed: Int {
        engine.completedIntervals.filter { $0.phase == .focus && $0.outcome == .completed }.count
    }

    var body: some View {
        VStack(spacing: 8) {
            if total > 0 {
                HStack(spacing: 8) {
                    ForEach(0..<total, id: \.self) { index in
                        Circle()
                            .fill(dotFilled(index) ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle().strokeBorder(
                                    index + 1 == current ? Color.accentColor : .clear,
                                    lineWidth: 2
                                )
                                .padding(-3)
                            )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Focus sessions")
                .accessibilityValue("\(completed) of \(total) completed")

                Text("Session \(max(1, current)) of \(total)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A dot is filled if its focus session has completed, or is the one in
    /// progress.
    private func dotFilled(_ index: Int) -> Bool {
        let position = index + 1
        return position <= completed || position == current
    }
}
