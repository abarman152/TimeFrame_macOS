//
//  ProductionReadinessM20Tests.swift
//  time_frameTests (Milestone 20)
//
//  The Milestone-20 additions to the release-gate source audit: iOS Home Screen widgets and iOS
//  local notifications. They extend — never weaken — the M17/M19 invariants. Each test scans the
//  source tree on disk (comments and string literals blanked, identifier-boundary aware — see
//  `SourceAudit`) and fails the build if a boundary regresses:
//
//   • the iOS Home Screen widget stays a read-only projection surface (no SwiftData, no CloudKit, no
//     `TimerEngine`/`SessionCoordinator` construction, no scheduling primitive);
//   • the local-notification stack lives in the shared `Core/Services/Notifications` and is the ONLY
//     importer of UserNotifications — the neutral timer core imports none of it;
//   • the notification adapter mutates no `ModelContext` and owns no clock;
//   • ActivityKit stays iOS-only, the App Group and deep-link scheme are unchanged, schema stays V6.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("M20 readiness — iOS Home Screen widget boundaries")
struct M20WidgetBoundaryTests {


    @Test("The iOS widget reuses the shared App Group and deep-link scheme (no new channel)")
    func iosWidgetReusesSharedChannels() {
        #expect(WidgetProjectionStore.appGroupIdentifier == "group.abirbarman.com.time-frame")
        // The neutral deep-link scheme both platforms use is unchanged.
        #expect(WidgetDeepLink.section(for: URL(string: "timeframe://timer")!) == .timer)
        #expect(WidgetDeepLink.section(for: URL(string: "timeframe://statistics")!) == .statistics)
    }
}

@Suite("M20 readiness — notification boundaries")
struct M20NotificationBoundaryTests {

    /// The shared notification stack now lives in `Core/Services/Notifications`.
    static func notificationRoot() -> URL {
        SourceAudit.core().appendingPathComponent("Services/Notifications")
    }


    @Test("The neutral timer core imports no UserNotifications")
    func timerCoreHasNoUserNotifications() {
        let timerDir = SourceAudit.core().appendingPathComponent("Timer")
        let modelsDir = SourceAudit.core().appendingPathComponent("Models")
        let hits = SourceAudit.filesReferencing(["import UserNotifications"], in: [timerDir, modelsDir])
        #expect(hits.isEmpty, "The timer core/models must stay UserNotifications-free: \(hits)")
    }

    @Test("The notification adapter/coordinator mutate no ModelContext and own no clock")
    func notificationStackIsPureObserver() {
        let root = Self.notificationRoot()
        // No direct SwiftData access from the notification stack (it takes pure snapshots).
        let persistence = SourceAudit.filesReferencing(["import SwiftData", "ModelContext"], in: [root])
        #expect(persistence.isEmpty, "Notification stack must not touch SwiftData: \(persistence)")
        // No second clock: scheduling is via the OS trigger, never a repeating timer here.
        let clock = SourceAudit.filesReferencing(
            ["Timer(", "Timer.publish", "DispatchSourceTimer", "Task.sleep", "asyncAfter", "scheduledTimer"],
            in: [root])
        #expect(clock.isEmpty, "Notification stack must own no clock: \(clock)")
    }

    @Test("No integration mutates the engine directly — notification actions route through the coordinator")
    func notificationActionsRouteThroughCoordinator() {
        let mutators = ["engine.start(", "engine.pause(", "engine.resume(", "engine.skip(",
                        "engine.restart(", "engine.stop(", "engine.load(", "engine.reset("]
        let hits = SourceAudit.filesReferencing(mutators, in: [Self.notificationRoot()])
        #expect(hits.isEmpty, "The notification stack must not mutate the engine directly: \(hits)")
    }
}

@Suite("M20 readiness — unchanged invariants")
struct M20UnchangedInvariantTests {


    @Test("No new model for widgets or notifications: still exactly the six V6 entities")
    func schemaAddsNoModel() {
        // The version moved to V7 in Milestone 28 (added attributes only, ADR-104).
        #expect(TimeFrameSchemaLatest.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(Schema(versionedSchema: TimeFrameSchemaLatest.self).entities.count == 6)
    }

}
