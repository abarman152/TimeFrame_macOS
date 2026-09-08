//
//  TimeSource.swift
//  time_frame
//
//  An injectable wall-clock abstraction so the timer engine can be driven by a
//  deterministic clock in tests and the real system clock in production.
//

import Foundation

/// Supplies the current instant used by the timer engine as its authoritative
/// time reference.
///
/// The engine never counts down by decrementing a value once per second.
/// Instead it anchors each interval to a target end `Date` and derives the
/// remaining time as `targetEnd - now`. `TimeProviding` is the seam that makes
/// that "now" injectable: production uses the system clock, tests use a
/// controllable clock so a 25-minute interval can be verified instantly.
protocol TimeProviding: Sendable {
    /// The current instant. Production returns `Date()`; tests return a value
    /// they advance manually. Nonisolated so any isolation domain (and a
    /// nonisolated test clock) can supply time.
    nonisolated func now() -> Date
}

/// Production time source backed by the system wall clock.
///
/// Wall-clock time (rather than a monotonic clock) is intentional: a Pomodoro
/// interval should keep elapsing while the machine sleeps or the app is
/// backgrounded, which is exactly how `Date` behaves. See
/// `docs/DECISIONS.md` for the rationale.
nonisolated struct SystemTimeSource: TimeProviding {
    init() {}
    func now() -> Date { Date() }
}
