//
//  TaskTemplate.swift
//  time_frame
//
//  A persisted, reusable task definition: a name, the task to focus on, a
//  referenced Pomodoro configuration, and a default focus-session count.
//

import Foundation
import SwiftData

/// A reusable starting point for future focus sessions.
///
/// A template combines a *task definition* (its `taskName`) with a referenced
/// `PomodoroConfiguration` and a default focus-session count, so a recurring kind
/// of work can be configured once and started repeatedly. A template is **not** a
/// `FocusSession` and **not** a historical record: starting a session copies the
/// template's values into a `SessionSetupDraft` and hands them to the existing
/// `SessionCoordinator.startSession`, and the running session is thereafter
/// independent of the template (editing or deleting the template never touches it
/// — ADR-023/024). See `docs/13-TASK-TEMPLATES.md`.
@Model
final class TaskTemplate {
    /// Stable identity. No `#Unique` constraint: CloudKit mirroring does not
    /// support unique constraints (ADR-061). The repository only ever mints fresh
    /// `UUID`s, so identity stays effectively unique.
    private(set) var id: UUID = UUID()

    /// The template's own name — how the *reusable template* is identified in the
    /// Templates list (e.g. "Research"). Deliberately distinct from `taskName`.
    var name: String = ""

    /// The task the started session will focus on (e.g. "Research Quantum IDS").
    /// This is what gets copied into the `FocusSession`; it is not the template's
    /// name.
    var taskName: String = ""

    /// The configuration this template starts sessions from. A reference, not a
    /// copy: editing the configuration changes what *future* sessions use, while
    /// already-started sessions keep their frozen plan (ADR-022). Optional so a
    /// template survives deletion of its configuration — the reference nullifies
    /// and the template is shown as "needs a configuration" rather than being
    /// deleted (ADR-024).
    var configuration: PomodoroConfiguration?

    /// The default number of focus sessions a run started from this template uses.
    /// Copied into the per-run `SessionSetupDraft`, where the user may override it
    /// for that run only — the template's value is never mutated by an override.
    var defaultTotalSessions: Int = 4

    /// Whether this is the user's default template. At most one template should
    /// have this set; the `TaskTemplateRepository` enforces that invariant when
    /// changing the default (ADR-025).
    var isDefault: Bool = false

    /// The template's icon, stored as the **stable catalog identifier** of a
    /// `TimeFrameIconIdentifier` — never an SF Symbol name and never free text
    /// (ADR-103). Read it through `icon`, which resolves an unknown or empty value
    /// to the catalog default rather than handing stored data to `Image(systemName:)`.
    /// Defaulted (not optional) so the attribute is CloudKit-legal and every existing
    /// row migrates with a sensible icon.
    var iconIdentifier: String = TimeFrameIconIdentifier.templateDefault.rawValue

    /// Whether the user pinned this template to Quick Start (ADR-104). Pinning is a
    /// property of the template itself, keyed by its stable `id`, so renaming keeps the
    /// pin and deleting the template removes it from Quick Start with no orphan state.
    var isPinned: Bool = false

    /// When the template was pinned, used to order Quick Start oldest-pin-first.
    /// Optional (CloudKit-legal); `nil` whenever `isPinned` is false.
    var pinnedAt: Date?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        name: String,
        taskName: String,
        configuration: PomodoroConfiguration? = nil,
        defaultTotalSessions: Int = 4,
        isDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.taskName = taskName
        self.configuration = configuration
        self.defaultTotalSessions = defaultTotalSessions
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// Whether the template can start a session: it still references a
    /// configuration. A template whose configuration was deleted is *incomplete*
    /// and must have a configuration chosen before it can run (ADR-024).
    var hasConfiguration: Bool { configuration != nil }

    /// The configuration name to show for this template, or a neutral
    /// "Configuration unavailable" when the reference was nullified.
    var displayConfigurationName: String {
        configuration?.name ?? "Configuration unavailable"
    }

    /// The template's icon, resolved through the one catalog. An unrecognised stored
    /// identifier falls back to the template default, so a corrupt or newer-build value
    /// still renders (ADR-103).
    var icon: TimeFrameIconIdentifier {
        TimeFrameIconIdentifier.resolve(iconIdentifier, fallback: .templateDefault)
    }
}
