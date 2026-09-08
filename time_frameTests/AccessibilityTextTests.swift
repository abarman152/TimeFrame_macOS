//
//  AccessibilityTextTests.swift
//  time_frameTests (Milestone 17)
//
//  Deterministic accessibility-text coverage. Time Frame's rule (since Milestone 3) is that
//  essential state is always carried by a *word*, never colour or icon alone. These tests
//  lock in the pure text helpers behind that rule — the spoken countdown, the status/phase
//  labels, and the menu-bar VoiceOver description — so a regression that drops a label or
//  leaves a bare "00:00" is caught without rendering any UI.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Accessibility text — spoken durations")
struct SpokenDurationTests {

    @Test("Zero and negative remaining speak as 0 seconds (never NaN or a minus sign)")
    func zeroAndNegative() {
        #expect(TimeFormatting.accessibleClock(0) == "0 seconds")
        #expect(TimeFormatting.accessibleClock(-42) == "0 seconds")
    }

    @Test("Singular and plural units are correct")
    func pluralisation() {
        #expect(TimeFormatting.accessibleClock(1) == "1 second")
        #expect(TimeFormatting.accessibleClock(2) == "2 seconds")
        #expect(TimeFormatting.accessibleClock(60) == "1 minute 0 seconds")
        #expect(TimeFormatting.accessibleClock(61) == "1 minute 1 second")
    }

    @Test("Minutes and hours compose")
    func composition() {
        #expect(TimeFormatting.accessibleClock(65) == "1 minute 5 seconds")
        #expect(TimeFormatting.accessibleClock(1_500) == "25 minutes 0 seconds")
        #expect(TimeFormatting.accessibleClock(3_661) == "1 hour 1 minute 1 second")
        #expect(TimeFormatting.accessibleClock(7_200) == "2 hours 0 seconds")
    }
}

@Suite("Accessibility text — status & phase labels")
struct StatusLabelTests {

    @Test("Every session status has a non-empty, distinct label and a symbol")
    func sessionStatusLabels() {
        let all: [SessionStatus] = [.planned, .running, .paused, .completed, .cancelled, .interrupted]
        let labels = all.map(\.displayLabel)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == labels.count, "Status labels must be distinguishable by text")
        #expect(all.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test("Every phase has a non-empty, distinct label and a symbol")
    func phaseLabels() {
        let all: [TimerPhase] = [.focus, .shortBreak, .longBreak]
        let labels = all.map(\.displayLabel)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == labels.count)
        #expect(all.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test("Every interval status has a non-empty label")
    func intervalStatusLabels() {
        let all: [IntervalStatus] = [.pending, .running, .paused, .completed, .skipped, .cancelled]
        #expect(all.map(\.displayLabel).allSatisfy { !$0.isEmpty })
    }
}

@Suite("Accessibility text — menu bar status")
struct MenuBarAccessibilityTextTests {

    /// A menu-bar projection with sensible defaults; override only what a case needs.
    private func state(
        situation: MenuBarPresentationState.Situation,
        phase: TimerPhase? = nil,
        state: TimerState = .idle,
        remaining: TimeInterval = 0
    ) -> MenuBarPresentationState {
        MenuBarPresentationState(
            situation: situation,
            hasActiveSession: situation == .running || situation == .paused,
            taskName: nil,
            configurationName: nil,
            phase: phase,
            state: state,
            remaining: remaining,
            currentFocusNumber: nil,
            totalFocusSessions: nil,
            completedFocusCount: 0,
            nextPhase: nil,
            nextDuration: nil,
            recovery: situation == .interrupted ? .interrupted : .none
        )
    }

    @Test("The VoiceOver label always names the app and conveys state as words")
    func accessibilityLabelConveysState() {
        let empty = MenuBarStatusPresentation.accessibilityLabel(for: state(situation: .empty))
        #expect(empty == "Time Frame, no active session")

        let running = MenuBarStatusPresentation.accessibilityLabel(
            for: state(situation: .running, phase: .focus, state: .running, remaining: 90))
        #expect(running.contains("Focus"))
        #expect(running.contains("1 minute 30 seconds remaining"))

        let paused = MenuBarStatusPresentation.accessibilityLabel(
            for: state(situation: .paused, phase: .focus, state: .paused, remaining: 300))
        #expect(paused.contains("paused"))
        #expect(paused.contains("5 minutes 0 seconds remaining"))

        let completed = MenuBarStatusPresentation.accessibilityLabel(for: state(situation: .completed))
        #expect(completed.contains("complete"))

        let interrupted = MenuBarStatusPresentation.accessibilityLabel(for: state(situation: .interrupted))
        #expect(interrupted.contains("interrupted"))
    }

    @Test("The compact title is never a bare countdown and honours the show-countdown flag")
    func titleIsNeverBare() {
        // Idle/interrupted/completed always show a word, never 00:00.
        #expect(MenuBarStatusPresentation.title(for: state(situation: .empty), showCountdown: true) == "Time Frame")
        #expect(MenuBarStatusPresentation.title(for: state(situation: .completed), showCountdown: true) == "Done")

        let running = state(situation: .running, phase: .shortBreak, state: .running, remaining: 120)
        #expect(MenuBarStatusPresentation.title(for: running, showCountdown: false) == "Break")
        #expect(MenuBarStatusPresentation.title(for: running, showCountdown: true).hasPrefix("Break "))
    }

    @Test("The status symbol is always a non-empty SF Symbol name")
    func symbolAlwaysPresent() {
        for situation in [MenuBarPresentationState.Situation.empty, .running, .paused, .completed, .interrupted] {
            #expect(MenuBarStatusPresentation.symbolName(for: state(situation: situation)).isEmpty == false)
        }
    }
}
