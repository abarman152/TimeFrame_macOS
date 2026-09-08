//
//  SessionSetupDraft.swift
//  time_frame
//
//  The user's choices when starting a run: task name and how many focus
//  sessions. A pure value so the setup logic (task required, count override,
//  plan generation) is testable without the UI.
//

import Foundation

/// The inputs collected on the Timer setup screen before a run starts.
///
/// This is *not* timer state — it is transient setup input. Starting a run hands
/// these values to `SessionCoordinator.startSession`, which builds the persisted
/// `FocusSession`. The saved `PomodoroConfiguration` is never mutated by a count
/// override (requirement of Milestone 3): the override rides along here and is
/// applied to a value snapshot only.
nonisolated struct SessionSetupDraft: Equatable, Sendable {
    /// The task the user is focusing on. Required (non-empty after trimming).
    var taskName: String = ""

    /// The number of focus sessions for this run. Overrides the configuration's
    /// default for this run only.
    var totalSessions: Int = 4

    /// The task name with surrounding whitespace removed — what actually gets
    /// persisted.
    var trimmedTaskName: String {
        taskName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the draft may start a run: a non-empty task name.
    var isValid: Bool { !trimmedTaskName.isEmpty }

    /// The interval plan this draft would produce for a given configuration,
    /// applying the session-count override. Used for the pre-start preview and
    /// mirrors exactly what the coordinator will run.
    func plan(for configuration: PomodoroConfigurationSnapshot) -> IntervalPlan {
        IntervalPlan(configuration: configuration.overriding(totalSessions: totalSessions))
    }
}
