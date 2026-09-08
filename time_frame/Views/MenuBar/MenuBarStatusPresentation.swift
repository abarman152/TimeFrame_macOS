//
//  MenuBarStatusPresentation.swift
//  time_frame
//
//  Pure mapping from a `MenuBarPresentationState` to the compact status-bar title and
//  its SF Symbol (§8/§44). Kept free of SwiftUI so the exact strings are unit-testable
//  without rendering the menu bar (§55/§57). Essential state is always carried by the
//  *word* ("Focus" / "Break" / "Paused"), never colour or icon alone (a11y rule shared
//  with `StatusPresentation`).
//

import Foundation

/// Derives the menu-bar title, icon, and spoken description from the projection.
nonisolated enum MenuBarStatusPresentation {

    /// The compact status-bar title. Always non-empty (never a bare `00:00` — §50):
    /// idle/interrupted show the app name, completion shows "Done", and an active
    /// session shows the phase word optionally followed by the live countdown (§8).
    static func title(for state: MenuBarPresentationState, showCountdown: Bool) -> String {
        switch state.situation {
        case .empty, .interrupted:
            return "Time Frame"
        case .completed:
            return "Done"
        case .running:
            let word = phaseWord(for: state.phase)
            return showCountdown ? "\(word) \(TimeFormatting.clock(state.remaining))" : word
        case .paused:
            return showCountdown ? "Paused \(TimeFormatting.clock(state.remaining))" : "Paused"
        }
    }

    /// The SF Symbol shown beside/instead of the title. A stable, low-noise icon whose
    /// meaning is reinforced by the title text (§44).
    static func symbolName(for state: MenuBarPresentationState) -> String {
        switch state.situation {
        case .empty:
            return "timer"
        case .running:
            return state.currentPhaseIsFocus ? "timer" : "cup.and.saucer"
        case .paused:
            return "pause.circle"
        case .completed:
            return "checkmark.circle"
        case .interrupted:
            return "exclamationmark.triangle"
        }
    }

    /// A VoiceOver-friendly description of the whole status item (§41).
    static func accessibilityLabel(for state: MenuBarPresentationState) -> String {
        switch state.situation {
        case .empty:
            return "Time Frame, no active session"
        case .interrupted:
            return "Time Frame, previous session interrupted"
        case .completed:
            return "Time Frame, session complete"
        case .running:
            return "Time Frame, \(phaseWord(for: state.phase)), \(TimeFormatting.accessibleClock(state.remaining)) remaining"
        case .paused:
            return "Time Frame, paused, \(TimeFormatting.accessibleClock(state.remaining)) remaining"
        }
    }

    /// The short word for a phase used in the compact title ("Break" for either break so
    /// the title stays narrow — §8/§45). Falls back to the app name if there is no phase.
    static func phaseWord(for phase: TimerPhase?) -> String {
        switch phase {
        case .focus: return "Focus"
        case .shortBreak, .longBreak: return "Break"
        case nil: return "Time Frame"
        }
    }
}
