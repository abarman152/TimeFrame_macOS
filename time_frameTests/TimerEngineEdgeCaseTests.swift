//
//  TimerEngineEdgeCaseTests.swift
//  time_frameTests
//
//  Boundary conditions.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Timer edge cases")
struct TimerEngineEdgeCaseTests {

    @Test("Very short (1s) durations still transition correctly")
    func veryShortDurations() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 1, short: 1, long: 1, before: 4, total: 1), clock: clock)
        engine.start()
        clock.advance(by: 1)
        engine.synchronize()
        #expect(engine.currentPhase == .shortBreak)
        clock.advance(by: 1)
        engine.synchronize()
        #expect(engine.state == .completed)
    }

    @Test("Durations passed as zero are clamped and remain runnable")
    func zeroDurationClamped() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 0, short: 0, long: 0, before: 4, total: 1), clock: clock)
        engine.start()
        expectClose(engine.remaining, PomodoroConfigurationSnapshot.minimumDuration)
        clock.advance(by: PomodoroConfigurationSnapshot.minimumDuration)
        engine.synchronize()
        #expect(engine.currentPhase == .shortBreak)
    }

    @Test("Single-session configuration completes after focus + break")
    func singleSessionCompletes() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, short: 5, before: 4, total: 1), clock: clock)
        engine.start()
        clock.advance(by: 10); engine.synchronize()
        #expect(engine.currentPhase == .shortBreak)
        clock.advance(by: 5); engine.synchronize()
        #expect(engine.state == .completed)
        #expect(engine.completedIntervals.count == 2)
    }

    @Test("Multiple sessions produce the expected interval count")
    func multipleSessionsCount() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(total: 6), clock: clock)
        #expect(engine.plan.count == 12) // 6 focus + 6 breaks
        #expect(engine.totalFocusSessions == 6)
    }

    @Test("Completing the final interval moves to completed, not to a phantom interval")
    func finalIntervalCompletes() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, short: 5, long: 15, before: 4, total: 2), clock: clock)
        engine.start()
        clock.advance(by: 1000)
        engine.synchronize()
        #expect(engine.state == .completed)
        #expect(engine.currentInterval == nil)
        expectClose(engine.remaining, 0)
    }

    @Test("Pause immediately before completion then resume finishes the interval")
    func pauseNearCompletion() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, short: 5), clock: clock)
        engine.start()
        clock.advance(by: 9.9)
        engine.pause()
        expectClose(engine.remaining, 0.1)
        engine.resume()
        clock.advance(by: 0.1)
        engine.synchronize()
        #expect(engine.currentPhase == .shortBreak)
    }

    @Test("Resuming an interval paused exactly at zero completes it")
    func pauseAtZeroThenResume() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, short: 5), clock: clock)
        engine.start()
        clock.advance(by: 10)
        engine.pause()             // remaining is exactly 0
        expectClose(engine.remaining, 0)
        engine.resume()            // resume re-synchronizes
        #expect(engine.currentPhase == .shortBreak)
    }

    @Test("Restart after partial progress restores the full duration")
    func restartAfterPartialProgress() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, short: 5, total: 2), clock: clock)
        engine.start()
        clock.advance(by: 7)
        engine.restart()
        expectClose(engine.remaining, 10)
        // The rest of the plan is intact.
        #expect(engine.plan.count == 4)
        #expect(engine.currentIndex == 0)
    }

    @Test("reset() returns a finished engine to idle with the same plan")
    func resetReturnsToIdle() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(total: 1), clock: clock)
        engine.start()
        clock.advance(by: 1000); engine.synchronize()
        #expect(engine.state == .completed)
        engine.reset()
        #expect(engine.state == .idle)
        #expect(engine.currentIndex == 0)
        #expect(engine.completedIntervals.isEmpty)
        #expect(engine.plan.count == 2)
    }

    @Test("load() replaces the plan while idle and is ignored while running")
    func loadRespectsActiveState() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(total: 1), clock: clock)
        engine.load(plan: IntervalPlan(configuration: makeConfig(total: 3)))
        #expect(engine.plan.count == 6)

        engine.start()
        engine.load(plan: IntervalPlan(configuration: makeConfig(total: 1)))
        #expect(engine.plan.count == 6) // unchanged while active
    }
}
