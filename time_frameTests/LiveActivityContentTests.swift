//
//  LiveActivityContentTests.swift
//  time_frameTests (Milestone 16)
//
//  The pure, platform-neutral live-session model: content mapping from authoritative state, the
//  static identity (a future `ActivityAttributes`), the run-state vocabulary, and the shared
//  presentation. All exercised with no ActivityKit runtime (ADR-072/076).
//

import Foundation
import Testing
@testable import time_frame

// MARK: - Presentation

@Suite("LiveActivityPresentationTests")
@MainActor
struct LiveActivityPresentationTests {

    private func content(_ phase: WidgetPhase, run: LiveActivityRunState = .running,
                         index: Int = 2, total: Int = 4) -> TimeFrameLiveActivityContent {
        TimeFrameLiveActivityContent(
            runState: run, phase: phase,
            phaseStartedAt: Date(timeIntervalSince1970: 100),
            phaseTargetEndAt: Date(timeIntervalSince1970: 160),
            sessionIndex: index, totalFocusSessions: total, completedFocusCount: 1,
            nextPhase: .shortBreak
        )
    }

    private func identity(task: String = "Write RFC", config: String = "Classic") -> LiveActivityIdentity {
        LiveActivityIdentity(sessionID: UUID(), taskName: task, configurationName: config,
                             sessionStartedAt: Date(timeIntervalSince1970: 0))
    }

    @Test("Focus content presents a title, symbol, progress, and a live countdown")
    func focusPresentation() {
        let p = LiveActivityPresentation(identity: identity(), content: content(.focus))
        #expect(p.phaseTitle == "Focus")
        #expect(p.symbolName == "brain.head.profile")
        #expect(p.progressText == "Session 2 of 4")
        #expect(p.showsCountdown)
        #expect(!p.isPaused)
        #expect(p.taskName == "Write RFC")
        #expect(p.accessibilityLabel.contains("Focus"))
        #expect(p.accessibilityLabel.contains("Write RFC"))
    }

    @Test("Break content shows no session-progress line and a break symbol")
    func breakPresentation() {
        let p = LiveActivityPresentation(identity: identity(), content: content(.shortBreak))
        #expect(p.phaseTitle == "Short Break")
        #expect(p.symbolName == "cup.and.saucer.fill")
        #expect(p.progressText == nil)   // progress shown only for focus
    }

    @Test("Paused content shows no countdown and marks paused")
    func pausedPresentation() {
        var c = content(.focus, run: .paused)
        c.phaseTargetEndAt = nil
        c.pausedRemainingSeconds = 42
        let p = LiveActivityPresentation(identity: identity(), content: c)
        #expect(p.isPaused)
        #expect(!p.showsCountdown)
        #expect(p.accessibilityLabel.contains("Paused"))
    }

    @Test("Terminal states present distinct titles and symbols")
    func terminalPresentation() {
        let completed = LiveActivityPresentation(identity: identity(),
            content: content(.none, run: .completed))
        #expect(completed.phaseTitle == "Session Complete")
        #expect(completed.symbolName == "checkmark.circle.fill")
        #expect(!completed.showsCountdown)

        let interrupted = LiveActivityPresentation(identity: identity(),
            content: content(.none, run: .interrupted))
        #expect(interrupted.phaseTitle == "Session Ended")
        #expect(interrupted.symbolName == "stop.circle")
    }

    @Test("Redacted identity hides task and configuration")
    func redactedIdentity() {
        let p = LiveActivityPresentation(identity: identity(task: "", config: ""), content: content(.focus))
        #expect(p.taskName == nil)
        #expect(p.configurationName == nil)
    }
}

// MARK: - Attributes (the static identity a future ActivityAttributes wraps)

@Suite("LiveActivityAttributesTests")
struct LiveActivityAttributesTests {

    @Test("Identity round-trips through Codable unchanged")
    func identityCodable() throws {
        let identity = LiveActivityIdentity(
            sessionID: UUID(), taskName: "Deep work", configurationName: "Focus 50/10",
            sessionStartedAt: Date(timeIntervalSince1970: 123_456)
        )
        let data = try JSONEncoder().encode(identity)
        let decoded = try JSONDecoder().decode(LiveActivityIdentity.self, from: data)
        #expect(decoded == identity)
    }

    @Test("Activity identity is keyed by the session id, never the task or configuration name")
    func identityKeyedBySession() {
        let id = UUID()
        let a = LiveActivityIdentity(sessionID: id, taskName: "A", configurationName: "X",
                                     sessionStartedAt: .init(timeIntervalSince1970: 0))
        let b = LiveActivityIdentity(sessionID: id, taskName: "B", configurationName: "Y",
                                     sessionStartedAt: .init(timeIntervalSince1970: 0))
        // Different labels, same session → same identity key (ADR-073).
        #expect(a.sessionID == b.sessionID)
        // The whole snapshot's identity key is the session id.
        let snapshot = LiveActivitySnapshot(
            identity: a,
            content: TimeFrameLiveActivityContent(runState: .running, phase: .focus)
        )
        #expect(snapshot.sessionID == id)
    }
}

// MARK: - Run state vocabulary

@Suite("LiveActivityStateTests")
struct LiveActivityStateTests {

    @Test("isActive / isTerminal partition the run states")
    func statePartition() {
        #expect(LiveActivityRunState.running.isActive)
        #expect(LiveActivityRunState.paused.isActive)
        #expect(!LiveActivityRunState.completed.isActive)
        #expect(!LiveActivityRunState.interrupted.isActive)
        #expect(LiveActivityRunState.completed.isTerminal)
        #expect(LiveActivityRunState.interrupted.isTerminal)
        #expect(!LiveActivityRunState.running.isTerminal)
    }

    @Test("Run state decodes defensively to .running on an unknown value")
    func defensiveDecode() throws {
        let json = Data(#""surprise""#.utf8)
        let decoded = try JSONDecoder().decode(LiveActivityRunState.self, from: json)
        #expect(decoded == .running)
    }

    @Test("Content round-trips through Codable unchanged")
    func contentCodable() throws {
        let c = TimeFrameLiveActivityContent(
            runState: .paused, phase: .focus,
            phaseStartedAt: Date(timeIntervalSince1970: 10),
            phaseTargetEndAt: nil, pausedRemainingSeconds: 90,
            sessionIndex: 3, totalFocusSessions: 5, completedFocusCount: 2,
            nextPhase: .longBreak, nextPhaseTargetEndAt: nil
        )
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(TimeFrameLiveActivityContent.self, from: data)
        #expect(decoded == c)
    }
}

// MARK: - Mapper (authoritative state → projection)

@Suite("LiveActivityMappingTests")
@MainActor
struct LiveActivityMappingTests {

    @Test("A running focus session maps to running focus content with frozen anchors")
    func mapsRunningFocus() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config, taskName: "Ship it")

        let snapshot = LiveActivityContentMapper.snapshot(from: rig.coordinator, now: rig.clock.now())
        let unwrapped = try #require(snapshot)
        #expect(unwrapped.identity.sessionID == rig.coordinator.activeSession?.id)
        #expect(unwrapped.identity.taskName == "Ship it")
        #expect(unwrapped.content.runState == .running)
        #expect(unwrapped.content.phase == .focus)
        #expect(unwrapped.content.phaseStartedAt != nil)
        #expect(unwrapped.content.phaseTargetEndAt != nil)
        #expect(unwrapped.content.totalFocusSessions == 4)
    }

    @Test("An idle coordinator maps to no snapshot")
    func idleMapsToNil() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        #expect(LiveActivityContentMapper.snapshot(from: rig.coordinator, now: rig.clock.now()) == nil)
    }

    @Test("A paused session freezes the remaining and drops the end anchor")
    func mapsPaused() throws {
        let rig = try makeLiveActivityRig(wireFanOut: false)
        try rig.coordinator.startSession(configuration: rig.config)
        rig.clock.advance(by: 3)
        try rig.coordinator.pause()

        let snapshot = try #require(LiveActivityContentMapper.snapshot(from: rig.coordinator, now: rig.clock.now()))
        #expect(snapshot.content.runState == .paused)
        #expect(snapshot.content.pausedRemainingSeconds != nil)
        #expect(snapshot.content.phaseTargetEndAt == nil)
    }
}
