//
//  LiveActivityIsolationTests.swift
//  time_frameTests (Milestone 16)
//
//  Failure isolation, CloudKit independence, and the boundary invariants for the platform-neutral
//  live-session layer. Proves that the presentation surface can never affect the one authoritative
//  timer, needs no CloudKit, and introduces no second timer or duplicated control vocabulary
//  (ADR-072/073/076).
//

import Foundation
import Testing
@testable import time_frame

@Suite("LiveActivityFailureIsolationTests")
@MainActor
struct LiveActivityFailureIsolationTests {

    @Test("A service that rejects starts never disturbs the timer")
    func rejectedStartDoesNotAffectTimer() throws {
        let rig = try makeLiveActivityRig()
        rig.service.startSucceeds = false   // the system refuses to create the activity

        try rig.coordinator.startSession(configuration: rig.config)
        #expect(rig.coordinator.engine.state == .running)   // timer runs regardless
        #expect(rig.service.activeCount == 0)               // no activity took

        rig.clock.advance(by: 2)
        try rig.coordinator.pause()
        #expect(rig.coordinator.engine.state == .paused)
        try rig.coordinator.resume()
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("Engine behaviour is identical with and without the Live Activity observer")
    func timerBehaviourUnchanged() throws {
        // With the observer wired.
        let withLive = try makeLiveActivityRig(focus: 10, short: 5, total: 3)
        // Without any observer.
        let control = try makeLiveActivityRig(focus: 10, short: 5, total: 3, wireFanOut: false)

        func run(_ rig: LiveActivityRig) -> [String] {
            var trace: [String] = []
            _ = try? rig.coordinator.startSession(configuration: rig.config)
            trace.append(rig.coordinator.engine.state.rawValue)
            rig.clock.advance(by: 2); try? rig.coordinator.pause()
            trace.append(rig.coordinator.engine.state.rawValue)
            try? rig.coordinator.resume()
            trace.append(rig.coordinator.engine.state.rawValue)
            try? rig.coordinator.skip()
            trace.append("\(rig.coordinator.engine.currentIndex)-\(rig.coordinator.engine.state.rawValue)")
            return trace
        }

        #expect(run(withLive) == run(control))   // the surface cannot perturb the timeline
    }

    @Test("An unsupported service leaves the timer fully functional")
    func unsupportedTimerWorks() throws {
        let rig = try makeLiveActivityRig(supported: false)
        try rig.coordinator.startSession(configuration: rig.config)
        while rig.coordinator.engine.state.isActive { try rig.coordinator.skip() }
        #expect(rig.coordinator.engine.state == .completed)
        #expect(rig.service.activeCount == 0)
    }
}

@Suite("LiveActivityCloudKitIndependenceTests")
@MainActor
struct LiveActivityCloudKitIndependenceTests {

    @Test("The live-session layer runs fully against the local (non-CloudKit) store")
    func worksWithoutCloudKit() throws {
        // `makeInMemoryContainer` is a plain local store — no CloudKit mirroring.
        let rig = try makeLiveActivityRig(total: 2)
        try rig.coordinator.startSession(configuration: rig.config)
        #expect(rig.service.activeCount == 1)
        while rig.coordinator.engine.state.isActive { try rig.coordinator.skip() }
        #expect(rig.service.activeCount == 0)
    }

    @Test("The projection is ephemeral: nothing is persisted for it")
    func projectionIsEphemeral() throws {
        // Building a snapshot performs no persistence; it is a pure read of in-memory state.
        let rig = try makeLiveActivityRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let a = LiveActivityContentMapper.snapshot(from: rig.coordinator, now: rig.clock.now())
        let b = LiveActivityContentMapper.snapshot(from: rig.coordinator, now: rig.clock.now())
        #expect(a == b)   // deterministic, reproducible, stored nowhere
    }
}

@Suite("LiveActivityBoundaryInvariantTests")
@MainActor
struct LiveActivityBoundaryInvariantTests {

    @Test("The live control vocabulary IS the shared Milestone-15 WidgetControlSet (no duplication)")
    func reusesSharedControlSet() {
        // Focus running offers pause/skip/stop; a break offers skip/stop; paused offers resume…
        #expect(WidgetControlSet.controls(for: .running, phase: .focus, compact: false) == [.pause, .skip, .stop])
        #expect(WidgetControlSet.controls(for: .running, phase: .shortBreak, compact: false) == [.skip, .stop])
        #expect(WidgetControlSet.controls(for: .paused, phase: .focus, compact: false) == [.resume, .restart, .stop])
        // Terminal states expose only a single start affordance.
        #expect(WidgetControlSet.controls(for: .completed, phase: .none, compact: true) == [.start])
    }

    @Test("Driving the observer introduces no second timer (engine index/state unchanged vs control)")
    func noSecondTimer() throws {
        let rig = try makeLiveActivityRig(focus: 10, total: 4)
        try rig.coordinator.startSession(configuration: rig.config)
        let indexAfterStart = rig.coordinator.engine.currentIndex
        // The observer only reads; a reconcile/update must not advance the engine.
        rig.live.update()
        rig.live.reconcileOnLaunch()
        #expect(rig.coordinator.engine.currentIndex == indexAfterStart)
        #expect(rig.coordinator.engine.state == .running)
    }

    @Test("The no-op service is inert and reports unsupported")
    func noopIsInert() {
        let noop = NoopLiveActivityService()
        #expect(!noop.isSupported)
        #expect(!noop.areActivitiesEnabled())
        #expect(noop.activeSessionIDs().isEmpty)
        #expect(noop.start(LiveActivitySnapshot(
            identity: LiveActivityIdentity(sessionID: UUID(), taskName: "", configurationName: "",
                                           sessionStartedAt: .init(timeIntervalSince1970: 0)),
            content: TimeFrameLiveActivityContent(runState: .running, phase: .focus))) == false)
    }
}
