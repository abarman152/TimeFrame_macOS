//
//  StartTemplateIntent.swift
//  time_frame (Milestone 12)
//
//  "Start Template" — begins a session from one of the user's saved `TaskTemplate`s. It
//  resolves the selected template, builds the existing `SessionSetupPrefill`, and routes
//  through `SessionCoordinator.startSession` — the exact chain the Templates UI uses
//  (ADR-056). There is no second template-execution path.
//

import Foundation
import AppIntents

struct StartTemplateIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Template"

    static let description = IntentDescription(
        "Start a focus session from one of your Time Frame templates.",
        categoryName: "Focusing"
    )

    static let openAppWhenRun = false

    @Parameter(title: "Template")
    var template: TaskTemplateEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Start the \(\.$template) template")
    }

    @AppDependency private var coordinator: SessionCoordinator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try AppIntentSessionActions(coordinator: coordinator)
            .startTemplate(id: template.id)
        let text = AppIntentDialogText.started(
            task: outcome.taskName,
            configurationName: outcome.configurationName,
            sessionCount: outcome.sessionCount
        )
        return .result(dialog: IntentDialog("\(text)"))
    }
}
