//
//  PomodoroConfiguration.swift
//  time_frame
//
//  Persisted, reusable definition of a Pomodoro rhythm (durations + counts).
//

import Foundation
import SwiftData

/// A named, reusable Pomodoro configuration.
///
/// A configuration is the single source of truth for a rhythm's durations and
/// counts. Sessions (and, in a later milestone, task templates) *reference* a
/// configuration rather than copying its values, so editing a configuration in
/// one place stays consistent. See `docs/02-DATA-MODEL.md`.
@Model
final class PomodoroConfiguration {
    /// Stable identity. Assigned once at creation and never reused. The store no
    /// longer declares a `#Unique` constraint on it: CloudKit mirroring does not
    /// support unique constraints, and declaring one breaks the local store too
    /// once CloudKit is enabled (Milestone 13 / ADR-061). The repositories only
    /// ever create fresh `UUID`s, so identity stays effectively unique without the
    /// database-level constraint.
    private(set) var id: UUID = UUID()

    /// Human-readable name, e.g. "Classic Pomodoro" or "Deep Work".
    var name: String = ""

    /// Focus interval length in seconds.
    var focusDuration: TimeInterval = 25 * 60

    /// Short break length in seconds.
    var shortBreakDuration: TimeInterval = 5 * 60

    /// Long break length in seconds.
    var longBreakDuration: TimeInterval = 15 * 60

    /// Number of focus sessions between long breaks (the long-break interval).
    var sessionsBeforeLongBreak: Int = 4

    /// Default number of focus sessions in a run started from this config.
    var defaultTotalSessions: Int = 4

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    /// Whether this is the user's default configuration. At most one
    /// configuration should have this set; the `ConfigurationRepository` enforces
    /// that invariant when changing the default. See ADR-015.
    var isDefault: Bool = false

    /// Sessions that reference this configuration. The inverse is declared here
    /// (on one side only); deleting a configuration nullifies the reference on
    /// its sessions rather than deleting historical sessions.
    @Relationship(deleteRule: .nullify, inverse: \FocusSession.configuration)
    var focusSessions: [FocusSession] = []

    /// Task templates that reference this configuration. Like `focusSessions`,
    /// the inverse is declared here (one side only) with a **nullify** delete
    /// rule: deleting a configuration leaves its templates intact but clears their
    /// reference, so they are shown as needing a new configuration rather than
    /// being deleted (ADR-024). Also lets the delete confirmation report how many
    /// templates a configuration is used by.
    @Relationship(deleteRule: .nullify, inverse: \TaskTemplate.configuration)
    var taskTemplates: [TaskTemplate] = []

    /// Session-plan items (focus intervals) that reference this configuration. Like
    /// `focusSessions`/`taskTemplates`, the inverse is declared here (one side only)
    /// with a **nullify** delete rule: deleting a configuration leaves the plan and
    /// its items intact but clears the reference, so the plan is shown as needing a
    /// configuration rather than being deleted (ADR-029). Also lets the delete
    /// confirmation report how many plans a configuration is used by.
    @Relationship(deleteRule: .nullify, inverse: \SessionPlanItem.configuration)
    var planItems: [SessionPlanItem] = []

    init(
        name: String,
        focusDuration: TimeInterval = 25 * 60,
        shortBreakDuration: TimeInterval = 5 * 60,
        longBreakDuration: TimeInterval = 15 * 60,
        sessionsBeforeLongBreak: Int = 4,
        defaultTotalSessions: Int = 4,
        isDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.focusDuration = focusDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.sessionsBeforeLongBreak = sessionsBeforeLongBreak
        self.defaultTotalSessions = defaultTotalSessions
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.modifiedAt = createdAt
    }

    /// An immutable value snapshot the timer engine can run from without
    /// depending on SwiftData.
    var snapshot: PomodoroConfigurationSnapshot {
        PomodoroConfigurationSnapshot(
            focusDuration: focusDuration,
            shortBreakDuration: shortBreakDuration,
            longBreakDuration: longBreakDuration,
            sessionsBeforeLongBreak: sessionsBeforeLongBreak,
            totalSessions: defaultTotalSessions
        )
    }
}

extension PomodoroConfiguration {
    /// A conventional starter configuration seeded on first launch.
    static func classic() -> PomodoroConfiguration {
        PomodoroConfiguration(
            name: "Classic Pomodoro",
            focusDuration: 25 * 60,
            shortBreakDuration: 5 * 60,
            longBreakDuration: 15 * 60,
            sessionsBeforeLongBreak: 4,
            defaultTotalSessions: 4
        )
    }
}
