//
//  LiveActivityRecoveryTests.swift
//  time_frameTests (Milestone 16)
//
//  Launch/recovery reconciliation and duplicate prevention for the platform-neutral
//  `LiveActivityCoordinator`. Proves the surface converges to exactly one activity for a recovered
//  running/paused session, ends stale/foreign activities, and never resurrects a terminal or
//  absent session — the core of ADR-073. The M13 device-origin policy is honoured: reconcile acts
//  only on this device's `activeSession`, so a foreign session never gains a controllable activity.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("LiveActivityRecoveryTests")
@MainActor
struct LiveActivityRecoveryTests {

    @Test("Recovery with a matching stale activity converges to exactly one, same session")
    func convergesToMatching() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config)
        let id = try #require(rig.coordinator.activeSession?.id)
        rig.service.seedStale(id)          // the activity that survived the relaunch

        rig.live.reconcileOnLaunch()
        #expect(rig.service.soleActiveID == id)
    }

    @Test("Recovery ends a foreign/stale activity and starts the one for the live session")
    func endsStaleStartsCurrent() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config)
        let id = try #require(rig.coordinator.activeSession?.id)
        rig.service.seedStale(UUID())      // a stale activity for a different session

        rig.live.reconcileOnLaunch()
        #expect(rig.service.soleActiveID == id)   // stale ended, current present — exactly one
    }

    @Test("A paused recovered session reconciles to exactly one paused activity")
    func pausedReconciles() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 2)
        try rig.coordinator.pause()
        let id = try #require(rig.coordinator.activeSession?.id)

        rig.live.reconcileOnLaunch()
        #expect(rig.service.soleActiveID == id)
        #expect(rig.service.snapshot(for: id)?.content.runState == .paused)
    }

    @Test("A completed session clears any stale activity on reconcile")
    func completedClears() throws {
        let rig = try makeLiveActivityRig(total: 1, wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config)
        while rig.coordinator.engine.state.isActive { try rig.coordinator.skip() }
        rig.service.seedStale(UUID())

        rig.live.reconcileOnLaunch()
        #expect(rig.service.activeCount == 0)
    }

    @Test("An interrupted recovered session clears stale activities and starts none")
    func interruptedClears() throws {
        // Craft an unrecoverable running session, then recover on a fresh coordinator → interrupted.
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container)
        let now = Date(timeIntervalSince1970: 2_000_000)
        let session = FocusSession(taskName: "broken", configuration: config, status: .running, startedAt: now)
        session.currentIntervalIndex = 0
        let interval = SessionInterval(phase: .focus, plannedDuration: 10, order: 0)
        interval.status = .running
        interval.startedAt = now
        interval.targetEndAt = nil     // corruption → interrupt
        session.intervals.append(interval)
        container.mainContext.insert(session)
        try container.mainContext.save()

        let clock = MockTimeSource()
        let coordinator = makeCoordinator(container, clock: clock)
        #expect(try coordinator.recover() == false)
        #expect(coordinator.recoveryOutcome == .interrupted)

        let service = FakeLiveActivityService()
        service.seedStale(UUID())
        let live = LiveActivityCoordinator(
            session: coordinator,
            service: service,
            preferences: LiveActivityPreferencesStore(defaults: makeScratchDefaults()),
            now: { clock.now() }
        )
        live.reconcileOnLaunch()
        #expect(service.activeCount == 0)   // never starts an activity for an interrupted session
    }

    @Test("Idle with a stale activity (e.g. a foreign device's session) clears and starts none")
    func idleClearsStale() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        rig.service.seedStale(UUID())      // stale/foreign; no local active session
        rig.live.reconcileOnLaunch()
        #expect(rig.service.activeCount == 0)   // device-origin: no local session → no activity
    }

    @Test("Disabled preference clears everything on reconcile")
    func disabledClears() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.service.seedStale(rig.coordinator.activeSession!.id)
        rig.preferences.enabled = false

        rig.live.reconcileOnLaunch()
        #expect(rig.service.activeCount == 0)
    }
}

@Suite("LiveActivityDuplicatePreventionTests")
@MainActor
struct LiveActivityDuplicatePreventionTests {

    @Test("Repeated start events never create a second activity for the same session")
    func repeatedStartIdempotent() throws {
        let rig = try makeLiveActivityRig()
        try rig.coordinator.startSession(configuration: rig.config)
        let id = try #require(rig.coordinator.activeSession?.id)

        // Simulate the system delivering the start callback again (relaunch, repeated fan-out).
        rig.live.handle(.started(rig.coordinator.currentLifecycleContext()!))
        rig.live.handle(.started(rig.coordinator.currentLifecycleContext()!))

        #expect(rig.service.soleActiveID == id)   // still exactly one
    }

    @Test("Starting a session ends any stale activity for a different session first")
    func startEndsForeign() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        let foreign = UUID()
        rig.service.seedStale(foreign)

        // Now a real session starts; drive the start event through the coordinator manually.
        try rig.coordinator.startSession(configuration: rig.config)
        rig.live.handle(.started(rig.coordinator.currentLifecycleContext()!))

        let id = try #require(rig.coordinator.activeSession?.id)
        #expect(rig.service.soleActiveID == id)   // foreign ended, current present — exactly one
        #expect(rig.service.snapshot(for: foreign) == nil)
    }

    @Test("Reconcile after repeated relaunches stays at exactly one activity")
    func reconcileStaysSingle() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config)
        let id = try #require(rig.coordinator.activeSession?.id)
        rig.service.seedStale(id)

        rig.live.reconcileOnLaunch()
        rig.live.reconcileOnLaunch()
        rig.live.reconcileOnLaunch()
        #expect(rig.service.soleActiveID == id)
    }
}
