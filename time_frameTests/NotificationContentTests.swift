//
//  NotificationContentTests.swift
//  time_frameTests
//
//  Every notification type's text is generated purely and deterministically, with no
//  empty titles and the right task/duration/progress wording (§54).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Notification content")
struct NotificationContentTests {

    @Test("Focus notification announces the task and duration")
    func focusContent() {
        let content = NotificationContentGenerator.content(
            for: .focus(task: "Research Quantum IDS", duration: 25 * 60, configurationName: "Classic Pomodoro"))
        #expect(content.title == "Time to focus")
        #expect(content.subtitle == "Research Quantum IDS")
        #expect(content.body.contains("25 min"))
        #expect(content.body.contains("Classic Pomodoro"))
    }

    @Test("Focus without a task falls back to the app name, never empty")
    func focusNoTask() {
        let content = NotificationContentGenerator.content(
            for: .focus(task: "   ", duration: 60, configurationName: ""))
        #expect(content.title == "Time to focus")
        #expect(content.subtitle == "Time Frame")
        #expect(content.subtitle?.isEmpty == false)
        // No configuration → body is just the duration, nothing trailing.
        #expect(content.body == "1 min")
    }

    @Test("Short break notification invites a recharge")
    func shortBreakContent() {
        let content = NotificationContentGenerator.content(
            for: .shortBreak(task: "Writing", duration: 5 * 60))
        #expect(content.title == "Short break")
        #expect(content.subtitle == "Writing")
        #expect(content.body.contains("recharge"))
        #expect(content.body.contains("5 min"))
    }

    @Test("Long break notification reports completed sessions")
    func longBreakContent() {
        let content = NotificationContentGenerator.content(
            for: .longBreak(task: "", completedFocusCount: 4))
        #expect(content.title == "Long break")
        #expect(content.subtitle == nil) // no task → no app-name filler on a break
        #expect(content.body.contains("4 focus sessions"))
        #expect(content.body.contains("longer break"))
    }

    @Test("Completion notification summarises the focus count")
    func completionContent() {
        let content = NotificationContentGenerator.content(
            for: .sessionCompleted(task: "Research Quantum IDS", focusCount: 4))
        #expect(content.title == "Session complete")
        #expect(content.subtitle == "Research Quantum IDS")
        #expect(content.body == "4 focus sessions completed.")
    }

    @Test("Singular focus count reads naturally")
    func singularCount() {
        let content = NotificationContentGenerator.content(
            for: .sessionCompleted(task: "X", focusCount: 1))
        #expect(content.body == "1 focus session completed.")
    }
}
