//
//  StatisticsRepository.swift
//  time_frame
//
//  The read-only bridge between persisted history and the pure statistics engine
//  (Milestone 10). It fetches `FocusSession`s once and maps each into an immutable
//  `SessionStatInput`, so the aggregator never touches SwiftData. It performs a
//  single fetch per call — never one query per day, per chart point, or per redraw —
//  and mutates nothing (no `save`, no schema change): statistics are a projection of
//  the same rows History browses, not a second store.
//
//  The mapping from `FocusSession` to `SessionStatInput` is defined here (rather than
//  on the pure value type) so the value type keeps importing only Foundation; the
//  SwiftUI dashboard reuses the very same mapping via `@Query` for live updates.
//

import Foundation
import SwiftData

/// Fetches persisted sessions and projects them into aggregation inputs. `@MainActor`,
/// operating on the main `ModelContext` like the other repositories (ADR-011); model
/// instances never cross an actor boundary.
@MainActor
struct StatisticsRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// All persisted sessions, newest first, mapped to pure aggregation inputs.
    /// A single fetch; the aggregator does the rest in memory.
    func sessionInputs() throws -> [SessionStatInput] {
        let descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor).map { SessionStatInput($0) }
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// The sessions that can contribute to `range`, mapped to aggregation inputs.
    ///
    /// The unbounded `sessionInputs()` above walks **every** session's intervals, so its
    /// cost grows without limit as history accumulates. Mapping a session is the
    /// expensive part (it faults in that session's `SessionInterval` rows), so this
    /// variant filters by the pure `mayContainActivity` superset test **before**
    /// mapping. Aggregating the result is byte-identical to aggregating all of history
    /// for the same range (the excluded sessions could not have contributed), but the
    /// work is proportional to the period rather than to the lifetime of the app.
    ///
    /// This is what every period-scoped caller — the widget's today summary and the
    /// Today/Statistics screens — uses, so an old, large history can never slow a
    /// timer control or a redraw (M26, ADR-100).
    func sessionInputs(in range: StatisticsDateRange) throws -> [SessionStatInput] {
        let descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
                .filter { range.mayContainActivity(startedAt: $0.startedAt, endedAt: $0.endedAt) }
                .map { SessionStatInput($0) }
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }

    /// The sessions that can contribute to **either** of two ranges (a period and the
    /// period it is compared against), fetched and mapped once. Trend-showing callers
    /// need both snapshots from one pass.
    func sessionInputs(in range: StatisticsDateRange, or other: StatisticsDateRange) throws -> [SessionStatInput] {
        let descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
                .filter {
                    range.mayContainActivity(startedAt: $0.startedAt, endedAt: $0.endedAt)
                        || other.mayContainActivity(startedAt: $0.startedAt, endedAt: $0.endedAt)
                }
                .map { SessionStatInput($0) }
        } catch {
            throw PersistenceError.fetchFailed(String(describing: error))
        }
    }
}

extension SessionStatInput {
    /// Projects a persisted `FocusSession` into an immutable statistics input, copying
    /// only frozen values (never a live configuration reference), so a metric can never
    /// change when a configuration is renamed or deleted.
    init(_ session: FocusSession) {
        self.init(
            id: session.id,
            taskName: session.taskName,
            configurationName: session.displayConfigurationName,
            status: session.status,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            intervals: session.orderedIntervals.map { IntervalStatInput($0) }
        )
    }
}

extension IntervalStatInput {
    /// Projects a persisted `SessionInterval` into an immutable statistics input.
    init(_ interval: SessionInterval) {
        self.init(
            phase: interval.phase,
            status: interval.status,
            plannedDuration: interval.plannedDuration,
            startedAt: interval.startedAt,
            endedAt: interval.endedAt,
            configurationName: interval.configurationName
        )
    }
}
