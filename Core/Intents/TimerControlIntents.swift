//
//  TimerControlIntents.swift
//  time_frame (Milestone 12)
//
//  The five stateless timer-control intents — Pause, Resume, Skip, Restart, Stop. Each is a
//  thin command that routes through the SINGLE `SessionCoordinator` (the same path the main
//  UI, menu bar, and notification actions use) and returns a short spoken confirmation
//  (ADR-056). None of them implements a timer, a countdown, or any scheduling: the intent
//  finishes instantly and the engine keeps deriving time on its own.
//
//  "Stop" routes through the existing stop operation, which preserves completed intervals and
//  records the in-progress one as cancelled — it never deletes history.
//

import Foundation
import AppIntents

/// Pause the running session.
struct PauseTimeFrameIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Time Frame"
    static let description = IntentDescription("Pause the current Time Frame session.", categoryName: "Controls")
    static let openAppWhenRun = false

    @AppDependency private var coordinator: SessionCoordinator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AppIntentSessionActions(coordinator: coordinator).pause()
        return .result(dialog: IntentDialog("\(AppIntentDialogText.paused)"))
    }
}

/// Resume the paused session.
struct ResumeTimeFrameIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Time Frame"
    static let description = IntentDescription("Resume a paused Time Frame session.", categoryName: "Controls")
    static let openAppWhenRun = false

    @AppDependency private var coordinator: SessionCoordinator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AppIntentSessionActions(coordinator: coordinator).resume()
        return .result(dialog: IntentDialog("\(AppIntentDialogText.resumed)"))
    }
}

/// Skip the current interval, advancing to the next (or completing the session).
struct SkipTimeFrameIntervalIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Time Frame Interval"
    static let description = IntentDescription("Skip the current focus or break interval.", categoryName: "Controls")
    static let openAppWhenRun = false

    @AppDependency private var coordinator: SessionCoordinator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let didComplete = try AppIntentSessionActions(coordinator: coordinator).skip()
        let text = didComplete ? AppIntentDialogText.completedBySkip : AppIntentDialogText.skipped
        return .result(dialog: IntentDialog("\(text)"))
    }
}

/// Restart the current interval from its full duration, in place.
struct RestartTimeFrameIntervalIntent: AppIntent {
    static let title: LocalizedStringResource = "Restart Time Frame Interval"
    static let description = IntentDescription("Restart the current interval from the beginning.", categoryName: "Controls")
    static let openAppWhenRun = false

    @AppDependency private var coordinator: SessionCoordinator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Bind the actions value to a local so its lifetime spans the call. Restart is the
        // one control that transitively starts the heartbeat (`Task { [weak self] }` over the
        // coordinator); binding here avoids a spurious Release-optimizer "weak reference will
        // always be nil" diagnostic from inlining the temporary through that path (M17).
        let actions = AppIntentSessionActions(coordinator: coordinator)
        try actions.restart()
        return .result(dialog: IntentDialog("\(AppIntentDialogText.restarted)"))
    }
}

/// Stop the session (preserving history — never a delete).
struct StopTimeFrameIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Time Frame"
    static let description = IntentDescription("Stop the current Time Frame session.", categoryName: "Controls")
    static let openAppWhenRun = false

    @AppDependency private var coordinator: SessionCoordinator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AppIntentSessionActions(coordinator: coordinator).stop()
        return .result(dialog: IntentDialog("\(AppIntentDialogText.stopped)"))
    }
}
