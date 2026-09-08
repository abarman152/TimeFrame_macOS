//
//  StatusPresentation.swift
//  time_frame
//
//  Presentation mapping for domain enums: a user label, an SF Symbol, and a
//  tint. Essential state is always carried by the *label*, never by colour
//  alone, so the UI stays legible to colour-blind users (Milestone 3 a11y rule).
//

import SwiftUI

extension SessionStatus {
    /// A user-facing name for the session's lifecycle status.
    var displayLabel: String {
        switch self {
        case .planned: "Planned"
        case .running: "Running"
        case .paused: "Paused"
        case .completed: "Completed"
        case .cancelled: "Stopped"
        case .interrupted: "Interrupted"
        }
    }

    /// An SF Symbol paired with the label (decorative; the label is authoritative).
    var symbol: String {
        switch self {
        case .planned: "circle.dashed"
        case .running: "play.circle.fill"
        case .paused: "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "stop.circle.fill"
        case .interrupted: "exclamationmark.triangle.fill"
        }
    }

    /// A tint used alongside — never instead of — the label. Routed through the
    /// shared `TFPalette` so semantic colour has a single source (§10/ADR-052).
    var tint: Color {
        switch self {
        case .planned: .secondary
        case .running: TFPalette.running
        case .paused: TFPalette.paused
        case .completed: TFPalette.completed
        case .cancelled: .secondary
        case .interrupted: TFPalette.warning
        }
    }
}

extension TimerPhase {
    /// A user-facing name for the phase.
    var displayLabel: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    /// An SF Symbol for the phase.
    var symbol: String {
        switch self {
        case .focus: "brain.head.profile"
        case .shortBreak: "cup.and.saucer"
        case .longBreak: "figure.walk"
        }
    }

    /// The phase's semantic tint, from the shared `TFPalette` (ADR-052). Focus keeps a
    /// subtle accent identity; the two breaks are distinguishable but part of the same
    /// family (§11/§12).
    var tint: Color {
        switch self {
        case .focus: TFPalette.focus
        case .shortBreak: TFPalette.shortBreak
        case .longBreak: TFPalette.longBreak
        }
    }
}

extension IntervalStatus {
    /// A user-facing name for a persisted interval's status.
    var displayLabel: String {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .paused: "Paused"
        case .completed: "Completed"
        case .skipped: "Skipped"
        case .cancelled: "Stopped"
        }
    }
}
