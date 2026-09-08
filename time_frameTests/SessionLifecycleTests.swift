//
//  SessionLifecycleTests.swift
//  time_frameTests
//
//  End-to-end: driving the SessionCoordinator persists every meaningful
//  lifecycle transition into SwiftData (Milestone 2). Uses in-memory stores and
//  a deterministic mock clock; the background heartbeat is disabled.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@MainActor
@Suite("Session lifecycle persistence")
struct SessionLifecycleTests {

    @Test("Starting a session persists the session and its full interval plan")
    func startPersists() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container) // focus10/short5, total 4 → 8 intervals
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config, taskName: "Write"))

        #expect(session.status == .running)
        #expect(session.startedAt != nil)
        #expect(session.taskName == "Write")
        #expect(session.intervals.count == 8)

        let ordered = session.orderedIntervals
        #expect(ordered.map(\.order) == Array(0..<8))
        #expect(ordered[0].status == .running)
        #expect(ordered[0].startedAt != nil)
        #expect(ordered[0].targetEndAt != nil)
        #expect(ordered[1].status == .pending)
        #expect(session.configuration?.id == config.id)
    }

    @Test("Pausing persists the paused state and the frozen remaining")
    func pausePersists() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config))
        clock.advance(by: 3)
        try coordinator.pause()

        #expect(session.status == .paused)
        #expect(session.pausedAt != nil)
        let current = try #require(session.currentInterval)
        #expect(current.status == .paused)
        #expect(current.remainingAtPause != nil)
        expectClose(try #require(current.remainingAtPause), 7) // focus 10 − 3
    }

    @Test("Resuming persists the running state and clears the pause anchor")
    func resumePersists() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config))
        clock.advance(by: 3)
        try coordinator.pause()
        try coordinator.resume()

        #expect(session.status == .running)
        #expect(session.pausedAt == nil)
        let current = try #require(session.currentInterval)
        #expect(current.status == .running)
        #expect(current.remainingAtPause == nil)
        #expect(current.targetEndAt != nil)
    }

    @Test("An automatic interval transition is persisted on tick")
    func automaticTransitionPersists() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config))
        clock.advance(by: 10) // exactly the focus duration
        try coordinator.tick()

        let ordered = session.orderedIntervals
        #expect(ordered[0].status == .completed)
        #expect(ordered[0].endedAt != nil)
        #expect(ordered[1].status == .running)
        #expect(session.currentIntervalIndex == 1)
        #expect(session.intervals.count == 8) // no duplicate intervals created
    }

    @Test("Skipping persists the skipped interval and advances")
    func skipPersists() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config))
        clock.advance(by: 2)
        try coordinator.skip()

        let ordered = session.orderedIntervals
        #expect(ordered[0].status == .skipped)
        #expect(ordered[0].endedAt != nil)
        #expect(ordered[1].status == .running)
        #expect(session.currentIntervalIndex == 1)
    }

    @Test("Restarting resets the current interval in place without new rows")
    func restartResetsInPlace() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config))
        clock.advance(by: 4)
        try coordinator.restart()

        #expect(session.intervals.count == 8) // no attempt row added (ADR-011)
        #expect(session.currentIntervalIndex == 0)
        #expect(session.orderedIntervals[0].status == .running)
        expectClose(coordinator.engine.remaining, 10) // full duration again
    }

    @Test("Stopping persists a cancelled session and preserves completed intervals")
    func stopPreservesHistory() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config))
        clock.advance(by: 10)
        try coordinator.tick() // completes interval 0, runs interval 1
        clock.advance(by: 2)
        try coordinator.stop()

        let ordered = session.orderedIntervals
        #expect(session.status == .cancelled)
        #expect(session.endedAt != nil)
        #expect(ordered[0].status == .completed) // preserved, not deleted
        #expect(ordered[1].status == .cancelled) // in-progress recorded as cancelled
    }

    @Test("Completing every interval persists a completed session")
    func completionPersists() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        // total 1 → plan is [focus, short break]: 2 intervals.
        let config = try insertConfiguration(container, total: 1)
        let coordinator = makeCoordinator(container, clock: clock)

        let session = try #require(try coordinator.startSession(configuration: config))
        #expect(session.intervals.count == 2)
        clock.advance(by: 10)
        try coordinator.tick() // focus → short break
        clock.advance(by: 5)
        try coordinator.tick() // short break → completed

        #expect(coordinator.engine.state == .completed)
        #expect(session.status == .completed)
        #expect(session.endedAt != nil)
        #expect(session.orderedIntervals.allSatisfy { $0.status == .completed })
    }
}
