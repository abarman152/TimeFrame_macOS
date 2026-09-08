//
//  ConfigurationEntity.swift
//  time_frame (Milestone 12)
//
//  The App Intents representation of a persisted `PomodoroConfiguration`, so "Start Time
//  Frame" can take a named rhythm as its configuration parameter (ADR-057). Immutable value,
//  stable UUID id, frozen display strings; resolved through the existing
//  `ConfigurationRepository`.
//

import Foundation
import AppIntents

/// A selectable Pomodoro configuration for App Intents / Shortcuts.
struct ConfigurationEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Configuration")

    static let defaultQuery = ConfigurationEntityQuery()

    /// Stable identity — the configuration's `UUID`.
    let id: UUID
    /// The configuration's name, e.g. "Deep Work".
    let name: String
    /// Focus-interval length in seconds (for a meaningful subtitle).
    let focusDuration: TimeInterval
    /// Default number of focus sessions.
    let defaultTotalSessions: Int

    var displayRepresentation: DisplayRepresentation {
        let subtitle = "\(TimeFormatting.minutesLabel(focusDuration)) focus · \(defaultTotalSessions) sessions"
        return DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }

    @MainActor
    init(_ configuration: PomodoroConfiguration) {
        self.id = configuration.id
        self.name = configuration.name
        self.focusDuration = configuration.focusDuration
        self.defaultTotalSessions = configuration.defaultTotalSessions
    }
}

/// Resolves `ConfigurationEntity` values from the persisted store through the existing
/// repository (ADR-057). Nonisolated `init()`; async methods hop to the main actor.
struct ConfigurationEntityQuery: EntityStringQuery {
    @AppDependency private var data: IntentDataProvider

    func entities(for identifiers: [UUID]) async throws -> [ConfigurationEntity] {
        let provider = data
        return try await MainActor.run { try Self.resolve(identifiers, in: provider.configurations) }
    }

    func suggestedEntities() async throws -> [ConfigurationEntity] {
        let provider = data
        return try await MainActor.run { try Self.suggested(in: provider.configurations) }
    }

    func entities(matching string: String) async throws -> [ConfigurationEntity] {
        let provider = data
        return try await MainActor.run { try Self.matching(string, in: provider.configurations) }
    }

    // MARK: Testable resolution cores

    @MainActor
    static func resolve(_ identifiers: [UUID], in repository: ConfigurationRepository) throws -> [ConfigurationEntity] {
        try identifiers.compactMap { id in
            try repository.configuration(with: id).map(ConfigurationEntity.init)
        }
    }

    @MainActor
    static func suggested(in repository: ConfigurationRepository) throws -> [ConfigurationEntity] {
        try repository.all().map(ConfigurationEntity.init)
    }

    @MainActor
    static func matching(_ string: String, in repository: ConfigurationRepository) throws -> [ConfigurationEntity] {
        let needle = string.lowercased()
        return try repository.all()
            .filter { $0.name.lowercased().contains(needle) }
            .map(ConfigurationEntity.init)
    }
}
