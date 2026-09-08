//
//  TimerEngineStateTests.swift
//  time_frameTests
//
//  State-machine transitions.
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Timer state machine")
struct TimerEngineStateTests {

    @Test("Starts in idle")
    func startsIdle() {
        let engine = makeEngine(clock: MockTimeSource())
        #expect(engine.state == .idle)
        #expect(engine.currentIndex == 0)
    }

    @Test("Idle → Running on start")
    func idleToRunning() {
        let clock = MockTimeSource()
        let engine = makeEngine(clock: clock)
        engine.start()
        #expect(engine.state == .running)
        #expect(engine.currentPhase == .focus)
        expectClose(engine.remaining, 10)
    }

    @Test("Running → Paused on pause")
    func runningToPaused() {
        let clock = MockTimeSource()
        let engine = makeEngine(clock: clock)
        engine.start()
        engine.pause()
        #expect(engine.state == .paused)
    }

    @Test("Paused → Running on resume")
    func pausedToRunning() {
        let clock = MockTimeSource()
        let engine = makeEngine(clock: clock)
        engine.start()
        engine.pause()
        engine.resume()
        #expect(engine.state == .running)
    }

    @Test("Running → Completed after the whole plan elapses")
    func runningToCompleted() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(total: 1), clock: clock)
        engine.start()
        clock.advance(by: 10_000)
        engine.synchronize()
        #expect(engine.state == .completed)
    }

    @Test("Running → Cancelled on stop")
    func runningToCancelled() {
        let clock = MockTimeSource()
        let engine = makeEngine(clock: clock)
        engine.start()
        engine.stop()
        #expect(engine.state == .cancelled)
    }

    @Test("Invalid transitions are ignored")
    func invalidTransitionsIgnored() {
        let clock = MockTimeSource()
        let engine = makeEngine(clock: clock)

        // pause/resume/skip/restart/stop are no-ops while idle
        engine.pause();   #expect(engine.state == .idle)
        engine.resume();  #expect(engine.state == .idle)
        engine.skip();    #expect(engine.state == .idle)
        engine.restart(); #expect(engine.state == .idle)
        engine.stop();    #expect(engine.state == .idle)

        engine.start()
        // resume while running is a no-op
        engine.resume()
        #expect(engine.state == .running)

        // start while running is a no-op (does not restart the plan)
        engine.start()
        #expect(engine.currentIndex == 0)
    }
}
