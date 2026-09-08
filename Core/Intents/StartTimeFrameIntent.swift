//
//  StartTimeFrameIntent.swift
//  time_frame (Milestone 12)
//
//  "Start Time Frame" — begins a new focus session through the existing setup/start
//  architecture. It never creates a `FocusSession` or touches SwiftData directly; it resolves
//  a configuration (the chosen one, or the user's default) and routes through
//  `SessionCoordinator.startSession` (ADR-056). The timer then runs independently — this
//  intent introduces no clock, countdown, or timer of its own.
//

import Foundation
import AppIntents

struct StartTimeFrameIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Time Frame"

    static let description = IntentDescription(
        "Start a new focus session, optionally choosing a task, a configuration, and how many focus sessions to run.",
        categoryName: "Focusing"
    )

    // Starting a session does not require bringing the window forward; the session runs in
    // the background and the menu bar / widgets reflect it. Keep it a quiet, fast command.
    static let openAppWhenRun = false

    @Parameter(title: "Task")
    var taskName: String?

    @Parameter(title: "Configuration")
    var configuration: ConfigurationEntity?

    @Parameter(title: "Focus Sessions")
    var sessionCount: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Start Time Frame using \(\.$configuration) on \(\.$taskName) for \(\.$sessionCount) sessions")
    }

    @AppDependency private var coordinator: SessionCoordinator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try AppIntentSessionActions(coordinator: coordinator).startSession(
            configurationID: configuration?.id,
            taskName: taskName,
            totalSessions: sessionCount
        )
        let text = AppIntentDialogText.started(
            task: outcome.taskName,
            configurationName: outcome.configurationName,
            sessionCount: outcome.sessionCount
        )
        return .result(dialog: IntentDialog("\(text)"))
    }
}
