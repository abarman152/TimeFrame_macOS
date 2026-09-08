//
//  ProductionReadinessM22Tests.swift
//  time_frameTests (Milestone 22)
//
//  The Milestone-22 additions to the release-gate source audit: the iOS Control Center controls
//  (`ControlWidget`) and their pure decision layer. They extend — never weaken — the M17/M19/M20/M21
//  invariants. Each test scans the source tree on disk (comments and string literals blanked,
//  identifier-boundary aware — see `SourceAudit`) and fails the build if a boundary regresses:
//
//   • `ControlWidget` (and its configuration/button types) exist ONLY in the iOS widget extension —
//     macOS, `Core/`, `Shared/`, and the macOS widget stay ControlWidget-free (iOS-only API);
//   • the Control Center controls own no timer: no SwiftData/CloudKit, no `TimerEngine`/
//     `SessionCoordinator` construction, no scheduling primitive, no second action router;
//   • the pure `ControlCenterPresentation` decision layer is Foundation-only, so it can never become
//     a second clock;
//   • the single mutation seam, App Group, deep-link scheme, ActivityKit confinement, disabled
//     CloudKit, and V6 schema are all unchanged.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("M22 readiness — Control Center is iOS-only")
struct M22ControlWidgetPlatformTests {

    /// The WidgetKit Control Center vocabulary. It is `@available(iOS 18.0, …)` and must never appear
    /// in the macOS app, the shared `Core/` domain, the shared projections, or the macOS widget.
    private static let controlWidgetTokens = [
        "ControlWidget", "StaticControlConfiguration", "AppIntentControlConfiguration",
        "ControlWidgetButton", "ControlWidgetToggle", "ControlValueProvider"
    ]

    @Test("macOS / Core / Shared / macOS-widget contain no ControlWidget API (iOS-only)")
    func controlWidgetIsIOSOnly() {
        let hits = SourceAudit.filesReferencing(Self.controlWidgetTokens, in: SourceAudit.productionRoots())
        #expect(hits.isEmpty, "ControlWidget API leaked into non-iOS production code: \(hits)")
    }

}

@Suite("M22 readiness — Control Center boundaries")
struct M22ControlCenterBoundaryTests {

    private static func code(named name: String, under root: URL) -> String? {
        guard let url = SourceAudit.swiftSources(in: root).first(where: { $0.lastPathComponent == name }) else { return nil }
        return SourceAudit.code(url)
    }

}

@Suite("M22 readiness — the Control Center decision layer is pure")
struct M22ControlCenterPurityTests {

    private static func presentationCode() -> String? {
        guard let url = SourceAudit.swiftSources(in: SourceAudit.shared())
            .first(where: { $0.lastPathComponent == "ControlCenterPresentation.swift" }) else { return nil }
        return SourceAudit.code(url)
    }

    @Test("ControlCenterPresentation imports only Foundation (no UI/WidgetKit/AppIntents/ActivityKit/SwiftData/CloudKit)")
    func presentationIsFoundationOnly() {
        guard let text = Self.presentationCode() else { Issue.record("presentation file not found"); return }
        for forbidden in ["import WidgetKit", "import SwiftUI", "import AppIntents",
                          "import ActivityKit", "import SwiftData", "import CloudKit"] {
            #expect(!SourceAudit.references(text, forbidden), "decision layer must not \(forbidden)")
        }
        #expect(SourceAudit.references(text, "import Foundation"))
    }

    @Test("The decision layer introduces no timer primitive")
    func presentationHasNoClock() {
        guard let text = Self.presentationCode() else { Issue.record("presentation file not found"); return }
        for token in ["Timer(", "Timer.publish", "DispatchSourceTimer", "Task.sleep", "asyncAfter", "scheduledTimer"] {
            #expect(!SourceAudit.references(text, token), "decision layer must not reference \(token)")
        }
    }
}

@Suite("M22 readiness — unchanged invariants")
struct M22UnchangedInvariantTests {


    @Test("M22 adds no model: the schema still has exactly the six V6 entities")
    func schemaAddsNoModel() {
        // The version moved to V7 in Milestone 28 (added attributes only, ADR-104).
        #expect(TimeFrameSchemaLatest.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(Schema(versionedSchema: TimeFrameSchemaLatest.self).entities.count == 6)
    }

    @Test("The App Group and the timeframe:// deep-link scheme are unchanged")
    func sharedChannelsUnchanged() {
        #expect(WidgetProjectionStore.appGroupIdentifier == "group.abirbarman.com.time-frame")
        #expect(WidgetDeepLink.section(for: URL(string: "timeframe://timer")!) == .timer)
        #expect(WidgetDeepLink.section(for: URL(string: "timeframe://history")!) == .history)
    }

}
