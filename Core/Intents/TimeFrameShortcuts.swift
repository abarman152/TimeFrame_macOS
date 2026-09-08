//
//  TimeFrameShortcuts.swift
//  time_frame (Milestone 12)
//
//  The App Shortcuts Time Frame offers to Siri and the Shortcuts app with zero user setup.
//  Deliberately curated to the common workflows (start, start a template, the timer controls,
//  a status check, and opening the app) rather than one phrase per intent — a focused list
//  the system can surface well. Every phrase must include the app-name token
//  (`\(.applicationName)`), which the runtime replaces with "Time Frame".
//
//  This provider only *references* the intents; it owns no logic and no state.
//

import Foundation
import AppIntents

struct TimeFrameShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTimeFrameIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Start a \(.applicationName) session",
                "Begin focusing with \(.applicationName)"
            ],
            shortTitle: "Start Time Frame",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StartTemplateIntent(),
            phrases: [
                "Start my \(\.$template) template with \(.applicationName)",
                "Start the \(\.$template) template in \(.applicationName)"
            ],
            shortTitle: "Start Template",
            systemImageName: "square.stack.3d.up"
        )
        AppShortcut(
            intent: StartPlanIntent(),
            phrases: [
                "Start my \(\.$plan) plan with \(.applicationName)",
                "Start the \(\.$plan) plan in \(.applicationName)"
            ],
            shortTitle: "Start Plan",
            systemImageName: "list.bullet.rectangle"
        )
        AppShortcut(
            intent: PauseTimeFrameIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Pause my \(.applicationName) session"
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeTimeFrameIntent(),
            phrases: [
                "Resume \(.applicationName)",
                "Resume my \(.applicationName) session"
            ],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: SkipTimeFrameIntervalIntent(),
            phrases: [
                "Skip the current \(.applicationName) interval",
                "Skip this \(.applicationName) interval"
            ],
            shortTitle: "Skip Interval",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: StopTimeFrameIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Stop my \(.applicationName) session"
            ],
            shortTitle: "Stop",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: GetCurrentTimeFrameStatusIntent(),
            phrases: [
                "What's my \(.applicationName) status",
                "Check \(.applicationName)",
                "How much time is left in \(.applicationName)"
            ],
            shortTitle: "Check Status",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: OpenTimeFrameIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show \(.applicationName)"
            ],
            shortTitle: "Open Time Frame",
            systemImageName: "timer"
        )
    }
}
