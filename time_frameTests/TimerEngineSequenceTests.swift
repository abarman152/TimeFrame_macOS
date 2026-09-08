//
//  TimerEngineSequenceTests.swift
//  time_frameTests
//
//  End-to-end progression through a full session, plus authoritative-clock
//  behaviour (fast-forward through delayed ticks and system sleep).
//

import Foundation
import Testing
@testable import time_frame

@MainActor
@Suite("Session sequence & authoritative clock")
struct TimerEngineSequenceTests {

    /// Drives the engine to completion by advancing the clock past each planned
    /// end and synchronizing, returning the ordered outcome phases.
    private func runToCompletion(_ engine: TimerEngine, clock: MockTimeSource) {
        var guardCounter = 0
        while engine.state == .running, guardCounter < 1_000 {
            let remaining = engine.remaining
            clock.advance(by: remaining + 0.001)
            engine.synchronize()
            guardCounter += 1
        }
    }

    @Test("A full four-session run completes every interval in order")
    func fullRunOrder() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, short: 5, long: 15, before: 4, total: 4), clock: clock)
        engine.start()
        runToCompletion(engine, clock: clock)

        #expect(engine.state == .completed)
        let phases = engine.completedIntervals.map(\.phase)
        #expect(phases == [
            .focus, .shortBreak,
            .focus, .shortBreak,
            .focus, .shortBreak,
            .focus, .longBreak
        ])
        #expect(engine.completedIntervals.allSatisfy { $0.outcome == .completed })
    }

    @Test("The long break lands after the configured number of sessions")
    func longBreakPlacement() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(before: 2, total: 4), clock: clock)
        engine.start()
        runToCompletion(engine, clock: clock)
        let phases = engine.completedIntervals.map(\.phase)
        #expect(phases == [
            .focus, .shortBreak,
            .focus, .longBreak,
            .focus, .shortBreak,
            .focus, .longBreak
        ])
    }

    @Test("A single synchronize fast-forwards through intervals missed during sleep")
    func fastForwardThroughSleep() {
        let clock = MockTimeSource()
        // Plan total duration: (10+5)*4 with a long break = 10+5+10+5+10+5+10+15 = 70s
        let engine = makeEngine(makeConfig(focus: 10, short: 5, long: 15, before: 4, total: 4), clock: clock)
        engine.start()
        // Simulate the machine sleeping for well beyond the whole plan.
        clock.advance(by: 100)
        engine.synchronize()
        #expect(engine.state == .completed)
        #expect(engine.completedIntervals.count == 8)
    }

    @Test("A delayed tick completes multiple intervals at once without drift")
    func delayedTickChainsIntervals() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10, short: 5, long: 15, before: 4, total: 4), clock: clock)
        engine.start()
        // Jump past focus(10) + shortBreak(5) = 15s, landing 8s into focus #2.
        clock.advance(by: 23)
        engine.synchronize()
        #expect(engine.currentIndex == 2)
        #expect(engine.currentPhase == .focus)
        #expect(engine.completedIntervals.count == 2)
        // No drift: focus #2 ends at t=25, clock is at t=23 → 2s remain.
        expectClose(engine.remaining, 2)
    }

    @Test("Remaining never goes negative even when the tick is late")
    func remainingNeverNegative() {
        let clock = MockTimeSource()
        let engine = makeEngine(makeConfig(focus: 10), clock: clock)
        engine.start()
        clock.advance(by: 999)
        #expect(engine.remaining >= 0)
    }
}
