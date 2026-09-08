//
//  StartPlanIntent.swift
//  time_frame (Milestone 12)
//
//  "Start Plan" — begins a session from one of the user's saved `SessionPlan`s. It resolves
//  the selected plan and hands its frozen `executionSnapshot` to the existing
//  `SessionCoordinator.startPlan` (ADR-056). All plan validation, snapshotting, interval
//  generation, persistence, and the timer start remain in the existing services — this intent
//  duplicates none of them.
//

import Foundation
import AppIntents

struct StartPlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Plan"

    static let description = IntentDescription(
        "Start a focus session from one of your Time Frame session plans.",
        categoryName: "Focusing"
    )

    static let openAppWhenRun = false

    @Parameter(title: "Plan")
    var plan: SessionPlanEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Start the \(\.$plan) plan")
    }

    @AppDependency private var coordinator: SessionCoordinator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try AppIntentSessionActions(coordinator: coordinator)
            .startPlan(id: plan.id)
        let text = AppIntentDialogText.startedPlan(
            task: outcome.taskName,
            planName: outcome.planName ?? outcome.configurationName
        )
        return .result(dialog: IntentDialog("\(text)"))
    }
}
