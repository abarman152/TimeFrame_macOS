//
//  SessionLifecycleEvent.swift
//  time_frame
//
//  The pure, calendar-agnostic notification the SessionCoordinator emits at each
//  *meaningful* session transition (never on a timer tick — §53). It is the seam
//  that lets the Calendar integration observe the timer without the timer ever
//  importing EventKit or knowing that Calendar exists (ADR-035). The execution core
//  emits domain events; any integration consumes them.
//

import Foundation

/// A snapshot of the session at a lifecycle transition, carrying the values an
/// observer needs without reaching back into the engine.
///
/// It intentionally carries the live `FocusSession` (for identity, task, and the
/// frozen per-interval data) plus the *actual* transition time and the engine's
/// *projected* completion time — so a calendar representation uses authoritative
/// timestamps, never fabricated ones (§31).
struct SessionLifecycleContext {
    /// The session that transitioned. Its `id` is the stable association key.
    let session: FocusSession
    /// The actual wall-clock time of the transition (from the injected clock).
    let now: Date
    /// The engine's projected completion time (`now` + total remaining) while the
    /// session is still active, or `nil` once it reached a terminal state.
    let projectedEnd: Date?
}

/// The transitions worth reflecting on the calendar. Emitted only on real state
/// changes, so an observer that syncs the calendar never sees per-tick churn.
enum SessionLifecycleEvent {
    case started(SessionLifecycleContext)
    case paused(SessionLifecycleContext)
    case resumed(SessionLifecycleContext)
    case skipped(SessionLifecycleContext)
    case stopped(SessionLifecycleContext)
    case completed(SessionLifecycleContext)

    /// The context regardless of case.
    var context: SessionLifecycleContext {
        switch self {
        case let .started(c), let .paused(c), let .resumed(c),
             let .skipped(c), let .stopped(c), let .completed(c):
            return c
        }
    }
}
