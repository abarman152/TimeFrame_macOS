//
//  SessionPlan.swift
//  time_frame
//
//  A persisted, reusable multi-session Pomodoro plan: a named, ordered sequence of
//  focus and break intervals the user designs before execution. A plan is what the
//  user *intends* to run; starting it freezes a value snapshot and hands that to
//  the existing session engine, producing an independent FocusSession (ADR-026/028).
//  See docs/14-SESSION-PLANNER.md.
//

import Foundation
import SwiftData

/// A designed, editable sequence of intervals for a longer focus block.
///
/// A `SessionPlan` is a **planning** entity, not an execution entity (ADR-026): it
/// is never run directly and never holds timer state. It owns its ordered
/// `SessionPlanItem`s (cascade delete) and, through the items, may reference more
/// than one `PomodoroConfiguration` — a plan can mix, say, a "Research" focus and a
/// "Writing" focus (ADR-030). Editing or deleting a plan never affects a session
/// already started from it, nor any historical session (ADR-029).
@Model
final class SessionPlan {
    /// Stable identity. No `#Unique` constraint: CloudKit mirroring does not
    /// support unique constraints (ADR-061). The repository only ever mints fresh
    /// `UUID`s, so identity stays effectively unique.
    private(set) var id: UUID = UUID()

    /// The plan's own name — how it appears in the Plans list (e.g. "Research Deep
    /// Work"). Distinct from `taskName`.
    var name: String = ""

    /// The task the plan is about — copied into the `FocusSession` when started.
    var taskName: String = ""

    var createdAt: Date = Date()

    /// Bumped whenever the plan is saved/edited. Drives the "Updated …" summary and
    /// the newest-first ordering in the list.
    var updatedAt: Date = Date()

    /// The plan's icon, stored as the **stable catalog identifier** of a
    /// `TimeFrameIconIdentifier` — never an SF Symbol name and never free text
    /// (ADR-103). Read it through `icon`. Defaulted (not optional) so the attribute is
    /// CloudKit-legal and every existing row migrates with a sensible icon.
    var iconIdentifier: String = TimeFrameIconIdentifier.planDefault.rawValue

    /// Whether the user pinned this plan to Quick Start (ADR-104). Keyed by the plan's
    /// stable `id`: renaming keeps the pin, deleting removes it from Quick Start.
    var isPinned: Bool = false

    /// When the plan was pinned, used to order Quick Start oldest-pin-first. Optional
    /// (CloudKit-legal); `nil` whenever `isPinned` is false.
    var pinnedAt: Date?

    /// The ordered intervals that make up the plan. Owned by the plan: deleting the
    /// plan cascades to its items (but never to the configurations they reference,
    /// nor to any FocusSession — ADR-029).
    @Relationship(deleteRule: .cascade, inverse: \SessionPlanItem.plan)
    var items: [SessionPlanItem] = []

    init(
        name: String,
        taskName: String,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.taskName = taskName
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// The items in planned order.
    var orderedItems: [SessionPlanItem] {
        items.sorted { $0.order < $1.order }
    }

    /// The plan's icon, resolved through the one catalog. An unrecognised stored
    /// identifier falls back to the plan default (ADR-103).
    var icon: TimeFrameIconIdentifier {
        TimeFrameIconIdentifier.resolve(iconIdentifier, fallback: .planDefault)
    }

    /// The number of focus intervals in the plan.
    var focusCount: Int {
        items.filter { $0.phase == .focus }.count
    }

    /// The total planned duration in seconds (pure arithmetic over the items;
    /// never derived from the timer engine — ADR-028).
    var totalDuration: TimeInterval {
        items.reduce(0) { $0 + $1.duration }
    }

    /// Whether every focus item still references a configuration. A plan whose
    /// configuration was deleted becomes *incomplete* and cannot start until it is
    /// re-assigned (mirrors a template losing its configuration — ADR-024/029).
    var isStartable: Bool {
        focusCount > 0 && !items.contains { $0.phase == .focus && $0.configuration == nil }
    }

    /// A value draft of this plan, for the editor and pure validation. Reading the
    /// items only — the editor mutates the draft, never the persisted model, until
    /// Save (mirrors the template editor).
    var draft: SessionPlanDraft {
        SessionPlanDraft(
            name: name,
            taskName: taskName,
            items: orderedItems.map(\.draft),
            icon: icon
        )
    }

    /// An immutable value freeze of this plan ready to execute. This is what
    /// `SessionCoordinator.startPlan` runs from — never the live model — so the
    /// running session is independent of any later edit or deletion (ADR-028).
    var executionSnapshot: SessionPlanExecutionSnapshot {
        SessionPlanExecutionSnapshot(taskName: taskName, items: orderedItems.map(\.draft))
    }
}
