//
//  SessionPlanValidation.swift
//  time_frame
//
//  Validation rules, limits, and the value-typed drafts for a Session Plan and its
//  items. A dedicated, pure validation layer so the same rules apply to create and
//  update and are testable without the UI (mirrors ConfigurationValidation /
//  TaskTemplateValidation). See docs/14-SESSION-PLANNER.md.
//

import Foundation

/// The accepted bounds for a `SessionPlan`.
///
/// Deliberately generous but finite so a typo (an interval of millions of seconds,
/// or thousands of items) is rejected rather than producing an unusable or
/// unschedulable plan. The per-interval maximum is shared with configuration
/// validation so a plan can never carry an interval the timer could not run.
/// See ADR-026.
nonisolated enum PlanLimits {
    /// The largest number of items a single plan may contain.
    static let maxItems = 100
    /// The largest any single interval may be: 8 hours (shared with configuration
    /// validation).
    static let maxItemDuration: TimeInterval = ConfigurationLimits.maxDuration
    /// The largest total duration a whole plan may sum to: 24 hours.
    static let maxTotalDuration: TimeInterval = 24 * 60 * 60
}

/// A single validation failure for a session plan, with a human-readable reason.
/// `nonisolated`/`Sendable`/`Equatable` so it can travel inside a
/// `PersistenceError` and be asserted in tests.
nonisolated enum SessionPlanValidationError: Error, Equatable, Sendable, Hashable {
    case emptyName
    case emptyTaskName
    case noFocusItems
    case focusMissingConfiguration
    case invalidItemDuration
    case tooManyItems
    case totalDurationTooLong

    /// A short, user-facing explanation.
    var message: String {
        switch self {
        case .emptyName:
            return "The plan needs a name."
        case .emptyTaskName:
            return "The plan needs a task."
        case .noFocusItems:
            return "A plan must contain at least one focus interval."
        case .focusMissingConfiguration:
            return "Every focus interval must have a configuration."
        case .invalidItemDuration:
            return "Every interval must be between 1 second and 8 hours long."
        case .tooManyItems:
            return "A plan can have at most \(PlanLimits.maxItems) intervals."
        case .totalDurationTooLong:
            return "A plan can't be longer than 24 hours in total."
        }
    }
}

/// The proposed values for one interval in a plan.
///
/// A plain `Sendable`/`Identifiable` value so the editor can hold and reorder
/// items without touching SwiftData, and so validation/generation stay pure. A
/// focus item carries its configuration by **id** (not the SwiftData model) plus a
/// frozen `configurationName` for display; a break carries neither. `duration` is
/// this item's own value — seeded from a configuration but independently editable,
/// so editing the underlying configuration never changes a saved plan item.
nonisolated struct PlanItemDraft: Equatable, Sendable, Identifiable {
    var id: UUID
    /// Position in the plan (0-based). Reassigned by `SessionPlanDraft.normalized`.
    var order: Int
    /// The kind of interval. `TimerPhase` is the shared domain enum used by the
    /// engine, the generated plan, and the persisted `SessionInterval` (ADR-027).
    var phase: TimerPhase
    /// This interval's planned length in seconds.
    var duration: TimeInterval
    /// The configuration a *focus* item uses, carried by id. `nil` for breaks and
    /// for a focus item whose configuration was deleted.
    var configurationID: UUID?
    /// The configuration name frozen for display, so a focus item still shows a
    /// meaningful label after its configuration is deleted (ADR-019 principle).
    var configurationName: String

    init(
        id: UUID = UUID(),
        order: Int = 0,
        phase: TimerPhase,
        duration: TimeInterval,
        configurationID: UUID? = nil,
        configurationName: String = ""
    ) {
        self.id = id
        self.order = order
        self.phase = phase
        self.duration = duration
        self.configurationID = configurationID
        self.configurationName = configurationName
    }

    /// Whether this is a focus interval.
    var isFocus: Bool { phase == .focus }
}

/// The proposed values for creating or updating a `SessionPlan`.
///
/// Kept as a plain value so validation is a pure function (trivially testable) and
/// the same rules apply to create and update. Invalid input is **never silently
/// modified** — `validate()` reports every violated rule so the caller can surface
/// them. Ordering is derived from array position via `normalized`, never left to
/// chance.
nonisolated struct SessionPlanDraft: Equatable, Sendable {
    var name: String
    var taskName: String
    var items: [PlanItemDraft]
    /// The chosen icon. Typed, so an arbitrary SF Symbol string can never enter the
    /// draft — the editor picks a catalog member and the repository persists its stable
    /// identifier (ADR-103).
    var icon: TimeFrameIconIdentifier

    init(
        name: String = "",
        taskName: String = "",
        items: [PlanItemDraft] = [],
        icon: TimeFrameIconIdentifier = .planDefault
    ) {
        self.name = name
        self.taskName = taskName
        self.items = items
        self.icon = icon
    }

    /// The plan name with surrounding whitespace removed — what gets persisted.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The task name with surrounding whitespace removed — what gets persisted.
    var trimmedTaskName: String {
        taskName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A copy whose items carry a contiguous `order` matching their array position,
    /// so persisted ordering is deterministic and never has duplicates or gaps.
    var normalized: SessionPlanDraft {
        var copy = self
        for index in copy.items.indices {
            copy.items[index].order = index
        }
        return copy
    }

    /// The number of focus intervals in the plan.
    var focusCount: Int { items.filter(\.isFocus).count }

    /// The sum of every interval's duration in seconds. Pure planner arithmetic —
    /// never derived from the timer engine (ADR-028).
    var totalDuration: TimeInterval {
        items.reduce(0) { $0 + $1.duration }
    }

    /// Every rule this draft violates, in a stable order. Empty means valid.
    func validate() -> [SessionPlanValidationError] {
        var errors: [SessionPlanValidationError] = []

        if trimmedName.isEmpty { errors.append(.emptyName) }
        if trimmedTaskName.isEmpty { errors.append(.emptyTaskName) }
        if focusCount == 0 { errors.append(.noFocusItems) }

        if items.contains(where: { $0.isFocus && $0.configurationID == nil }) {
            errors.append(.focusMissingConfiguration)
        }

        if items.contains(where: {
            !($0.duration > 0) || $0.duration > PlanLimits.maxItemDuration
        }) {
            errors.append(.invalidItemDuration)
        }

        if items.count > PlanLimits.maxItems { errors.append(.tooManyItems) }
        if totalDuration > PlanLimits.maxTotalDuration { errors.append(.totalDurationTooLong) }

        return errors
    }

    /// Throws `PersistenceError.invalidPlan` if any rule is violated.
    func validated() throws {
        let errors = validate()
        guard errors.isEmpty else {
            throw PersistenceError.invalidPlan(errors)
        }
    }
}
