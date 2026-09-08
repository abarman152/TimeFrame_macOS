//
//  SessionSetupPrefill.swift
//  time_frame
//
//  A small value that pre-fills the session-setup screen when a run is started
//  from a Task Template. It carries only the *starting* values; the setup screen
//  copies them into its editable fields, so any per-run change the user makes
//  never flows back to the template (ADR-023/025).
//

import Foundation

/// Starting values handed to `SessionSetupView` when a session is launched from a
/// `TaskTemplate`.
///
/// This is the seam that keeps a single session-start path: the template does not
/// create a `FocusSession` itself. It fills the setup screen, the user may adjust
/// per-run options, and Start goes through the existing
/// `SessionCoordinator.startSession` (ADR-025).
nonisolated struct SessionSetupPrefill: Equatable, Sendable, Identifiable {
    let id = UUID()

    /// The task name to pre-fill (the template's `taskName`, not its `name`).
    var taskName: String

    /// The configuration to pre-select. `nil` when the template has lost its
    /// configuration — the setup screen then falls back to its own default.
    var configurationID: UUID?

    /// The focus-session count to pre-fill (the template's `defaultTotalSessions`).
    var totalSessions: Int

    /// Builds a prefill from a template, reading the template's *values* only.
    init(template: TaskTemplate) {
        self.taskName = template.taskName
        self.configurationID = template.configuration?.id
        self.totalSessions = template.defaultTotalSessions
    }
}
