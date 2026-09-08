//
//  ControlCenterPresentationTests.swift
//  time_frameTests (Milestone 22)
//
//  The pure decision layer behind the iOS Control Center controls (`ControlCenterPresentation`,
//  Shared/). These tests prove — with no WidgetKit host, no coordinator, no clock — that:
//
//   • the situation is derived correctly from the read-only projection (state × phase);
//   • the control set is semantically sound (a break offers skip, not pause), matching the M15
//     `WidgetControlSet` philosophy so the two surfaces never disagree (Part 5);
//   • the adaptive primary action is total and correct for every situation (Part 3);
//   • every control has a meaningful, glyph-independent VoiceOver label (Part 6);
//   • the mapping is deterministic (same input → same output).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Control Center — situation projection")
struct ControlCenterSituationTests {

    private func projection(_ state: WidgetSessionState, _ phase: WidgetPhase) -> WidgetProjection {
        WidgetProjection(generatedAt: Date(timeIntervalSinceReferenceDate: 700_000_000),
                         state: state, phase: phase)
    }

    @Test("Idle projection → idle situation")
    func idle() {
        #expect(ControlCenterSessionState(projection: projection(.idle, .none)) == .idle)
    }

    @Test("Running + focus → focusRunning; running + break → breakRunning")
    func running() {
        #expect(ControlCenterSessionState(projection: projection(.running, .focus)) == .focusRunning)
        #expect(ControlCenterSessionState(projection: projection(.running, .shortBreak)) == .breakRunning)
        #expect(ControlCenterSessionState(projection: projection(.running, .longBreak)) == .breakRunning)
    }

    @Test("Paused / completed / interrupted / unavailable map 1:1")
    func others() {
        #expect(ControlCenterSessionState(projection: projection(.paused, .focus)) == .paused)
        #expect(ControlCenterSessionState(projection: projection(.completed, .none)) == .completed)
        #expect(ControlCenterSessionState(projection: projection(.interrupted, .none)) == .interrupted)
        #expect(ControlCenterSessionState(projection: projection(.unavailable, .none)) == .unavailable)
    }

    @Test("isActive / isRunning reflect a live session")
    func activity() {
        #expect(ControlCenterSessionState.focusRunning.isActive)
        #expect(ControlCenterSessionState.breakRunning.isActive)
        #expect(ControlCenterSessionState.paused.isActive)
        #expect(!ControlCenterSessionState.idle.isActive)
        #expect(!ControlCenterSessionState.completed.isActive)
        #expect(!ControlCenterSessionState.interrupted.isActive)
        #expect(!ControlCenterSessionState.unavailable.isActive)

        #expect(ControlCenterSessionState.focusRunning.isRunning)
        #expect(ControlCenterSessionState.breakRunning.isRunning)
        #expect(!ControlCenterSessionState.paused.isRunning)
        #expect(!ControlCenterSessionState.idle.isRunning)
    }
}

@Suite("Control Center — control set & primary action")
struct ControlCenterControlSetTests {

    @Test("Each situation offers only semantically valid controls (Part 5)")
    func controlsPerState() {
        #expect(ControlCenterControlSet.controls(for: .idle) == [.start])
        #expect(ControlCenterControlSet.controls(for: .completed) == [.start])
        #expect(ControlCenterControlSet.controls(for: .interrupted) == [.start])
        #expect(ControlCenterControlSet.controls(for: .unavailable) == [.start])
        #expect(ControlCenterControlSet.controls(for: .focusRunning) == [.pause, .skip, .stop])
        // A break can't be paused — skip advances it (mirrors M15 WidgetControlSet).
        #expect(ControlCenterControlSet.controls(for: .breakRunning) == [.skip, .stop])
        #expect(ControlCenterControlSet.controls(for: .paused) == [.resume, .stop])
    }

    @Test("A break never offers pause; a focus run always does")
    func breakNeverPauses() {
        #expect(!ControlCenterControlSet.isAvailable(.pause, in: .breakRunning))
        #expect(ControlCenterControlSet.isAvailable(.pause, in: .focusRunning))
    }

    @Test("The primary action is total and correct for every situation (Part 3)")
    func primaryActionPerState() {
        #expect(ControlCenterControlSet.primaryAction(for: .idle) == .start)
        #expect(ControlCenterControlSet.primaryAction(for: .completed) == .start)
        #expect(ControlCenterControlSet.primaryAction(for: .interrupted) == .start)
        #expect(ControlCenterControlSet.primaryAction(for: .unavailable) == .start)
        #expect(ControlCenterControlSet.primaryAction(for: .focusRunning) == .pause)
        #expect(ControlCenterControlSet.primaryAction(for: .breakRunning) == .skip)
        #expect(ControlCenterControlSet.primaryAction(for: .paused) == .resume)
    }

    @Test("Stop is available exactly when a session is active")
    func stopAvailability() {
        for state in ControlCenterSessionState.allCases {
            #expect(ControlCenterControlSet.isAvailable(.stop, in: state) == state.isActive)
        }
    }
}

@Suite("Control Center — appearance & accessibility")
struct ControlCenterAppearanceTests {

    @Test("Every action has a non-empty title, symbol, and glyph-independent VoiceOver label (Part 6)")
    func everyActionIsLabelled() {
        for action in WidgetControlAction.allCases {
            let a = ControlCenterActionCatalog.appearance(for: action)
            #expect(!a.title.isEmpty, "\(action) has no title")
            #expect(!a.symbolName.isEmpty, "\(action) has no symbol")
            #expect(!a.accessibilityLabel.isEmpty, "\(action) has no accessibility label")
            // The spoken label must not be a bare symbol name (never glyph-only).
            #expect(!a.accessibilityLabel.contains("."), "\(action) label looks like a symbol name")
        }
    }

    @Test("The VoiceOver phrasing matches the documented control names (Part 6)")
    func documentedLabels() {
        #expect(ControlCenterActionCatalog.appearance(for: .start).accessibilityLabel == "Start Timer")
        #expect(ControlCenterActionCatalog.appearance(for: .pause).accessibilityLabel == "Pause Focus Timer")
        #expect(ControlCenterActionCatalog.appearance(for: .resume).accessibilityLabel == "Resume Focus Timer")
        #expect(ControlCenterActionCatalog.appearance(for: .skip).accessibilityLabel == "Skip Interval")
        #expect(ControlCenterActionCatalog.appearance(for: .stop).accessibilityLabel == "Stop Timer")
    }

    @Test("Primary content resolves action + appearance together and carries the active flag")
    func primaryContent() {
        let running = ControlCenterPresentation.primary(for: .focusRunning)
        #expect(running.action == .pause)
        #expect(running.title == "Pause")
        #expect(running.accessibilityLabel == "Pause Focus Timer")
        #expect(running.isActive)

        let idle = ControlCenterPresentation.primary(for: .idle)
        #expect(idle.action == .start)
        #expect(idle.accessibilityLabel == "Start Timer")
        #expect(!idle.isActive)
    }

    @Test("An unavailable projection yields the calm Start content (safe fallback)")
    func unavailableFallback() {
        let content = ControlCenterPresentation.primary(for: .unavailable(reason: "no data"))
        #expect(content.action == .start)
        #expect(content.state == .unavailable)
    }

    @Test("The mapping is deterministic — same input, same output")
    func deterministic() {
        let p = WidgetProjection(generatedAt: Date(), state: .running, phase: .focus)
        #expect(ControlCenterPresentation.primary(for: p) == ControlCenterPresentation.primary(for: p))
    }
}
