//
//  SessionPlanEntity.swift
//  time_frame (Milestone 12)
//
//  The App Intents representation of a persisted `SessionPlan`, so Shortcuts/Siri can offer
//  the user's real plans as a parameter for "Start Plan" (ADR-057). Immutable value, stable
//  UUID id, frozen display strings; resolved through the existing `SessionPlanRepository`.
//

import Foundation
import AppIntents

/// A selectable session plan for App Intents / Shortcuts.
struct SessionPlanEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Session Plan")

    static let defaultQuery = SessionPlanEntityQuery()

    /// Stable identity — the plan's `UUID`.
    let id: UUID
    /// The plan's own name, e.g. "Morning Deep Work".
    let name: String
    /// The task the plan is about, e.g. "Research Paper".
    let taskName: String
    /// The number of focus intervals in the plan (for a meaningful subtitle).
    let focusCount: Int

    var displayRepresentation: DisplayRepresentation {
        let sessions = "\(focusCount) focus session\(focusCount == 1 ? "" : "s")"
        let subtitle = taskName.isEmpty ? sessions : "\(taskName) · \(sessions)"
        return DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }

    @MainActor
    init(_ plan: SessionPlan) {
        self.id = plan.id
        self.name = plan.name
        self.taskName = plan.taskName
        self.focusCount = plan.focusCount
    }
}

/// Resolves `SessionPlanEntity` values from the persisted store through the existing
/// repository (ADR-057). Nonisolated `init()`; async methods hop to the main actor.
struct SessionPlanEntityQuery: EntityStringQuery {
    @AppDependency private var data: IntentDataProvider

    func entities(for identifiers: [UUID]) async throws -> [SessionPlanEntity] {
        let provider = data
        return try await MainActor.run { try Self.resolve(identifiers, in: provider.plans) }
    }

    func suggestedEntities() async throws -> [SessionPlanEntity] {
        let provider = data
        return try await MainActor.run { try Self.suggested(in: provider.plans) }
    }

    func entities(matching string: String) async throws -> [SessionPlanEntity] {
        let provider = data
        return try await MainActor.run { try Self.matching(string, in: provider.plans) }
    }

    // MARK: Testable resolution cores

    @MainActor
    static func resolve(_ identifiers: [UUID], in repository: SessionPlanRepository) throws -> [SessionPlanEntity] {
        try identifiers.compactMap { id in
            try repository.plan(with: id).map(SessionPlanEntity.init)
        }
    }

    @MainActor
    static func suggested(in repository: SessionPlanRepository) throws -> [SessionPlanEntity] {
        try repository.all().map(SessionPlanEntity.init)
    }

    @MainActor
    static func matching(_ string: String, in repository: SessionPlanRepository) throws -> [SessionPlanEntity] {
        let needle = string.lowercased()
        return try repository.all()
            .filter { $0.name.lowercased().contains(needle) || $0.taskName.lowercased().contains(needle) }
            .map(SessionPlanEntity.init)
    }
}
