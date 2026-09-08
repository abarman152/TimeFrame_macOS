//
//  TimerEngine.swift
//  time_frame
//
//  The authoritative Pomodoro state machine. Pure domain logic: no SwiftUI, no
//  SwiftData, no real wall-clock timer of its own. Time is read exclusively
//  through an injected `TimeProviding`, so the engine is fully deterministic
//  under test.
//

import Foundation
import Observation

/// A reliable Pomodoro session engine.
///
/// ## Authoritative timeline
/// The engine never decrements a counter once per second. Each running interval
/// is anchored to a target end `Date`; the remaining time is always derived as
/// `targetEnd - now`. Because "now" comes from an injected `TimeProviding`, the
/// engine tolerates delayed ticks, CPU scheduling jitter, app backgrounding and
/// system sleep: whenever it is asked to `synchronize`, it recomputes the true
/// state from timestamps and fast-forwards through any intervals that elapsed
/// while it was not being ticked.
///
/// ## Driving the engine
/// The engine performs no scheduling. In production `SessionCoordinator` ticks
/// it a few times a second; in tests the suite advances a mock clock and calls
/// `synchronize()` directly. Either way the engine's behaviour is identical.
///
/// See `docs/03-TIMER-ENGINE.md` for the full state/transition specification.
@Observable
final class TimerEngine {

    // MARK: Configuration

    /// The ordered sequence of intervals this session runs through.
    private(set) var plan: IntervalPlan

    /// The time reference. Not observed — it is an implementation seam.
    @ObservationIgnored private let timeSource: TimeProviding

    // MARK: Observable state

    /// The current lifecycle state.
    private(set) var state: TimerState = .idle

    /// Index of the current interval within `plan`.
    private(set) var currentIndex: Int = 0

    /// Records of every interval that has already ended, in order.
    private(set) var completedIntervals: [IntervalRecord] = []

    // MARK: Timeline anchors (private)

    /// The instant the current interval began running (used for history).
    private var intervalStartDate: Date?

    /// The instant the current interval is scheduled to end while running.
    private var intervalEndDate: Date?

    /// Remaining seconds captured when the session was paused.
    private var remainingWhenPaused: TimeInterval?

    // MARK: Init

    init(plan: IntervalPlan, timeSource: TimeProviding = SystemTimeSource()) {
        self.plan = plan
        self.timeSource = timeSource
    }

    /// Convenience initializer that builds the plan from a configuration.
    convenience init(
        configuration: PomodoroConfigurationSnapshot,
        timeSource: TimeProviding = SystemTimeSource()
    ) {
        self.init(plan: IntervalPlan(configuration: configuration), timeSource: timeSource)
    }

    // MARK: Derived, read-only state

    /// The interval currently active (or about to start when idle).
    var currentInterval: PlannedInterval? {
        plan.interval(at: currentIndex)
    }

    /// The phase of the current interval.
    var currentPhase: TimerPhase? {
        currentInterval?.phase
    }

    /// The planned duration of the current interval, or zero if none.
    var currentPlannedDuration: TimeInterval {
        currentInterval?.duration ?? 0
    }

    /// Seconds remaining in the current interval, derived from the authoritative
    /// timeline. Never negative.
    var remaining: TimeInterval {
        remaining(at: timeSource.now())
    }

    /// Seconds elapsed in the current interval.
    var elapsed: TimeInterval {
        max(0, currentPlannedDuration - remaining)
    }

    /// Progress through the current interval, `0...1`.
    var progress: Double {
        let duration = currentPlannedDuration
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    /// The 1-based number of the focus session currently in progress or most
    /// recently reached (0 before the first focus starts).
    var currentFocusNumber: Int {
        let focusUpToHere = plan.intervals
            .prefix(currentIndex + 1)
            .filter { $0.phase == .focus }
            .count
        return focusUpToHere
    }

    /// Total number of focus sessions in the plan.
    var totalFocusSessions: Int {
        plan.intervals.filter { $0.phase == .focus }.count
    }

    // MARK: Timeline anchors (read-only, for persistence)

    /// The instant the current interval began running, if any. Exposed read-only
    /// so the persistence layer can record the timeline; the engine remains the
    /// only writer.
    var currentIntervalStart: Date? { intervalStartDate }

    /// The authoritative end of the current interval while running (nil while
    /// paused or inactive). This is the value the persistence layer records as
    /// `targetEndAt`, and the value recovery reads back to reconstruct the
    /// running interval — it already accounts for any pause/resume re-anchoring.
    var currentIntervalEnd: Date? { intervalEndDate }

    // MARK: Controls

    /// Begins a session from `idle`. No-op in any other state.
    func start() {
        guard state == .idle, !plan.isEmpty else { return }
        currentIndex = 0
        completedIntervals.removeAll(keepingCapacity: true)
        state = .running
        beginCurrentInterval(startingAt: timeSource.now())
        synchronize()
    }

    /// Freezes the current interval, preserving its remaining time. Only valid
    /// while `running`.
    func pause() {
        guard state == .running else { return }
        let now = timeSource.now()
        remainingWhenPaused = remaining(at: now)
        intervalEndDate = nil
        state = .paused
    }

    /// Resumes a paused session by re-anchoring the interval's end to the
    /// preserved remaining time. Does not reset the interval. Only valid while
    /// `paused`.
    func resume() {
        guard state == .paused else { return }
        let now = timeSource.now()
        let remainingSeconds = remainingWhenPaused ?? currentPlannedDuration
        intervalEndDate = now.addingTimeInterval(remainingSeconds)
        remainingWhenPaused = nil
        state = .running
        synchronize()
    }

    /// Stops the whole session. The in-progress interval is recorded as
    /// `cancelled` so history is preserved. Valid while `running` or `paused`.
    func stop() {
        guard state.isActive else { return }
        let now = timeSource.now()
        recordCurrentInterval(endedAt: now, outcome: .cancelled)
        clearAnchors()
        state = .cancelled
    }

    /// Ends the current interval early and advances to the next one, which
    /// begins running. The skipped interval is recorded (never discarded). If
    /// there is no next interval the session completes. Valid while `running`
    /// or `paused`.
    func skip() {
        guard state.isActive else { return }
        let now = timeSource.now()
        recordCurrentInterval(endedAt: now, outcome: .skipped)
        advance(from: now)
    }

    /// Restarts the current interval from its full configured duration without
    /// disturbing the rest of the plan. Preserves the running/paused state.
    /// Valid while `running` or `paused`.
    func restart() {
        guard state.isActive else { return }
        let now = timeSource.now()
        switch state {
        case .running:
            beginCurrentInterval(startingAt: now)
        case .paused:
            intervalStartDate = now
            intervalEndDate = nil
            remainingWhenPaused = currentPlannedDuration
        default:
            break
        }
    }

    /// Returns the engine to `idle` with the same plan, clearing history and
    /// timeline. Used to prepare a fresh run.
    func reset() {
        currentIndex = 0
        completedIntervals.removeAll(keepingCapacity: true)
        clearAnchors()
        state = .idle
    }

    /// Replaces the plan and returns to `idle`. Ignored while a session is
    /// active so a run is never corrupted mid-flight.
    func load(plan newPlan: IntervalPlan) {
        guard !state.isActive else { return }
        plan = newPlan
        reset()
    }

    // MARK: Restoration (app relaunch / recovery)

    /// Rebuilds engine state from a persisted snapshot so a session that was
    /// live when the app stopped can continue.
    ///
    /// This is the SwiftData-free recovery seam: the persistence layer reads the
    /// stored rows, assembles a `TimerEngineSnapshot` (plain values), and hands
    /// it here. The engine imports no persistence framework. Only meaningful
    /// from `idle` (a freshly built engine) and only for `.running`/`.paused`
    /// snapshots; any other request is ignored so an active run is never
    /// corrupted.
    ///
    /// After restoring a `.running` snapshot the caller should immediately
    /// `synchronize()` to fast-forward through any intervals whose planned end
    /// passed while the app was unavailable (see ADR-014). A `.paused` snapshot
    /// is left frozen — no time elapses while paused (ADR-013).
    func restore(from snapshot: TimerEngineSnapshot) {
        guard state == .idle else { return }
        guard snapshot.state == .running || snapshot.state == .paused else { return }
        guard plan.interval(at: snapshot.currentIndex) != nil else { return }

        currentIndex = snapshot.currentIndex
        completedIntervals = snapshot.completedIntervals
        intervalStartDate = snapshot.intervalStartDate
        intervalEndDate = snapshot.intervalEndDate
        remainingWhenPaused = snapshot.remainingWhenPaused
        state = snapshot.state
    }

    // MARK: Synchronization (the "tick")

    /// Reconciles the engine with the authoritative clock. Completes and
    /// advances through every interval whose planned end has passed. Safe to
    /// call at any cadence, including far less often than once per second.
    func synchronize() {
        guard state == .running else { return }
        let now = timeSource.now()

        while state == .running, let end = intervalEndDate, now >= end {
            // The current interval reached its planned end.
            recordCurrentInterval(endedAt: end, outcome: .completed)

            let nextIndex = currentIndex + 1
            if plan.interval(at: nextIndex) != nil {
                currentIndex = nextIndex
                // Anchor the next interval to the *planned* end of the previous
                // one, not to `now`. This prevents drift and lets a single
                // synchronize call fast-forward through intervals missed during
                // sleep or scheduling gaps.
                beginCurrentInterval(startingAt: end)
            } else {
                currentIndex = nextIndex
                clearAnchors()
                state = .completed
            }
        }
    }

    // MARK: Private helpers

    private func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .idle:
            return currentPlannedDuration
        case .running:
            guard let end = intervalEndDate else { return 0 }
            return max(0, end.timeIntervalSince(now))
        case .paused:
            return remainingWhenPaused ?? currentPlannedDuration
        case .completed, .cancelled:
            return 0
        }
    }

    private func beginCurrentInterval(startingAt start: Date) {
        intervalStartDate = start
        intervalEndDate = start.addingTimeInterval(currentPlannedDuration)
        remainingWhenPaused = nil
    }

    private func advance(from now: Date) {
        let nextIndex = currentIndex + 1
        if plan.interval(at: nextIndex) != nil {
            currentIndex = nextIndex
            state = .running
            beginCurrentInterval(startingAt: now)
            synchronize()
        } else {
            currentIndex = nextIndex
            clearAnchors()
            state = .completed
        }
    }

    private func recordCurrentInterval(endedAt: Date, outcome: IntervalOutcome) {
        guard let interval = currentInterval else { return }
        let started = intervalStartDate ?? endedAt.addingTimeInterval(-interval.duration)
        completedIntervals.append(
            IntervalRecord(
                index: interval.index,
                phase: interval.phase,
                plannedDuration: interval.duration,
                startedAt: started,
                endedAt: endedAt,
                outcome: outcome
            )
        )
    }

    private func clearAnchors() {
        intervalStartDate = nil
        intervalEndDate = nil
        remainingWhenPaused = nil
    }
}
