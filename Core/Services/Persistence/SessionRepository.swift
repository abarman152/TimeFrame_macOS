//
//  SessionRepository.swift
//  time_frame
//
//  Persistence for FocusSession / SessionInterval rows, isolated from the UI and
//  from the timer engine.
//

import Foundation
import SwiftData
import os

/// A description of one interval row's desired persisted state, derived from the
/// engine by the coordinator. Plain values so the engine never crosses into the
/// persistence layer.
nonisolated struct IntervalSync: Equatable, Sendable {
    let order: Int
    let status: IntervalStatus
    let startedAt: Date?
    let endedAt: Date?
    let targetEndAt: Date?
    let remainingAtPause: TimeInterval?
}

/// A description of a session's desired persisted state after an engine tick /
/// transition. Applied atomically (one save) so the store never reflects a
/// half-updated session.
nonisolated struct SessionSync: Equatable, Sendable {
    let currentIndex: Int
    let status: SessionStatus
    let pausedAt: Date?
    let endedAt: Date?
    let intervals: [IntervalSync]
}

/// Create/read plus lifecycle persistence for `FocusSession` and its
/// `SessionInterval`s.
///
/// Intervals for a session are created **once, up front** from the plan and
/// thereafter only *updated in place* (matched by `order`). Nothing here ever
/// inserts a second row for the same plan position, so synchronization and
/// recovery cannot create duplicate intervals (requirement of Milestone 2).
///
/// `@MainActor`, operating on the main `ModelContext`. Model instances never
/// cross an actor boundary (ADR-011). Failures surface as `PersistenceError`.
@MainActor
struct SessionRepository {
    let context: ModelContext

    /// The identifier of the device this repository runs on. Stamped onto sessions
    /// it creates and used by `fetchRecoverableSession` to keep timer recovery
    /// device-local across synced devices (ADR-063). Injectable so tests can
    /// simulate two devices in one process.
    let deviceID: String

    init(context: ModelContext, deviceID: String = CloudDeviceIdentity.current) {
        self.context = context
        self.deviceID = deviceID
    }

    // MARK: Create

    /// Persists a newly started session together with the full interval plan
    /// (all intervals `pending`). The caller reconciles immediately afterwards
    /// to mark the first interval running.
    @discardableResult
    func createSession(
        taskName: String,
        configuration: PomodoroConfiguration?,
        plan: IntervalPlan,
        startedAt: Date
    ) throws -> FocusSession {
        let session = FocusSession(
            taskName: taskName,
            configuration: configuration,
            status: .running,
            startedAt: startedAt
        )
        // Freeze the configuration name for historically accurate display even
        // if the configuration is later renamed or deleted (ADR-019).
        session.configurationName = configuration?.name ?? ""
        // Stamp the originating device so timer recovery stays device-local once
        // this session syncs to other devices (ADR-063).
        session.originatingDeviceID = deviceID
        session.currentIntervalIndex = 0
        for planned in plan.intervals {
            session.intervals.append(SessionInterval(planned: planned))
        }
        context.insert(session)
        try save()
        AppLog.session.info("Created session with \(plan.count, privacy: .public) intervals.")
        return session
    }

    /// Persists a session started from a **Session Plan** execution snapshot. Unlike
    /// `createSession`, the intervals come from the (possibly multi-configuration)
    /// snapshot rather than being generated from one configuration, and each focus
    /// interval freezes the name of the configuration it used. The session holds no
    /// live configuration reference — the plan's frozen values are authoritative, so
    /// editing or deleting the plan or its configurations can never change this
    /// running/historical session (ADR-028/029).
    @discardableResult
    func createPlannedSession(
        taskName: String,
        intervals: [SessionPlanExecutionSnapshot.Interval],
        configurationName: String,
        startedAt: Date
    ) throws -> FocusSession {
        let session = FocusSession(
            taskName: taskName,
            configuration: nil,
            status: .running,
            startedAt: startedAt
        )
        // A plan can mix configurations, so the session-level name is a summary
        // ("Research", or "Multiple configurations"); each interval also freezes its
        // own configuration name below.
        session.configurationName = configurationName
        // Stamp the originating device so timer recovery stays device-local once
        // this session syncs to other devices (ADR-063).
        session.originatingDeviceID = deviceID
        session.currentIntervalIndex = 0
        for planned in intervals {
            let interval = SessionInterval(
                phase: planned.phase,
                plannedDuration: planned.duration,
                order: planned.index
            )
            interval.configurationName = planned.configurationName
            session.intervals.append(interval)
        }
        context.insert(session)
        try save()
        AppLog.session.info("Created plan session with \(intervals.count, privacy: .public) intervals.")
        return session
    }

    // MARK: Read

    /// All sessions, newest first.
    func allSessions() throws -> [FocusSession] {
        let descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// The single session that was live when the app last stopped, if any.
    ///
    /// Only sessions that belong to **this device** are considered (ADR-063): a
    /// running/paused session that was started on another device and synced here
    /// via CloudKit is deliberately left untouched — neither recovered into a
    /// second live timer, nor marked `interrupted` (which would sync back and stop
    /// the device that actually owns it). Legacy rows with no recorded origin are
    /// treated as local, preserving pre-sync recovery behaviour.
    ///
    /// If more than one *local* session is in a recoverable state (should not
    /// happen, but defends against inconsistent data), the newest is returned and
    /// the rest are marked `interrupted` so exactly one session can ever be
    /// restored.
    func fetchRecoverableSession() throws -> FocusSession? {
        let recoverable = try allSessions().filter {
            $0.status.isRecoverable && $0.belongsToDevice(deviceID)
        }
        guard let newest = recoverable.first else { return nil }
        let stale = recoverable.dropFirst()
        if !stale.isEmpty {
            for session in stale {
                session.status = .interrupted
                session.endedAt = session.endedAt ?? session.startedAt
            }
            try save()
            AppLog.session.error("Found \(stale.count, privacy: .public) extra active sessions; marked interrupted.")
        }
        return newest
    }

    // MARK: Lifecycle persistence

    /// Applies a derived sync state to a session in one save. Interval rows are
    /// matched by `order` and updated in place; unmatched orders are left alone.
    func applySync(_ sync: SessionSync, to session: FocusSession) throws {
        let byOrder = Dictionary(
            session.intervals.map { ($0.order, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for update in sync.intervals {
            guard let interval = byOrder[update.order] else { continue }
            interval.status = update.status
            interval.startedAt = update.startedAt
            interval.endedAt = update.endedAt
            interval.targetEndAt = update.targetEndAt
            interval.remainingAtPause = update.remainingAtPause
        }
        session.currentIntervalIndex = sync.currentIndex
        session.status = sync.status
        session.pausedAt = sync.pausedAt
        session.endedAt = sync.endedAt
        try save()
    }

    /// Marks a session `interrupted` (a recovery-time terminal outcome).
    func markInterrupted(_ session: FocusSession, at date: Date) throws {
        session.status = .interrupted
        session.endedAt = session.endedAt ?? date
        // Any still-running/paused interval is left as-is for history; only its
        // terminality is implied by the session being interrupted.
        try save()
        AppLog.session.error("Session marked interrupted during recovery.")
    }

    // MARK: Private

    private func save() throws {
        do {
            try context.save()
        } catch {
            throw PersistenceError.saveFailed(String(describing: error))
        }
    }
}
