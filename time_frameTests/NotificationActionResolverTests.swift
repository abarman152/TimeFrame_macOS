//
//  NotificationActionResolverTests.swift
//  time_frameTests
//
//  The pure safety rules for a received notification action (§40): an action for a
//  missing, mismatched, or finished session is ignored gracefully; a valid control is
//  routed. No engine, no UserNotifications.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Notification action resolver")
struct NotificationActionResolverTests {

    private let session = UUID()

    @Test("Open always activates the app, regardless of session state")
    func openAlwaysActivates() {
        let r1 = NotificationActionResolver.resolve(
            .init(action: .open, sessionID: nil), activeSessionID: nil, state: .idle)
        #expect(r1 == .activateApp)
        let r2 = NotificationActionResolver.resolve(
            .init(action: .open, sessionID: session), activeSessionID: session, state: .completed)
        #expect(r2 == .activateApp)
    }

    @Test("Pause is performed only while running")
    func pauseOnlyWhenRunning() {
        #expect(NotificationActionResolver.resolve(
            .init(action: .pause, sessionID: session), activeSessionID: session, state: .running)
            == .perform(.pause))
        #expect(NotificationActionResolver.resolve(
            .init(action: .pause, sessionID: session), activeSessionID: session, state: .paused)
            == .ignore(reason: "not running"))
    }

    @Test("Resume is performed only while paused")
    func resumeOnlyWhenPaused() {
        #expect(NotificationActionResolver.resolve(
            .init(action: .resume, sessionID: session), activeSessionID: session, state: .paused)
            == .perform(.resume))
        #expect(NotificationActionResolver.resolve(
            .init(action: .resume, sessionID: session), activeSessionID: session, state: .running)
            == .ignore(reason: "not paused"))
    }

    @Test("Skip and stop are performed for any active session")
    func skipAndStop() {
        #expect(NotificationActionResolver.resolve(
            .init(action: .skip, sessionID: session), activeSessionID: session, state: .running)
            == .perform(.skip))
        #expect(NotificationActionResolver.resolve(
            .init(action: .stop, sessionID: session), activeSessionID: session, state: .paused)
            == .perform(.stop))
    }

    @Test("An action for a different session is ignored")
    func mismatchedSessionIgnored() {
        let result = NotificationActionResolver.resolve(
            .init(action: .skip, sessionID: UUID()), activeSessionID: session, state: .running)
        #expect(result == .ignore(reason: "action for a different session"))
    }

    @Test("An action with no active session is ignored, not crashed")
    func noActiveSessionIgnored() {
        let result = NotificationActionResolver.resolve(
            .init(action: .pause, sessionID: session), activeSessionID: nil, state: .idle)
        #expect(result == .ignore(reason: "no active session"))
    }

    @Test("An action for a finished session is ignored")
    func finishedSessionIgnored() {
        let result = NotificationActionResolver.resolve(
            .init(action: .skip, sessionID: session), activeSessionID: session, state: .completed)
        #expect(result == .ignore(reason: "session is not active"))
    }
}
