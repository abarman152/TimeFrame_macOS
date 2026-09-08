//
//  LiveActivityTestSupport.swift
//  time_frameTests (Milestone 16)
//
//  Deterministic support for the Live Activity tests: a fake `LiveActivityService` that records
//  every call and tracks "running" activities in memory, plus a rig that wires a real
//  `SessionCoordinator` (mock clock, heartbeat off) to a `LiveActivityCoordinator` exactly as the
//  app *would* wire them for a supported platform. No ActivityKit runtime is ever required — the
//  whole live-session core is platform-neutral, so its lifecycle/recovery/duplicate-prevention
//  logic is exercised entirely through the fake.
//

import Foundation
import SwiftData
@testable import time_frame

/// Records Live Activity operations and simulates the system's set of running activities.
@MainActor
final class FakeLiveActivityService: LiveActivityService {

    /// A recorded call, for order-sensitive assertions.
    enum Call: Equatable {
        case start(UUID)
        case update(UUID)
        case end(UUID)
        case endAll
    }

    /// Whether the (pretend) platform supports Live Activities.
    var supported: Bool
    /// Whether the user has (pretend) authorized Live Activities.
    var enabled: Bool
    /// When `false`, `start` records the call but the activity does not "take" — simulating the
    /// system rejecting a request. The coordinator must handle this without crashing.
    var startSucceeds: Bool = true

    private(set) var calls: [Call] = []
    private(set) var active: [UUID: LiveActivitySnapshot] = [:]

    init(supported: Bool = true, enabled: Bool = true, seeded: [LiveActivitySnapshot] = []) {
        self.supported = supported
        self.enabled = enabled
        for snapshot in seeded { active[snapshot.sessionID] = snapshot }
    }

    var isSupported: Bool { supported }
    func areActivitiesEnabled() -> Bool { enabled }
    func activeSessionIDs() -> [UUID] { Array(active.keys) }

    @discardableResult
    func start(_ snapshot: LiveActivitySnapshot) -> Bool {
        calls.append(.start(snapshot.sessionID))
        // Idempotent: never a second activity for the same session id.
        if active[snapshot.sessionID] != nil { return true }
        guard startSucceeds else { return false }
        active[snapshot.sessionID] = snapshot
        return true
    }

    func update(_ snapshot: LiveActivitySnapshot) {
        calls.append(.update(snapshot.sessionID))
        if active[snapshot.sessionID] != nil { active[snapshot.sessionID] = snapshot }
    }

    func end(sessionID: UUID, finalContent: TimeFrameLiveActivityContent?, dismissal: LiveActivityDismissal) {
        calls.append(.end(sessionID))
        active[sessionID] = nil
    }

    func endAll(dismissal: LiveActivityDismissal) {
        calls.append(.endAll)
        active.removeAll()
    }

    // MARK: Assertions helpers

    /// The number of activities currently "running".
    var activeCount: Int { active.count }

    /// The single running activity's session id, if exactly one exists.
    var soleActiveID: UUID? { active.count == 1 ? active.keys.first : nil }

    /// The most recent snapshot recorded for a session, if it is running.
    func snapshot(for id: UUID) -> LiveActivitySnapshot? { active[id] }

    /// Seeds a stale "already running" activity (e.g. one left over from before a relaunch), so a
    /// reconcile has something to converge/clear. Does not record a call.
    func seedStale(_ id: UUID) {
        active[id] = LiveActivitySnapshot(
            identity: LiveActivityIdentity(sessionID: id, taskName: "stale", configurationName: "",
                                           sessionStartedAt: Date(timeIntervalSince1970: 0)),
            content: TimeFrameLiveActivityContent(runState: .running, phase: .focus)
        )
    }
}

/// A wired rig: a real coordinator driven by a mock clock (heartbeat off) with a
/// `LiveActivityCoordinator` observing it through the app's fan-out shape.
@MainActor
struct LiveActivityRig {
    let container: ModelContainer
    let clock: MockTimeSource
    let coordinator: SessionCoordinator
    let live: LiveActivityCoordinator
    let service: FakeLiveActivityService
    let preferences: LiveActivityPreferencesStore
    let config: PomodoroConfiguration
}

@MainActor
func makeLiveActivityRig(
    focus: TimeInterval = 10,
    short: TimeInterval = 5,
    long: TimeInterval = 15,
    before: Int = 4,
    total: Int = 4,
    supported: Bool = true,
    enabled: Bool = true,
    wireFanOut: Bool = true
) throws -> LiveActivityRig {
    let container = try makeInMemoryContainer()
    let clock = MockTimeSource()
    let coordinator = makeCoordinator(container, clock: clock)
    let config = try insertConfiguration(
        container, focus: focus, short: short, long: long, before: before, total: total)
    let preferences = LiveActivityPreferencesStore(defaults: makeScratchDefaults())
    let service = FakeLiveActivityService(supported: supported, enabled: enabled)
    let live = LiveActivityCoordinator(
        session: coordinator,
        service: service,
        preferences: preferences,
        now: { clock.now() }
    )
    if wireFanOut {
        // Mirror the app's fan-out shape (weak, so the closure never keeps the coordinator alive).
        coordinator.onLifecycleEvent = { [weak live] event in live?.handle(event) }
        coordinator.onMeaningfulTransition = { [weak live] in live?.update() }
    }
    return LiveActivityRig(
        container: container, clock: clock, coordinator: coordinator,
        live: live, service: service, preferences: preferences, config: config
    )
}
