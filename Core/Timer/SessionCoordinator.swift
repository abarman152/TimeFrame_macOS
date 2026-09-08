//
//  SessionCoordinator.swift
//  time_frame
//
//  The production driver that sits between the pure `TimerEngine` and durable
//  SwiftData persistence. It owns the periodic "tick" that keeps the engine
//  synchronized, mirrors every meaningful lifecycle transition into the store
//  through the repositories, and restores a live session on app relaunch.
//

import Foundation
import Observation
import SwiftData
import os
#if canImport(AppKit)
import AppKit
#endif

/// Coordinates the timer engine, the session lifecycle, and persistence.
///
/// ```
/// SwiftUI → SessionCoordinator → TimerEngine → Clock
///                     │
///                     └────────→ Session/Configuration repositories → SwiftData
/// ```
///
/// The engine stays entirely persistence-agnostic (it imports no SwiftData). The
/// coordinator reads the engine's pure state and hands the repositories plain
/// values to persist (ADR-011/012). Correctness of *time* lives in the engine
/// (derived from timestamps), so the tick cadence is irrelevant and a missed
/// tick, a sleep, or a relaunch are all reconciled from the authoritative
/// timeline (ADR-013/014).
@Observable
@MainActor
final class SessionCoordinator {

    /// The engine being driven. Observed so views update as it changes.
    let engine: TimerEngine

    /// Configuration CRUD, exposed so the (future) UI can manage configurations.
    @ObservationIgnored let configurations: ConfigurationRepository

    /// Session persistence.
    @ObservationIgnored let sessions: SessionRepository

    /// Task-template CRUD, exposed so the Templates UI manages templates through
    /// the same persistence boundary as configurations and sessions.
    @ObservationIgnored let templates: TaskTemplateRepository

    /// Session-plan CRUD, exposed so the Plans UI manages plans through the same
    /// persistence boundary. The coordinator itself only *executes* a plan
    /// (`startPlan`); designing and storing plans is the repository's job (ADR-026).
    @ObservationIgnored let plans: SessionPlanRepository

    /// The session currently being driven / most recently driven, if any.
    private(set) var activeSession: FocusSession?

    /// The outcome of the most recent relaunch recovery attempt, so the UI can
    /// present a restored session or a non-alarming "couldn't restore" notice.
    /// Observed; cleared by `acknowledgeRecovery()` once the UI has shown it.
    private(set) var recoveryOutcome: RecoveryOutcome = .none

    /// The session that recovery marked `interrupted`, if any — kept only so the
    /// UI can name it in the notice. Not the active session.
    private(set) var interruptedSession: FocusSession?

    @ObservationIgnored private let timeSource: TimeProviding
    @ObservationIgnored private let tickInterval: Duration
    @ObservationIgnored private let autoTick: Bool
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Monotonic id of the heartbeat generation currently considered live.
    ///
    /// A cancelled heartbeat does not stop instantly: it resumes from its
    /// `Task.sleep` on a later main-actor turn and only then unwinds. Without a
    /// generation stamp, that late unwind would clear `ticker` — potentially the
    /// reference to a *newer* heartbeat started in between — leaving a live,
    /// unreferenced tick loop that `stopTicking()` can no longer cancel and that
    /// `startTickingIfNeeded()`'s `ticker == nil` guard would then happily
    /// duplicate. Each heartbeat captures the generation it was born into and
    /// only clears `ticker` if it is still the current one (M26, ADR-099).
    @ObservationIgnored private var tickerGeneration: UInt64 = 0

    /// A **display-only** repaint signal: the whole-second instant of the most recent
    /// heartbeat, updated at most once per second while a session runs.
    ///
    /// This is not a clock and carries no authority — `TimerEngine`'s frozen anchors
    /// remain the only source of elapsed time, and nothing here decrements anything. It
    /// exists because a surface that shows a live countdown needs *something observable*
    /// to change once a second, and the engine's own state only changes at interval
    /// boundaries.
    ///
    /// The menu bar used to get that from a `TimelineView`, but a `TimelineView` inside a
    /// `MenuBarExtra` **label** re-renders the `NSStatusBarButton` synchronously and
    /// re-arms itself during that render, producing an unbounded update loop that pinned
    /// the main thread at 100% CPU for as long as a session was running (M26, ADR-101).
    /// Driving the repaint from the **existing** heartbeat instead is safe precisely
    /// because the change originates outside the render pass, so it cannot self-perpetuate.
    ///
    /// It is written only here, only from `tick()`, and only when the whole second
    /// actually changes — never per tick, and never on a path that touches persistence,
    /// notifications, or the widget projection.
    private(set) var displaySecond: Date = .distantPast

    /// The number of heartbeat tasks currently alive. The invariant is `0...1`:
    /// zero while idle/paused/terminal, one while running. Exposed internally so
    /// the stability suite can assert the heartbeat never multiplies or leaks —
    /// it is a diagnostic of an architectural invariant, not runtime state
    /// anything depends on (M26).
    @ObservationIgnored private(set) var activeTickerCount: Int = 0

    /// The (index, state) last written to the store, so the heartbeat only
    /// persists on a real transition rather than on every sub-second tick.
    @ObservationIgnored private var lastPersistedSignature: (Int, TimerState)?

    /// Observer for *meaningful* lifecycle transitions (start/pause/resume/skip/
    /// stop/completion — never a tick, §53). The Calendar integration subscribes
    /// here; the coordinator stays entirely calendar-agnostic and imports no
    /// EventKit (ADR-035). Nil in tests that don't exercise the integration.
    @ObservationIgnored var onLifecycleEvent: ((SessionLifecycleEvent) -> Void)?

    /// An optional, purely additive observer fired whenever a *meaningful* engine
    /// transition is persisted — i.e. the `(currentIndex, state)` signature changes,
    /// exactly the boundaries `reconcileIfChanged()` writes on (never a sub-second tick;
    /// ADR-040/ADR-055). It exists so a read-only projection surface (the Milestone 11
    /// widget writer) can refresh at an *auto* interval boundary — focus→break→focus —
    /// which advances the engine without emitting a lifecycle event. This changes no
    /// timer semantics: it is a fire-and-forget notification, called after the state is
    /// already reconciled, and the engine is never touched in response.
    @ObservationIgnored var onMeaningfulTransition: (() -> Void)?

    /// Guards against emitting `.completed` more than once for a run (completion
    /// can be reached from a tick or from skipping the final interval).
    @ObservationIgnored private var completionEmitted = false

    #if canImport(AppKit)
    @ObservationIgnored private var sleepWakeObservers: [NSObjectProtocol] = []
    #endif

    // MARK: Init

    /// - Parameter autoTick: when `true` (production), a background heartbeat
    ///   drives `tick()` while running. Tests pass `false` and call `tick()`
    ///   directly after advancing a mock clock, keeping them deterministic.
    /// - Parameter onConfigurationsChanged: a neutral, opaque hook forwarded to the
    ///   `ConfigurationRepository` and fired after any configuration mutation. The app wires it to
    ///   republish the Control Center quick-start catalog (Milestone 24, ADR-097). The coordinator
    ///   only forwards it — it owns no widget knowledge and this never affects the timer.
    /// - Parameter onLibraryChanged: the same kind of neutral, opaque hook, forwarded to the
    ///   `TaskTemplateRepository` and `SessionPlanRepository` and fired after any template or plan
    ///   mutation. The app wires it to refresh the menu bar's Quick Start list, so pinning,
    ///   renaming, or deleting an item is reflected without polling and without a restart
    ///   (Milestone 28, ADR-105). Forwarded only — the coordinator owns no Quick Start knowledge
    ///   and this never affects the timer.
    init(
        context: ModelContext,
        timeSource: TimeProviding = SystemTimeSource(),
        tickInterval: Duration = .milliseconds(250),
        autoTick: Bool = true,
        onConfigurationsChanged: (@MainActor () -> Void)? = nil,
        onLibraryChanged: (@MainActor () -> Void)? = nil
    ) {
        self.timeSource = timeSource
        self.tickInterval = tickInterval
        self.autoTick = autoTick
        self.engine = TimerEngine(plan: IntervalPlan(intervals: []), timeSource: timeSource)
        self.configurations = ConfigurationRepository(context: context, onChange: onConfigurationsChanged)
        self.sessions = SessionRepository(context: context)
        self.templates = TaskTemplateRepository(context: context, onChange: onLibraryChanged)
        self.plans = SessionPlanRepository(context: context, onChange: onLibraryChanged)
        observeSleepWake()
    }

    deinit {
        ticker?.cancel()
        #if canImport(AppKit)
        for token in sleepWakeObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        #endif
    }

    // MARK: Session lifecycle controls

    /// Starts and persists a new session from a configuration. Ignored if a
    /// session is already active (the caller must stop it first).
    ///
    /// - Parameter totalSessions: overrides the configuration's default number
    ///   of focus sessions *for this run only*. The saved configuration is never
    ///   mutated — the override is applied to a value snapshot, so the
    ///   `Configuration → Session Start Options → FocusSession` chain stays
    ///   one-directional (requirement of Milestone 3).
    @discardableResult
    func startSession(
        configuration: PomodoroConfiguration,
        taskName: String = "",
        totalSessions: Int? = nil
    ) throws -> FocusSession? {
        guard !engine.state.isActive else { return nil }

        let snapshot = configuration.snapshot.overriding(totalSessions: totalSessions)
        engine.load(plan: IntervalPlan(configuration: snapshot))
        let startedAt = timeSource.now()
        engine.start()

        let session = try sessions.createSession(
            taskName: taskName,
            configuration: configuration,
            plan: engine.plan,
            startedAt: startedAt
        )
        activeSession = session
        completionEmitted = false
        try reconcile()
        startTickingIfNeeded()
        emit { .started($0) }
        return session
    }

    /// Starts and persists a session from a **Session Plan** execution snapshot.
    /// Ignored if a session is already active or the snapshot has no interval.
    ///
    /// The plan's values are already frozen in the immutable `snapshot`, so this
    /// runs through the *same* engine and persistence path as any other session —
    /// there is no second timer implementation (ADR-028). Because the snapshot holds
    /// no reference to the saved plan or its configurations, editing or deleting the
    /// plan afterwards cannot affect the running session (ADR-029). The engine plan
    /// is built directly from the snapshot's ordered intervals (which may span
    /// multiple configurations — ADR-030).
    @discardableResult
    func startPlan(_ snapshot: SessionPlanExecutionSnapshot) throws -> FocusSession? {
        guard !engine.state.isActive else { return nil }
        let plan = snapshot.enginePlan
        guard !plan.isEmpty else { return nil }

        engine.load(plan: plan)
        let startedAt = timeSource.now()
        engine.start()

        let session = try sessions.createPlannedSession(
            taskName: snapshot.taskName,
            intervals: snapshot.intervals,
            configurationName: snapshot.summaryConfigurationName,
            startedAt: startedAt
        )
        activeSession = session
        completionEmitted = false
        try reconcile()
        startTickingIfNeeded()
        emit { .started($0) }
        return session
    }

    func pause() throws {
        guard engine.state == .running else { return }
        engine.pause()
        try reconcile()
        stopTicking()
        emit { .paused($0) }
    }

    func resume() throws {
        guard engine.state == .paused else { return }
        engine.resume()
        try reconcile()
        startTickingIfNeeded()
        emit { .resumed($0) }
    }

    /// Stops (cancels) the active session, preserving completed intervals and
    /// recording the in-progress one as cancelled.
    func stop() throws {
        guard engine.state.isActive else { return }
        engine.stop()
        try reconcile()
        stopTicking()
        emit { .stopped($0) }
    }

    func skip() throws {
        guard engine.state.isActive else { return }
        engine.skip()
        try reconcile()
        startTickingIfNeeded()
        // Skipping the final interval completes the session; prefer the single
        // `.completed` event over a `.skipped` in that case.
        if !emitCompletionIfNeeded() { emit { .skipped($0) } }
    }

    /// Restarts the current interval in place (reset model — ADR-011): no new
    /// interval row is created, the existing one is re-anchored.
    func restart() throws {
        guard engine.state.isActive else { return }
        engine.restart()
        try reconcile()
        startTickingIfNeeded()
    }

    // MARK: Tick (heartbeat entry point; also called on wake and by tests)

    /// Reconciles the engine with the clock and persists a transition if one
    /// occurred. Deterministic and synchronous so tests can drive it directly
    /// after advancing a mock clock.
    func tick() throws {
        engine.synchronize()
        try reconcileIfChanged()
        emitCompletionIfNeeded()
        refreshDisplaySecond()
    }

    /// Advances the display-only repaint signal when the whole second changes, so a
    /// live countdown surface repaints ~1 Hz. Pure in-memory assignment: no persistence,
    /// no projection write, no notification, no engine mutation.
    private func refreshDisplaySecond() {
        let now = timeSource.now()
        let whole = Date(timeIntervalSinceReferenceDate:
                            now.timeIntervalSinceReferenceDate.rounded(.down))
        if whole != displaySecond { displaySecond = whole }
    }

    // MARK: Recovery (app relaunch)

    /// Restores the session that was live when the app last stopped, if any.
    ///
    /// Returns `true` if a session was restored into an active (running/paused)
    /// state. A running session is fast-forwarded through every interval whose
    /// planned end passed while the app was unavailable and, if still unfinished,
    /// resumes running (per the chosen "reconcile & resume" policy). A paused
    /// session is restored paused. A session whose persisted state is too
    /// inconsistent to trust is marked `interrupted` and not restored.
    @discardableResult
    func recover() throws -> Bool {
        guard let session = try sessions.fetchRecoverableSession() else { return false }
        let now = timeSource.now()

        let ordered = session.orderedIntervals
        guard !ordered.isEmpty else {
            try interrupt(session, at: now)
            return false
        }

        let plan = IntervalPlan(intervals: ordered.map {
            PlannedInterval(index: $0.order, phase: $0.phase, duration: $0.plannedDuration)
        })
        let history = ordered.compactMap { interval -> IntervalRecord? in
            guard let outcome = interval.status.engineOutcome else { return nil }
            let started = interval.startedAt
                ?? (interval.endedAt ?? now).addingTimeInterval(-interval.plannedDuration)
            let ended = interval.endedAt ?? now
            return IntervalRecord(
                index: interval.order,
                phase: interval.phase,
                plannedDuration: interval.plannedDuration,
                startedAt: started,
                endedAt: ended,
                outcome: outcome
            )
        }

        let index = session.currentIntervalIndex
        guard plan.interval(at: index) != nil, let current = session.currentInterval else {
            try interrupt(session, at: now)
            return false
        }

        let snapshot: TimerEngineSnapshot
        switch session.status {
        case .running:
            guard let start = current.startedAt, let target = current.targetEndAt else {
                try interrupt(session, at: now)
                return false
            }
            snapshot = TimerEngineSnapshot(
                state: .running,
                currentIndex: index,
                completedIntervals: history,
                intervalStartDate: start,
                intervalEndDate: target,
                remainingWhenPaused: nil
            )
        case .paused:
            guard let remaining = current.remainingAtPause else {
                try interrupt(session, at: now)
                return false
            }
            snapshot = TimerEngineSnapshot(
                state: .paused,
                currentIndex: index,
                completedIntervals: history,
                intervalStartDate: current.startedAt,
                intervalEndDate: nil,
                remainingWhenPaused: remaining
            )
        default:
            return false
        }

        engine.load(plan: plan)
        engine.restore(from: snapshot)
        guard engine.state == snapshot.state else {
            try interrupt(session, at: now)
            return false
        }

        if engine.state == .running {
            engine.synchronize() // fast-forward through intervals missed while away
        }

        activeSession = session
        completionEmitted = false
        recoveryOutcome = .restored
        interruptedSession = nil
        try reconcile()
        if engine.state == .running {
            startTickingIfNeeded()
        }
        AppLog.session.info("Recovered session; engine now \(self.engine.state.rawValue, privacy: .public).")
        return engine.state.isActive
    }

    /// Records that a session could not be safely restored, so the UI can show a
    /// non-alarming notice, then marks it interrupted in the store.
    private func interrupt(_ session: FocusSession, at date: Date) throws {
        interruptedSession = session
        recoveryOutcome = .interrupted
        try sessions.markInterrupted(session, at: date)
    }

    /// Clears the recovery notice once the UI has presented it. Idempotent.
    func acknowledgeRecovery() {
        recoveryOutcome = .none
        interruptedSession = nil
    }

    /// Returns the engine to `idle` and forgets the finished/active-record so the
    /// setup screen is shown for a fresh run. Only valid once the current run has
    /// reached a terminal state (completed/cancelled) or is already idle — an
    /// active run must be stopped first, so a session can never be silently
    /// discarded mid-flight. The persisted `FocusSession` is left untouched (its
    /// final state already lives in the store and in History).
    func prepareForNewSession() {
        guard !engine.state.isActive else { return }
        stopTicking()
        engine.reset()
        activeSession = nil
        lastPersistedSignature = nil
        completionEmitted = false
        acknowledgeRecovery()
    }

    // MARK: Lifecycle event emission (calendar-agnostic seam)

    /// The current transition context from the engine's authoritative state, or nil
    /// if there is no active session. Exposed read-only so an integration can
    /// (re)synchronize itself with the live session outside of an event — e.g. the
    /// Notification layer rescheduling after relaunch recovery or when the user
    /// re-enables notifications mid-run. Pure: it reads engine/model state only and
    /// imports nothing from any integration (ADR-043).
    func currentLifecycleContext() -> SessionLifecycleContext? {
        makeLifecycleContext()
    }

    /// Builds the transition context from the engine's authoritative state, or nil
    /// if there is no active session to describe.
    private func makeLifecycleContext() -> SessionLifecycleContext? {
        guard let session = activeSession else { return nil }
        let now = timeSource.now()
        let projectedEnd: Date? = engine.state.isTerminal
            ? nil
            : now.addingTimeInterval(totalRemaining())
        return SessionLifecycleContext(session: session, now: now, projectedEnd: projectedEnd)
    }

    /// The total remaining time across the current and all later intervals, from
    /// the authoritative engine — used only to project a calendar end time.
    private func totalRemaining() -> TimeInterval {
        guard engine.state == .running || engine.state == .paused else { return 0 }
        let currentRemaining = max(0, engine.remaining)
        let laterDurations = engine.plan.intervals
            .filter { $0.index > engine.currentIndex }
            .reduce(0) { $0 + $1.duration }
        return currentRemaining + laterDurations
    }

    /// Emits a lifecycle event to the observer, if one is attached and there is an
    /// active session. Pure fire-and-forget: the observer must never be able to
    /// affect the timer (it is called after the store is already reconciled).
    private func emit(_ build: (SessionLifecycleContext) -> SessionLifecycleEvent) {
        guard let onLifecycleEvent, let context = makeLifecycleContext() else { return }
        onLifecycleEvent(build(context))
    }

    /// Emits `.completed` exactly once when the engine reaches the completed state.
    @discardableResult
    private func emitCompletionIfNeeded() -> Bool {
        guard engine.state == .completed, !completionEmitted else { return false }
        completionEmitted = true
        emit { .completed($0) }
        return true
    }

    // MARK: Reconciliation (engine → persistence)

    /// Persists the engine's current state onto the active session (one save).
    func reconcile() throws {
        guard let session = activeSession else { return }
        try sessions.applySync(makeSync(), to: session)
        lastPersistedSignature = (engine.currentIndex, engine.state)
        if engine.state.isTerminal { stopTicking() }
    }

    /// Reconciles only if a transition occurred since the last persisted state,
    /// so the sub-second heartbeat does not write on every tick.
    private func reconcileIfChanged() throws {
        let signature = (engine.currentIndex, engine.state)
        if let last = lastPersistedSignature, last == signature { return }
        try reconcile()
        // A meaningful transition was just persisted; notify any read-only projection
        // observer (e.g. the widget writer). Fire-and-forget: never affects the engine.
        onMeaningfulTransition?()
    }

    /// Derives the desired persisted state from the engine's pure state.
    private func makeSync() -> SessionSync {
        var intervals: [IntervalSync] = engine.completedIntervals.map { record in
            IntervalSync(
                order: record.index,
                status: IntervalStatus(record.outcome),
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                targetEndAt: nil,
                remainingAtPause: nil
            )
        }

        switch engine.state {
        case .running:
            intervals.append(IntervalSync(
                order: engine.currentIndex,
                status: .running,
                startedAt: engine.currentIntervalStart,
                endedAt: nil,
                targetEndAt: engine.currentIntervalEnd,
                remainingAtPause: nil
            ))
        case .paused:
            intervals.append(IntervalSync(
                order: engine.currentIndex,
                status: .paused,
                startedAt: engine.currentIntervalStart,
                endedAt: nil,
                targetEndAt: nil,
                remainingAtPause: engine.remaining
            ))
        case .idle, .completed, .cancelled:
            break
        }

        let now = timeSource.now()
        let endedAt: Date? = engine.state.isTerminal
            ? (engine.completedIntervals.last?.endedAt ?? now)
            : nil
        let pausedAt: Date? = engine.state == .paused ? now : nil

        return SessionSync(
            currentIndex: engine.currentIndex,
            status: SessionStatus(engine.state),
            pausedAt: pausedAt,
            endedAt: endedAt,
            intervals: intervals
        )
    }

    // MARK: Heartbeat

    private func startTickingIfNeeded() {
        guard engine.state == .running else {
            stopTicking()
            return
        }
        guard autoTick else { return }
        guard ticker == nil else { return }
        tickerGeneration &+= 1
        let generation = tickerGeneration
        activeTickerCount += 1
        ticker = Task { [weak self, tickInterval] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try self.tick()
                } catch {
                    AppLog.session.error("Tick reconcile failed: \(String(describing: error), privacy: .public)")
                }
                if self.engine.state != .running { break }
                try? await Task.sleep(for: tickInterval)
            }
            guard let self else { return }
            self.activeTickerCount -= 1
            // Only the heartbeat that is still current may clear the handle. A
            // late-unwinding cancelled generation must not clobber a newer one.
            if self.tickerGeneration == generation { self.ticker = nil }
        }
    }

    private func stopTicking() {
        // Retiring the generation makes any in-flight heartbeat's late unwind a
        // no-op against `ticker`, so the handle always describes reality.
        tickerGeneration &+= 1
        ticker?.cancel()
        ticker = nil
    }

    // MARK: Sleep / wake

    /// Observes system wake so the engine reconciles the moment the Mac wakes,
    /// rather than waiting for the next heartbeat. Correctness does not depend on
    /// this (the next tick would reconcile anyway); it just makes the catch-up
    /// immediate. See `docs/04-SESSION-LIFECYCLE.md`.
    private func observeSleepWake() {
        #if canImport(AppKit)
        let center = NSWorkspace.shared.notificationCenter
        let onWake = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.engine.state == .running else { return }
                do {
                    try self.tick()
                } catch {
                    AppLog.session.error("Wake reconcile failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
        sleepWakeObservers = [onWake]
        #endif
    }
}

private extension IntervalStatus {
    /// The engine outcome corresponding to a terminal interval status, or nil if
    /// the interval has not reached a terminal state.
    var engineOutcome: IntervalOutcome? {
        switch self {
        case .completed: return .completed
        case .skipped: return .skipped
        case .cancelled: return .cancelled
        case .pending, .running, .paused: return nil
        }
    }
}
