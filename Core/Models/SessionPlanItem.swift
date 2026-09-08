//
//  SessionPlanItem.swift
//  time_frame
//
//  One planned interval within a SessionPlan: a focus block or a break, its
//  duration, its position, and (for focus) the configuration it uses. An item
//  represents immutable execution *intent* — its own frozen duration, independent
//  of the configuration it was seeded from (ADR-027).
//

import Foundation
import SwiftData

/// A single planned interval in a `SessionPlan`.
///
/// The `duration` is the item's **own** value (seeded from a configuration when the
/// item was created, then independently editable), so editing the underlying
/// configuration never changes a saved plan item. A *focus* item also references a
/// `PomodoroConfiguration` — optional, with a nullify delete rule declared on the
/// configuration side — and freezes that configuration's name in
/// `configurationName` so the item still displays meaningfully if the configuration
/// is later deleted (the ADR-019 freezing principle). A break references no
/// configuration.
@Model
final class SessionPlanItem {
    /// Stable identity. No `#Unique` constraint: CloudKit mirroring does not
    /// support unique constraints (ADR-061). The plan editor only ever mints fresh
    /// `UUID`s, so identity stays effectively unique.
    private(set) var id: UUID = UUID()

    /// Position within the owning plan (0-based). Ordering is explicit and
    /// normalized on save — never inferred from array position alone (ADR-027).
    var order: Int = 0

    /// Which kind of interval this is. Stored via the shared `TimerPhase` enum, the
    /// same vocabulary the engine and `SessionInterval` use, so no mapping is
    /// needed on execution.
    var phase: TimerPhase = TimerPhase.focus

    /// The planned length in seconds — the item's own frozen intent.
    var duration: TimeInterval = 0

    /// The configuration a focus item uses. A reference (not a copy of its
    /// durations), optional so the item survives deletion of its configuration
    /// (the reference nullifies and the plan is shown as incomplete). `nil` for
    /// breaks.
    var configuration: PomodoroConfiguration?

    /// The configuration name frozen when the item was created/edited, so a focus
    /// item still shows a meaningful label after its configuration is deleted.
    /// Empty for breaks.
    var configurationName: String = ""

    /// The plan this item belongs to. Inverse is declared on `SessionPlan.items`;
    /// no macro here (one side only).
    var plan: SessionPlan?

    init(
        order: Int,
        phase: TimerPhase,
        duration: TimeInterval,
        configuration: PomodoroConfiguration? = nil,
        configurationName: String = ""
    ) {
        self.id = UUID()
        self.order = order
        self.phase = phase
        self.duration = duration
        self.configuration = configuration
        self.configurationName = configurationName
    }

    /// Whether this is a focus interval.
    var isFocus: Bool { phase == .focus }

    /// The configuration name to show: the frozen name if present, else the live
    /// reference's name, else a neutral label for a focus item that lost its
    /// configuration. Breaks return an empty string.
    var displayConfigurationName: String {
        if !isFocus { return "" }
        if !configurationName.isEmpty { return configurationName }
        if let live = configuration?.name, !live.isEmpty { return live }
        return "Configuration unavailable"
    }

    /// A value draft of this item, for editing and pure validation/execution.
    var draft: PlanItemDraft {
        PlanItemDraft(
            id: id,
            order: order,
            phase: phase,
            duration: duration,
            configurationID: configuration?.id,
            configurationName: isFocus ? configurationName : ""
        )
    }
}
