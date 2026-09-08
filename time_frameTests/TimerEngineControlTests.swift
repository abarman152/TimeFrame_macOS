//
//  TimerEngineControlTests.swift
//  time_frameTests
//
//  start / pause / resume / stop / skip / restart behaviour.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Timer controls")
struct TimerEngineControlTests {

    @Test("Start anchors the first interval to its full duration")
    func startAnchors() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10), clock: clock)
        engine.start()
        expectClose(engine.remaining, 10)
        clock.advance(by: 4)
        expectClose(engine.remaining, 6)
        expectClose(engine.elapsed, 4)
    }

    @Test("Pause preserves remaining time regardless of clock advance")
    func pausePreservesRemaining() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10), clock: clock)
        engine.start()
        clock.advance(by: 3)
        engine.pause()
        expectClose(engine.remaining, 7)
        // The clock keeps moving but the paused interval does not.
        clock.advance(by: 100)
        expectClose(engine.remaining, 7)
    }

    @Test("Resume continues from the preserved remaining time")
    func resumeContinues() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, short: 5), clock: clock)
        engine.start()
        clock.advance(by: 3)
        engine.pause()
        clock.advance(by: 50) // time while paused must not count
        engine.resume()
        expectClose(engine.remaining, 7)
        clock.advance(by: 7)
        engine.synchronize()
        // Focus completed → advanced into the short break.
        #expect(engine.currentPhase == .shortBreak)
        #expect(engine.state == .running)
    }

    @Test("Stop records the in-progress interval as cancelled")
    func stopRecordsCancelled() {
        let clock = MockTimeSource()
        let engine = makeEngine(clock: clock)
        engine.start()
        clock.advance(by: 2)
        engine.stop()
        #expect(engine.state == .cancelled)
        #expect(engine.completedIntervals.count == 1)
        #expect(engine.completedIntervals.last?.outcome == .cancelled)
        #expect(engine.completedIntervals.last?.phase == .focus)
    }

    @Test("Skip during focus advances to the following break and preserves history")
    func skipDuringFocus() {
        let clock = MockTimeSource()
        let engine = makeEngine(clock: clock)
        engine.start()
        clock.advance(by: 2)
        engine.skip()
        #expect(engine.currentPhase == .shortBreak)
        #expect(engine.state == .running)
        #expect(engine.completedIntervals.count == 1)
        #expect(engine.completedIntervals.last?.outcome == .skipped)
        #expect(engine.completedIntervals.last?.phase == .focus)
    }

    @Test("Skip during a break advances to the next focus")
    func skipDuringBreak() {
        let clock = MockTimeSource()
        let engine = makeEngine(clock: clock)
        engine.start()
        engine.skip() // skip focus 1 → short break
        #expect(engine.currentPhase == .shortBreak)
        engine.skip() // skip short break → focus 2
        #expect(engine.currentPhase == .focus)
        #expect(engine.currentIndex == 2)
        #expect(engine.completedIntervals.count == 2)
    }

    @Test("Restart resets the current interval to its full duration")
    func restartResets() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10), clock: clock)
        engine.start()
        clock.advance(by: 6)
        expectClose(engine.remaining, 4)
        engine.restart()
        expectClose(engine.remaining, 10)
        #expect(engine.state == .running)
        #expect(engine.currentIndex == 0)
    }

    @Test("Restart while paused keeps the session paused with full remaining")
    func restartWhilePaused() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10), clock: clock)
        engine.start()
        clock.advance(by: 6)
        engine.pause()
        engine.restart()
        #expect(engine.state == .paused)
        expectClose(engine.remaining, 10)
        // Resuming then runs a full interval.
        engine.resume()
        clock.advance(by: 10)
        engine.synchronize()
        #expect(engine.currentPhase == .shortBreak)
    }

    @Test("Skip past the final interval completes the session")
    func skipPastEndCompletes() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(total: 1), clock: clock)
        engine.start()   // focus
        engine.skip()    // → short break
        engine.skip()    // → past end → completed
        #expect(engine.state == .completed)
    }
}
