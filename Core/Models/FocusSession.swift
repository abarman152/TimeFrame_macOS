//
//  FocusSession.swift
//  time_frame
//
//  A persisted running or completed Pomodoro plan.
//

import Foundation
import SwiftData

/// One run of a Pomodoro plan — either in progress or finished.
///
/// A session references the `PomodoroConfiguration` it was built from (it does
/// not duplicate the configuration's values) and owns the concrete
/// `SessionInterval`s it is composed of.
@Model
final class FocusSession {
    // No `#Unique` on `id`: CloudKit mirroring does not support unique
    // constraints (ADR-061). `id` remains a stable, freshly generated identifier.
    private(set) var id: UUID = UUID()

    /// The task this session is focused on (may be empty for an ad-hoc run).
    var taskName: String = ""

    /// The configuration this session was generated from. Optional so a
    /// session survives deletion of its configuration (`.nullify`).
    var configuration: PomodoroConfiguration?

    /// The configuration's name captured at the moment the session started.
    ///
    /// Historical display must remain accurate even if the configuration is
    /// later renamed or deleted (the relationship above nullifies on delete).
    /// The per-interval `plannedDuration`/`phase` already freeze the *timing*;
    /// this freezes the *name* so history never silently changes. Defaulted so
    /// sessions created before this field existed migrate cleanly (they fall
    /// back to the live relationship via `displayConfigurationName`). See
    /// ADR-019.
    var configurationName: String = ""

    var startedAt: Date?

    /// When the session was most recently paused (nil while running or before
    /// the first pause). Informational; the authoritative frozen remaining lives
    /// on the current `SessionInterval`.
    var pausedAt: Date?

    var endedAt: Date?

    /// Index of the interval currently in progress within `intervals`.
    var currentIntervalIndex: Int = 0

    /// Persisted lifecycle status. Distinct from the engine's `TimerState`: it
    /// adds `planned` (created, not started) and `interrupted` (could not be
    /// safely recovered). See `SessionStatus` and ADR-012.
    var status: SessionStatus = SessionStatus.planned

    /// The stable identifier of the device that started this session (a random
    /// per-install UUID string — never an iCloud account identifier or any PII).
    ///
    /// With CloudKit sync (Milestone 13), a running/paused session may appear on
    /// another device. Timer execution is **device-local**: only the device that
    /// started a session recovers or advances its live timer. This field is what
    /// `fetchRecoverableSession` uses to leave a session running on *another*
    /// device untouched — so a synced "running" row never triggers a second timer
    /// takeover (ADR-063). Optional and defaulted so legacy rows (and rows created
    /// before this field existed) migrate cleanly; a `nil` origin is treated as
    /// local for backward compatibility. See `docs/22-ICLOUD-CLOUDKIT.md`.
    var originatingDeviceID: String?

    /// The concrete intervals this session runs through. Owned by the session:
    /// deleting the session cascades to its intervals.
    @Relationship(deleteRule: .cascade, inverse: \SessionInterval.session)
    var intervals: [SessionInterval] = []

    init(
        taskName: String = "",
        configuration: PomodoroConfiguration? = nil,
        status: SessionStatus = .planned,
        startedAt: Date? = nil
    ) {
        self.id = UUID()
        self.taskName = taskName
        self.configuration = configuration
        self.status = status
        self.startedAt = startedAt
    }

    /// The intervals in planned order.
    var orderedIntervals: [SessionInterval] {
        intervals.sorted { $0.order < $1.order }
    }

    /// The interval currently in progress, matched by `order`.
    var currentInterval: SessionInterval? {
        intervals.first { $0.order == currentIntervalIndex }
    }

    /// Whether the session finished by completing all of its intervals.
    var isCompleted: Bool { status == .completed }

    /// Whether this session's live timer belongs to (may be recovered/advanced by)
    /// the device identified by `deviceID`. A session with no recorded origin
    /// (legacy rows, or rows created before device tracking) is treated as local
    /// so existing recovery behaviour is unchanged. A session that originated on a
    /// *different* device is left to that device — the running-session policy that
    /// prevents a synced running row from starting a second timer here (ADR-063).
    func belongsToDevice(_ deviceID: String) -> Bool {
        guard let originatingDeviceID, !originatingDeviceID.isEmpty else { return true }
        return originatingDeviceID == deviceID
    }

    /// The configuration name to show for this session. Prefers the frozen
    /// snapshot (historically accurate); falls back to the live relationship for
    /// sessions created before the snapshot existed, then to a neutral label.
    var displayConfigurationName: String {
        if !configurationName.isEmpty { return configurationName }
        if let live = configuration?.name, !live.isEmpty { return live }
        return "No configuration"
    }
}
