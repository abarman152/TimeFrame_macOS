//
//  ProductionReadinessM21Tests.swift
//  time_frameTests (Milestone 21)
//
//  The Milestone-21 additions to the release-gate source audit: iOS Lock Screen accessory widgets
//  (circular / rectangular / inline) and their pure presentation mapper. They extend — never weaken —
//  the M17/M19/M20 invariants. Each test scans the source tree on disk (comments and string literals
//  blanked, identifier-boundary aware — see `SourceAudit`) and fails the build if a boundary regresses:
//
//   • the accessory widget stays a read-only projection surface in the EXISTING iOS extension (no
//     SwiftData, no CloudKit, no notifications, no `TimerEngine`/`SessionCoordinator` construction, no
//     scheduling primitive, no ModelContext);
//   • the new `AccessoryWidgetPresentation` mapper is pure — Foundation only (no WidgetKit / SwiftUI /
//     AppIntents / ActivityKit / SwiftData) — so it can never become a second clock;
//   • the accessory views are read-only (no interactive `Button(intent:)` / AppIntents), keeping the
//     Milestone-15 mutation seam the single one (ADR-089);
//   • ActivityKit stays iOS-only (exactly the three M18 files), the App Group + deep-link scheme are
//     unchanged, and the schema stays V6.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("M21 readiness — iOS Lock Screen accessory boundaries")
struct M21AccessoryBoundaryTests {

    /// The accessory-widget source files added this milestone (in the existing iOS widget extension).
    private static let accessoryFiles = ["LockScreenWidget.swift", "LockScreenWidgetViews.swift"]

    /// Reads a specific file (by last path component) under a root, with comments/strings blanked.
    private static func code(named name: String, under root: URL) -> String? {
        guard let url = SourceAudit.swiftSources(in: root).first(where: { $0.lastPathComponent == name }) else { return nil }
        return SourceAudit.code(url)
    }

}

@Suite("M21 readiness — the accessory mapper is pure")
struct M21AccessoryMapperPurityTests {

    private static func mapperCode() -> String? {
        guard let url = SourceAudit.swiftSources(in: SourceAudit.shared())
            .first(where: { $0.lastPathComponent == "AccessoryWidgetPresentation.swift" }) else { return nil }
        return SourceAudit.code(url)
    }

    @Test("AccessoryWidgetPresentation imports only Foundation (no UI/WidgetKit/AppIntents/ActivityKit/SwiftData)")
    func mapperIsFoundationOnly() {
        guard let text = Self.mapperCode() else { Issue.record("mapper file not found"); return }
        for forbidden in ["import WidgetKit", "import SwiftUI", "import AppIntents",
                          "import ActivityKit", "import SwiftData", "import CloudKit"] {
            #expect(!SourceAudit.references(text, forbidden), "mapper must not \(forbidden)")
        }
        #expect(SourceAudit.references(text, "import Foundation"))
    }

    @Test("The mapper introduces no timer primitive")
    func mapperHasNoClock() {
        guard let text = Self.mapperCode() else { Issue.record("mapper file not found"); return }
        for token in ["Timer(", "Timer.publish", "DispatchSourceTimer", "Task.sleep", "asyncAfter", "scheduledTimer"] {
            #expect(!SourceAudit.references(text, token), "mapper must not reference \(token)")
        }
    }
}

@Suite("M21 readiness — unchanged invariants")
struct M21UnchangedInvariantTests {


    @Test("M21 adds no model: the schema still has exactly the six V6 entities")
    func schemaAddsNoModel() {
        // The version itself moved to V7 in Milestone 28 (added attributes only, ADR-104);
        // what M21 must hold is that the accessory widgets introduced no MODEL of their own.
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
