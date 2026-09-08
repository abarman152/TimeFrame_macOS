//
//  CurrentSessionEntity.swift
//  time_frame (Milestone 12)
//
//  A read-only App Intents view of the ONE live session, so a Shortcut can read individual
//  fields ("get the remaining time", "get the current task"). It is a projection of
//  authoritative state (built from `AppIntentSessionState`), never a mutable handle on the
//  timer — it exposes no control and holds no engine internals (ADR-058). There is at most
//  one, addressed by a fixed identifier.
//

import Foundation
import AppIntents

/// The current Time Frame session, as read-only App Intents data.
///
/// Fields are `@Property`-exposed so Shortcuts can pipe them into later actions. Every value
/// is a frozen snapshot taken when the entity was resolved; nothing here can change the
/// timer. Absent (query returns empty) when no session is active.
struct CurrentSessionEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Current Session")

    static let defaultQuery = CurrentSessionEntityQuery()

    /// The single, stable identifier for "the current session" (there is only ever one).
    static let currentID = "current"

    let id: String

    @Property(title: "Task")
    var task: String

    @Property(title: "Phase")
    var phase: String

    @Property(title: "State")
    var state: String

    @Property(title: "Remaining")
    var remaining: String

    @Property(title: "Remaining Minutes")
    var remainingMinutes: Int

    @Property(title: "Session Number")
    var sessionNumber: Int

    @Property(title: "Total Sessions")
    var totalSessions: Int

    @Property(title: "Configuration")
    var configurationName: String

    @Property(title: "Next Phase")
    var nextPhase: String

    var displayRepresentation: DisplayRepresentation {
        let title = task.isEmpty ? "Current Session" : task
        return DisplayRepresentation(title: "\(title)", subtitle: "\(phase) · \(remaining) left")
    }

    /// Builds the entity from the pure session projection. Nonisolated: the projection is a
    /// plain value, so no model or engine access happens here.
    init(state projection: AppIntentSessionState) {
        self.id = CurrentSessionEntity.currentID
        self.task = projection.taskName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.phase = projection.phase.map(AppIntentDialogText.phaseTitle) ?? "—"
        self.state = CurrentSessionEntity.stateLabel(projection.situation)
        self.remaining = TimeFormatting.clock(projection.remaining)
        self.remainingMinutes = Int((max(0, projection.remaining) / 60).rounded())
        self.sessionNumber = projection.sessionIndex ?? 0
        self.totalSessions = projection.totalSessions ?? 0
        self.configurationName = projection.configurationName ?? ""
        self.nextPhase = projection.nextPhase.map(AppIntentDialogText.phaseTitle) ?? "—"
    }

    private static func stateLabel(_ situation: AppIntentSessionState.Situation) -> String {
        switch situation {
        case .idle: return "Idle"
        case .running: return "Running"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .interrupted: return "Interrupted"
        }
    }
}

/// Resolves the single current-session entity from the authoritative coordinator. Returns an
/// empty array when no session is active, so a Shortcut degrades gracefully. Read-only.
struct CurrentSessionEntityQuery: EntityQuery {
    @AppDependency private var coordinator: SessionCoordinator

    func entities(for identifiers: [String]) async throws -> [CurrentSessionEntity] {
        // Only the fixed "current" id ever resolves, and only while a session exists.
        guard identifiers.contains(CurrentSessionEntity.currentID) else { return [] }
        let session = coordinator
        return await MainActor.run { Self.resolve(coordinator: session) }
    }

    func suggestedEntities() async throws -> [CurrentSessionEntity] {
        let session = coordinator
        return await MainActor.run { Self.resolve(coordinator: session) }
    }

    /// Testable core: builds the current-session entity (or none) from a coordinator.
    @MainActor
    static func resolve(coordinator: SessionCoordinator) -> [CurrentSessionEntity] {
        let projection = AppIntentSessionState(coordinator: coordinator)
        guard projection.hasSession else { return [] }
        return [CurrentSessionEntity(state: projection)]
    }
}
