//
//  SessionPlanGenerator.swift
//  time_frame
//
//  Deterministic generation of an initial plan (a list of `PlanItemDraft`s) from a
//  configuration. Pure value logic — no SwiftUI, no SwiftData — so "same input →
//  same plan" is trivially testable. This is the planning-layer counterpart to the
//  engine's `SessionPlan`; unlike the engine plan it makes the trailing break
//  optional (the planner never forces a break after the final focus — ADR-026).
//

import Foundation

/// Builds an initial `SessionPlan` timeline from a configuration.
///
/// For a configuration with N focus sessions and a long-break interval of L, the
/// generated timeline is:
///
///     focus, break, focus, break, … , focus[, break]
///
/// where the break after focus number *k* is a long break when `k % L == 0` and a
/// short break otherwise. The break after the **final** focus is included only when
/// `includeFinalBreak` is true; by default it is omitted, so a plan ends on focus
/// (important for eventual Calendar integration — ADR-026). Every focus item
/// carries the source configuration's identity and name so a multi-configuration
/// plan preserves per-focus configuration (ADR-030).
nonisolated enum SessionPlanGenerator {

    /// Generates the ordered plan items for one configuration.
    ///
    /// - Parameters:
    ///   - configuration: the validated snapshot providing durations and the
    ///     long-break interval.
    ///   - configurationID: the source configuration's stable id, frozen onto each
    ///     focus item so execution and display know which configuration it used.
    ///   - configurationName: the source configuration's name, frozen for display.
    ///   - sessions: the number of focus intervals to generate (clamped to ≥ 1).
    ///   - includeFinalBreak: whether to append a break after the last focus.
    static func generate(
        from configuration: PomodoroConfigurationSnapshot,
        configurationID: UUID,
        configurationName: String,
        sessions: Int,
        includeFinalBreak: Bool = false
    ) -> [PlanItemDraft] {
        var items: [PlanItemDraft] = []
        var order = 0

        let totalSessions = max(1, sessions)
        let longBreakInterval = max(1, configuration.sessionsBeforeLongBreak)

        for focusNumber in 1...totalSessions {
            items.append(
                PlanItemDraft(
                    order: order,
                    phase: .focus,
                    duration: configuration.focusDuration,
                    configurationID: configurationID,
                    configurationName: configurationName
                )
            )
            order += 1

            let isLast = focusNumber == totalSessions
            guard !isLast || includeFinalBreak else { continue }

            let isLongBreak = focusNumber % longBreakInterval == 0
            items.append(
                PlanItemDraft(
                    order: order,
                    phase: isLongBreak ? .longBreak : .shortBreak,
                    duration: isLongBreak
                        ? configuration.longBreakDuration
                        : configuration.shortBreakDuration
                )
            )
            order += 1
        }

        return items
    }
}
