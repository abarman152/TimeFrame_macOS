//
//  MenuBarEmptyStateView.swift
//  time_frame
//
//  The idle / completed / interrupted header of the popover. Kept useful even with no
//  running session (§50): a short status line and a primary action. Starting from here
//  never builds a second start flow — it opens the main window's existing setup screen
//  (§13/§21), wired by `MenuBarControlsView`.
//

import SwiftUI

struct MenuBarEmptyStateView: View {
    let state: MenuBarPresentationState

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(headline)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch state.situation {
        case .completed: "checkmark.circle.fill"
        case .interrupted: "exclamationmark.triangle.fill"
        default: "timer"
        }
    }

    private var tint: Color {
        switch state.situation {
        case .completed: TFPalette.completed
        case .interrupted: TFPalette.warning
        default: .secondary
        }
    }

    private var headline: String {
        switch state.situation {
        case .completed: "Session complete"
        case .interrupted: "Session interrupted"
        default: "Time Frame"
        }
    }

    private var subtitle: String? {
        switch state.situation {
        case .completed:
            let name = state.taskName ?? ""
            if let total = state.totalFocusSessions, total > 0 {
                let sessions = "\(total) focus session\(total == 1 ? "" : "s")"
                return name.isEmpty ? sessions : "\(name) · \(sessions)"
            }
            return name.isEmpty ? nil : name
        case .interrupted:
            return "It's been saved to History."
        default:
            return "Ready to focus"
        }
    }
}
