//
//  NotificationScheduleBuilderTests.swift
//  time_frameTests
//
//  The pure planner schedules exactly one notification per upcoming interval-start
//  boundary — never one per tick — anchored to the engine's authoritative timeline
//  (§55/§71/§72). Fully deterministic; no UserNotifications.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Notification schedule builder")
struct NotificationScheduleBuilderTests {

    private let start = Date(timeIntervalSince1970: 2_000_000)

    /// A snapshot for a full Pomodoro-style plan: focus/break pairs.
    private func snapshot(
        focus: TimeInterval = 25 * 60,
        short: TimeInterval = 5 * 60,
        long: TimeInterval = 15 * 60,
        totalFocus: Int = 4,
        longEvery: Int = 4,
        currentIndex: Int = 0,
        task: String = "Deep Work",
        config: String = "Classic"
    ) -> NotificationSessionSnapshot {
        var intervals: [NotificationSessionSnapshot.Interval] = []
        var index = 0
        for focusNumber in 1...totalFocus {
            intervals.append(.init(index: index, phase: .focus, duration: focus, configurationName: config))
            index += 1
            let isLong = focusNumber % longEvery == 0
            intervals.append(.init(index: index, phase: isLong ? .longBreak : .shortBreak,
                                   duration: isLong ? long : short, configurationName: ""))
            index += 1
        }
        return NotificationSessionSnapshot(
            sessionID: UUID(), taskName: task, currentIndex: currentIndex,
            currentIntervalEnd: start.addingTimeInterval(focus), intervals: intervals)
    }

    // MARK: One request per boundary (§55)

    @Test("A single-focus session schedules exactly one upcoming transition")
    func singleFocusOneTransition() {
        // Plan: [focus, shortBreak]. The only upcoming interval start is the break.
        let snap = snapshot(totalFocus: 1)
        let descriptors = NotificationScheduleBuilder.upcomingDescriptors(
            for: snap, preferences: .default)
        #expect(descriptors.count == 1)
        #expect(descriptors.first?.category == .shortBreakStarted)
        // It fires exactly at the current interval's authoritative end.
        #expect(descriptors.first?.fireDate == snap.currentIntervalEnd)
    }

    @Test("A full session schedules one transition per later interval, never per tick")
    func fullSessionOnePerBoundary() {
        let snap = snapshot(totalFocus: 4) // 8 intervals, current 0
        let descriptors = NotificationScheduleBuilder.upcomingDescriptors(
            for: snap, preferences: .default)
        // Intervals 1...7 each get a start notification; interval 0 is current, and the
        // final boundary (end of interval 7) is completion, not pre-scheduled.
        #expect(descriptors.count == 7)
        // The last long break is announced with the long-break category.
        #expect(descriptors.contains { $0.category == .longBreakStarted })
    }

    @Test("Fire dates are cumulative along the authoritative timeline")
    func cumulativeFireDates() {
        let snap = snapshot(focus: 100, short: 20, totalFocus: 2, longEvery: 4)
        // Plan: focus(100), short(20), focus(100), short(20). current 0, end at +100.
        let descriptors = NotificationScheduleBuilder.upcomingDescriptors(
            for: snap, preferences: .default).sorted { ($0.fireDate ?? .distantPast) < ($1.fireDate ?? .distantPast) }
        #expect(descriptors.count == 3)
        // boundary 1: end of focus0 = +100 (short break starts)
        #expect(descriptors[0].fireDate == start.addingTimeInterval(100))
        // boundary 2: +100 + 20 = +120 (focus1 starts)
        #expect(descriptors[1].fireDate == start.addingTimeInterval(120))
        // boundary 3: +120 + 100 = +220 (last short break starts)
        #expect(descriptors[2].fireDate == start.addingTimeInterval(220))
    }

    // MARK: Preferences gating

    @Test("Disabling a category removes exactly those notifications")
    func categoryGating() {
        let snap = snapshot(totalFocus: 4)
        var prefs = NotificationPreferences.default
        prefs.shortBreakStarted = false
        let descriptors = NotificationScheduleBuilder.upcomingDescriptors(for: snap, preferences: prefs)
        #expect(descriptors.allSatisfy { $0.category != .shortBreakStarted })
        // Focus starts and the long break are still scheduled.
        #expect(descriptors.contains { $0.category == .focusStarted })
        #expect(descriptors.contains { $0.category == .longBreakStarted })
    }

    @Test("Long break reports the number of focus sessions completed before it")
    func longBreakCount() {
        let snap = snapshot(totalFocus: 4)
        let longBreak = NotificationScheduleBuilder.upcomingDescriptors(for: snap, preferences: .default)
            .first { $0.category == .longBreakStarted }
        #expect(longBreak?.body.contains("4 focus sessions") == true)
    }

    // MARK: Identity (§34)

    @Test("Identifiers are namespaced by session and interval, and stable")
    func stableIdentifiers() {
        let snap = snapshot(totalFocus: 1)
        let descriptor = NotificationScheduleBuilder.upcomingDescriptors(for: snap, preferences: .default).first
        #expect(descriptor?.identifier == NotificationIdentifier.transition(sessionID: snap.sessionID, intervalIndex: 1))
        #expect(descriptor?.identifier.hasPrefix(NotificationIdentifier.sessionPrefix(snap.sessionID)) == true)
    }

    // MARK: Completion (§30)

    @Test("The completion descriptor is immediate and gated by its preference")
    func completionDescriptor() {
        let snap = snapshot(totalFocus: 4)
        let completion = NotificationScheduleBuilder.completionDescriptor(for: snap, preferences: .default)
        #expect(completion?.fireDate == nil) // immediate, never pre-scheduled
        #expect(completion?.category == .sessionCompleted)
        #expect(completion?.body.contains("4 focus sessions completed") == true)
        #expect(completion?.identifier == NotificationIdentifier.completion(sessionID: snap.sessionID))

        var prefs = NotificationPreferences.default
        prefs.sessionCompleted = false
        #expect(NotificationScheduleBuilder.completionDescriptor(for: snap, preferences: prefs) == nil)
    }

    @Test("Nothing is scheduled from a mid-plan current index for already-past intervals")
    func midPlanNoPastScheduling() {
        // current index 4 (a focus) of an 8-interval plan → only intervals 5,6,7 remain.
        let snap = snapshot(totalFocus: 4, currentIndex: 4)
        let descriptors = NotificationScheduleBuilder.upcomingDescriptors(for: snap, preferences: .default)
        #expect(descriptors.count == 3)
        #expect(descriptors.allSatisfy { descriptor in
            // No descriptor announces an interval at or before the current one.
            !descriptor.identifier.contains(".0.transition")
        })
    }
}
