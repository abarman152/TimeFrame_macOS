//
//  KeyboardNavigationAuditTests.swift
//  time_frameTests (Milestone 17)
//
//  Keyboard-reachability regression guard. SwiftUI's `keyboardShortcut`/`focused` modifiers
//  can't be exercised without a rendered UI, but their *presence* on the primary controls
//  can be asserted by scanning the source (comments/strings blanked — see `SourceAudit`).
//  This locks in that every timer transport control keeps both a keyboard shortcut and a
//  stable accessibility identifier, that the setup form can be started from the keyboard,
//  and that every modal editor stays keyboard-confirmable and -cancelable — so a future
//  refactor can't quietly strip keyboard access.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Keyboard navigation audit")
struct KeyboardNavigationAuditTests {

    // Keeps string literals: accessibility identifiers are string constants we must find.
    private func code(_ relativePath: String) -> String {
        SourceAudit.codeKeepingStrings(SourceAudit.appTarget().appendingPathComponent(relativePath))
    }

    @Test("Every timer transport control has a keyboard shortcut and a stable identifier")
    func transportControlsAreKeyboardReachable() {
        let text = code("Views/Timer/TimerControls.swift")

        // Each control is addressable (for automation/VoiceOver) by a stable identifier.
        for identifier in ["timeFrame.timer.pause", "timeFrame.timer.resume", "timeFrame.timer.stop",
                           "timeFrame.timer.restart", "timeFrame.timer.skip"] {
            #expect(text.contains(identifier), "Missing control identifier \(identifier)")
        }

        // Pause/Resume (Space), Stop (Escape), Restart (R), Skip (→): at least five shortcuts.
        let shortcutCount = text.components(separatedBy: "keyboardShortcut").count - 1
        #expect(shortcutCount >= 5, "Expected ≥5 keyboard shortcuts, found \(shortcutCount)")

        // The dominant Pause/Resume action binds Space; Stop binds the cancel action (Escape).
        #expect(text.contains(".space"))
        #expect(text.contains(".cancelAction"))
        #expect(text.contains(".rightArrow"))   // Skip
    }

    @Test("The session setup form can be started from the keyboard and focuses its task field")
    func setupIsKeyboardOperable() {
        let text = code("Views/Timer/SessionSetupView.swift")
        // Cmd+Return starts the session; the task field takes focus via @FocusState.
        #expect(text.contains(".return"))
        #expect(text.contains("modifiers: .command"))
        #expect(text.contains("FocusState"))
        #expect(text.contains(".focused("))
    }

    @Test("Every modal editor is keyboard-confirmable and -cancelable")
    func editorsHaveDefaultAndCancelActions() {
        for editor in ["Views/Configurations/ConfigurationEditorView.swift",
                       "Views/Templates/TemplateEditorView.swift",
                       "Views/Plans/PlanEditorView.swift",
                       "Views/Plans/PlanItemEditorView.swift"] {
            let text = code(editor)
            #expect(text.contains(".defaultAction"), "\(editor) has no default (Return) action")
            #expect(text.contains(".cancelAction"), "\(editor) has no cancel (Escape) action")
        }
    }
}
