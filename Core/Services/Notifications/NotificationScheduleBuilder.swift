//
//  NotificationScheduleBuilder.swift
//  time_frame
//
//  The pure planner that turns a running-session snapshot into the set of
//  `NotificationDescriptor`s to schedule. It mirrors the engine's authoritative
//  timeline (never a parallel timer — §23/§73) and emits **one descriptor per upcoming
//  interval-start boundary** — never one per tick (§53/§71). Deterministic and fully
//  testable without UserNotifications (§55).
//

import Foundation

/// Builds the notifications for a session's upcoming transitions.
///
/// ## What is scheduled
/// For a session whose current interval `c` ends at `currentIntervalEnd`, one
/// notification is scheduled for the **start of each later interval** `j` (`c < j`),
/// firing at the end of interval `j-1`. Announcing the *next* interval means the
/// notification that fires when focus ends says "Short break", and the one that fires
/// when a break ends says "Time to focus" (§12/§21).
///
/// Because the existing lifecycle seam does not emit on an automatic interval advance
/// (only on start/pause/resume/skip/stop/complete), the whole remaining timeline is
/// scheduled ahead of time so transitions still fire when the app is backgrounded or
/// closed (§22, ADR-040). The count is bounded by the session's interval count, so the
/// queue stays small and predictable (§72).
///
/// The **completion** notification is *not* pre-scheduled here; it is delivered from
/// the `.completed` lifecycle event via `completionDescriptor(...)` so it can never be
/// duplicated and never fires stale after an early finish (§30/§32, ADR-041).
nonisolated enum NotificationScheduleBuilder {

    /// The upcoming interval-start notifications permitted by `preferences`.
    static func upcomingDescriptors(
        for snapshot: NotificationSessionSnapshot,
        preferences: NotificationPreferences
    ) -> [NotificationDescriptor] {
        let intervals = snapshot.intervals
        let current = snapshot.currentIndex
        guard intervals.contains(where: { $0.index == current }) else { return [] }

        var descriptors: [NotificationDescriptor] = []
        // `boundaryEnd` starts at the current interval's authoritative end and grows by
        // each subsequent interval's duration, so every fire date is anchored to the
        // engine's timeline with no drift.
        var boundaryEnd = snapshot.currentIntervalEnd

        for interval in intervals where interval.index > current {
            let announcement = announcement(forStartOf: interval, in: snapshot)
            let category = announcement.category
            if preferences.allows(category) {
                descriptors.append(NotificationDescriptor(
                    identifier: NotificationIdentifier.transition(
                        sessionID: snapshot.sessionID, intervalIndex: interval.index),
                    content: NotificationContentGenerator.content(for: announcement),
                    fireDate: boundaryEnd,
                    category: category,
                    sound: preferences.sound,
                    showsActions: preferences.actionsEnabled,
                    sessionID: snapshot.sessionID
                ))
            }
            boundaryEnd = boundaryEnd.addingTimeInterval(interval.duration)
        }
        return descriptors
    }

    /// The immediate completion notification, or nil if completion notifications are
    /// disabled. Delivered from the `.completed` event (never pre-scheduled).
    static func completionDescriptor(
        for snapshot: NotificationSessionSnapshot,
        preferences: NotificationPreferences
    ) -> NotificationDescriptor? {
        guard preferences.allows(.sessionCompleted) else { return nil }
        let announcement = NotificationAnnouncement.sessionCompleted(
            task: snapshot.taskName, focusCount: snapshot.totalFocusCount)
        return NotificationDescriptor(
            identifier: NotificationIdentifier.completion(sessionID: snapshot.sessionID),
            content: NotificationContentGenerator.content(for: announcement),
            fireDate: nil, // immediate
            category: .sessionCompleted,
            sound: preferences.sound,
            showsActions: preferences.actionsEnabled,
            sessionID: snapshot.sessionID
        )
    }

    // MARK: Announcement mapping

    /// The announcement describing the *start* of `interval`, using the engine's plan
    /// (never Pomodoro rules re-derived here — the plan already encodes long breaks,
    /// §73).
    private static func announcement(
        forStartOf interval: NotificationSessionSnapshot.Interval,
        in snapshot: NotificationSessionSnapshot
    ) -> NotificationAnnouncement {
        switch interval.phase {
        case .focus:
            return .focus(task: snapshot.taskName,
                          duration: interval.duration,
                          configurationName: interval.configurationName)
        case .shortBreak:
            return .shortBreak(task: snapshot.taskName, duration: interval.duration)
        case .longBreak:
            // Focus sessions completed before this long break = focus intervals that
            // sit before it in the plan.
            let completed = snapshot.intervals
                .filter { $0.phase == .focus && $0.index < interval.index }
                .count
            return .longBreak(task: snapshot.taskName, completedFocusCount: completed)
        }
    }
}
