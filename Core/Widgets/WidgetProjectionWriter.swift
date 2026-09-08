//
//  WidgetProjectionWriter.swift
//  time_frame (Milestone 11; concurrency-hardened in Milestone 26)
//
//  The app-side observer that keeps the widget projection fresh. It subscribes to the SAME
//  pure `SessionLifecycleEvent` seam the Calendar and Notification integrations use (§fan-out)
//  plus the coordinator's meaningful-transition hook (auto interval advance), builds a
//  `WidgetProjection` from authoritative state, writes it to the shared store, and asks
//  WidgetKit to reload (ADR-055).
//
//  Failure isolation: like Calendar/Notifications, a widget write can never affect the
//  timer. Every path is a best-effort no-op on failure — a missing App Group, a failed
//  encode, or a statistics fetch error is swallowed, and the engine is never touched. The
//  writer only ever *reads* the coordinator and *writes* the projection store.
//
//  It writes on meaningful transitions only — never on a per-second tick — matching the
//  same discipline as the notification scheduler (§40/ADR-040).
//
//  ## Why the today summary is deferred (M26, ADR-099)
//  `handle(_:)` runs **synchronously inside** `SessionCoordinator.pause()/resume()/stop()/
//  skip()/start`. Everything it does therefore lands on the user's Pause latency. The
//  session fields of a projection are derived from the engine's in-memory anchors and are
//  free; the *today summary* is a persistence read whose cost grows with recorded history.
//  Doing both synchronously made Pause O(all history) — measured at ~770 ms per control
//  with 2,000 recorded sessions, and unbounded thereafter.
//
//  So the writer splits the work by cost, not by importance:
//   • the **session** projection is written synchronously, so a widget/menu-bar surface
//     never shows a stale running/paused state; and
//   • the **today summary** is refreshed on a coalesced follow-up main-actor task that
//     runs after the control path has returned, then rewrites the projection if the
//     numbers actually changed.
//  This introduces no timer, no clock, and no polling: the follow-up is scheduled by the
//  same transitions that already write, and a burst of transitions collapses into one
//  refresh.
//

import Foundation
import WidgetKit

/// Observes authoritative session state and mirrors it into the widget projection store.
@MainActor
final class WidgetProjectionWriter {

    private let coordinator: SessionCoordinator
    private let store: WidgetProjectionStore
    private let now: () -> Date
    private let todayProvider: () -> TodaySummary?
    private let reload: () -> Void

    /// The most recently computed today summary, reused by the synchronous write so a
    /// control never pays for a statistics read. Refreshed off the control path.
    private var cachedToday: TodaySummary?

    /// Whether a today refresh is already queued. Collapses a burst of transitions
    /// (skip → boundary → skip) into a single statistics pass.
    private var todayRefreshScheduled = false

    /// Number of today-summary refreshes performed. A diagnostic of the coalescing
    /// invariant for the stability suite (M26); nothing depends on it at runtime.
    private(set) var todayRefreshCount = 0

    /// - Parameters:
    ///   - coordinator: the one shared coordinator (read-only here).
    ///   - store: the shared projection store (App Group in the app; volatile in tests).
    ///   - now: the app clock.
    ///   - todayProvider: computes the optional today summary; may return `nil` and must
    ///     never throw (the app wraps its statistics fetch defensively). Never called on
    ///     the timer control path — only from the deferred refresh.
    ///   - reload: asks WidgetKit to reload; defaults to reloading all Time Frame widgets.
    ///     Injected so tests can observe reloads without a WidgetKit host.
    init(
        coordinator: SessionCoordinator,
        store: WidgetProjectionStore,
        now: @escaping () -> Date = Date.init,
        todayProvider: @escaping () -> TodaySummary? = { nil },
        reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.coordinator = coordinator
        self.store = store
        self.now = now
        self.todayProvider = todayProvider
        self.reload = reload
    }

    /// Rebuilds the projection from authoritative state, persists it, and reloads the
    /// widgets. Cheap and synchronous: it reads only the engine's in-memory anchors and
    /// the cached today summary, so it is safe to call from a timer control. The today
    /// summary is brought up to date by a coalesced follow-up (see the type comment).
    func update() {
        writeProjection(today: cachedToday)
        scheduleTodayRefresh()
    }

    /// Subscribed to the app's lifecycle fan-out. Every meaningful transition refreshes
    /// the projection; the specific event is irrelevant because the projection is a full
    /// snapshot of current state.
    func handle(_ event: SessionLifecycleEvent) {
        update()
    }

    /// Recomputes the today summary now and rewrites the projection if it changed.
    /// Synchronous — used by the deferred refresh and by tests that need determinism.
    func refreshTodayNow() {
        todayRefreshCount += 1
        let summary = todayProvider()
        guard summary != cachedToday else { return }
        cachedToday = summary
        writeProjection(today: summary)
    }

    // MARK: Private

    /// Builds and stores a projection carrying the given today summary, then reloads.
    /// Best-effort throughout: a store or reload failure is swallowed (ADR-055).
    private func writeProjection(today: TodaySummary?) {
        let projection = WidgetProjectionMapper.projection(
            from: coordinator,
            now: now(),
            today: today
        )
        store.write(projection)
        reload()
    }

    /// Queues one today-summary refresh onto a fresh main-actor task, so the statistics
    /// read happens strictly *after* the control path that requested it has returned.
    /// Repeated requests while one is pending are collapsed into that pending pass,
    /// which reads live state when it runs and is therefore always current.
    private func scheduleTodayRefresh() {
        guard !todayRefreshScheduled else { return }
        todayRefreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.todayRefreshScheduled = false
            self.refreshTodayNow()
        }
    }
}
