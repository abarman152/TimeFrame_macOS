//
//  GetCurrentTimeFrameStatusIntent.swift
//  time_frame (Milestone 12)
//
//  "What's my Time Frame status?" — a read-only query that speaks a natural-language summary
//  derived entirely from the authoritative coordinator/engine via the pure
//  `AppIntentSessionState` projection (ADR-058). It maintains no countdown of its own; it
//  reads a frozen snapshot and phrases it.
//

import Foundation
import AppIntents

struct GetCurrentTimeFrameStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Time Frame Status"

    static let description = IntentDescription(
        "Ask what Time Frame is doing right now — your task, session number, and time remaining.",
        categoryName: "Status"
    )

    // A pure query; no need to bring the window forward.
    static let openAppWhenRun = false

    @AppDependency private var coordinator: SessionCoordinator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = AppIntentSessionActions(coordinator: coordinator).status()
        let text = AppIntentDialogText.status(state)
        return .result(dialog: IntentDialog("\(text)"))
    }
}
