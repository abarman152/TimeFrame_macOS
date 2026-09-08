//
//  FocusSession+History.swift
//  time_frame
//
//  History-oriented derived values for a persisted session. Computed from the
//  session's own persisted intervals (never from the live configuration), so
//  history stays accurate after a configuration is edited or deleted (ADR-019).
//

import Foundation

extension FocusSession {

    /// Focus intervals that ran to completion — the "N completed sessions" shown
    /// in history. Derived purely from persisted interval state.
    var completedFocusCount: Int {
        intervals.filter { $0.phase == .focus && $0.status == .completed }.count
    }

    /// The number of focus intervals originally planned for this session.
    var plannedFocusCount: Int {
        intervals.filter { $0.phase == .focus }.count
    }

    /// Total focused time actually achieved, summed from the planned durations of
    /// completed focus intervals (the reliable figure — each interval froze its
    /// own duration when the plan was generated).
    var completedFocusDuration: TimeInterval {
        intervals
            .filter { $0.phase == .focus && $0.status == .completed }
            .reduce(0) { $0 + $1.plannedDuration }
    }

    /// The day the session started, normalized to midnight, for history grouping.
    /// Falls back to `endedAt` and then the distant past so an unstarted row still
    /// sorts sensibly.
    func startDay(in calendar: Calendar = .current) -> Date {
        let anchor = startedAt ?? endedAt ?? .distantPast
        return calendar.startOfDay(for: anchor)
    }
}
