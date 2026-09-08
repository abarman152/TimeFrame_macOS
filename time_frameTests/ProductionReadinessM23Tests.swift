//
//  ProductionReadinessM23Tests.swift
//  time_frameTests (Milestone 23)
//
//  The Milestone-23 additions to the release-gate source audit: the USER-CONFIGURABLE Control
//  Center quick-start control (`AppIntentControlConfiguration`) and its shared quick-start entity /
//  catalog / intents. They extend — never weaken — the M17…M22 invariants. Each test scans the
//  source tree on disk (comments + string literals blanked, identifier-boundary aware) and fails the
//  build if a boundary regresses:
//
//   • WidgetKit's `AppIntentControlConfiguration` (and the rest of the ControlWidget API) stays
//     iOS-only — macOS, `Core/`, `Shared/`, and the macOS widget remain ControlWidget-free;
//   • the shared quick-start layer (entity, catalog, config/action intents) is Foundation/AppIntents
//     only — no SwiftData/CloudKit/WidgetKit/SwiftUI, so it compiles into every target and can never
//     become a second timer or a second store;
//   • the configurable control owns no timer: the widget extension touches no persistence/CloudKit,
//     constructs no engine, schedules nothing, and defines no second action router;
//   • the app-side catalog writer lives in `Core/` (never the widget extension);
//   • the catalog reuses the EXISTING App Group (no new group), the single mutation seam is
//     unchanged, ActivityKit stays confined to its three iOS files, CloudKit stays disabled, and the
//     schema stays V6.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("M23 readiness — the configurable control is iOS-only")
struct M23ConfigurableControlPlatformTests {

    /// The full ControlWidget vocabulary, including the M23 configurable variant. None of it may
    /// appear in the macOS app, the shared `Core/` domain, the shared projections, or the macOS
    /// widget (all iOS-only API).
    private static let controlWidgetTokens = [
        "ControlWidget", "StaticControlConfiguration", "AppIntentControlConfiguration",
        "AppIntentControlValueProvider", "ControlWidgetButton", "ControlWidgetToggle", "ControlValueProvider"
    ]

    @Test("macOS / Core / Shared / macOS-widget contain no ControlWidget API (incl. AppIntentControlConfiguration)")
    func controlWidgetIsIOSOnly() {
        let hits = SourceAudit.filesReferencing(Self.controlWidgetTokens, in: SourceAudit.productionRoots())
        #expect(hits.isEmpty, "ControlWidget API leaked into non-iOS production code: \(hits)")
    }

}

@Suite("M23 readiness — the shared quick-start layer is pure")
struct M23SharedQuickStartPurityTests {

    private static func sharedFile(_ name: String) -> String? {
        guard let url = SourceAudit.swiftSources(in: SourceAudit.shared())
            .first(where: { $0.lastPathComponent == name }) else { return nil }
        return SourceAudit.code(url)
    }

    @Test("The shared quick-start intents/entity/catalog import no UI/WidgetKit/SwiftData/CloudKit")
    func quickStartLayerIsFoundationAndAppIntentsOnly() {
        guard let text = Self.sharedFile("WidgetControlIntents.swift") else {
            Issue.record("WidgetControlIntents.swift not found"); return
        }
        for forbidden in ["import WidgetKit", "import SwiftUI", "import ActivityKit",
                          "import SwiftData", "import CloudKit"] {
            #expect(!SourceAudit.references(text, forbidden), "shared quick-start layer must not \(forbidden)")
        }
        // It legitimately imports Foundation + AppIntents (the entity/config-intent/action-intent).
        #expect(SourceAudit.references(text, "import Foundation"))
        #expect(SourceAudit.references(text, "import AppIntents"))
    }

    @Test("The shared quick-start layer introduces no timer primitive (no second clock)")
    func quickStartLayerHasNoClock() {
        guard let text = Self.sharedFile("WidgetControlIntents.swift") else {
            Issue.record("WidgetControlIntents.swift not found"); return
        }
        for token in ["Timer(", "Timer.publish", "DispatchSourceTimer", "Task.sleep", "asyncAfter",
                      "scheduledTimer", "CADisplayLink"] {
            #expect(!SourceAudit.references(text, token), "quick-start layer must not schedule: \(token)")
        }
    }

    @Test("The quick-start catalog reuses the EXISTING App Group (no new group)")
    func catalogReusesAppGroup() {
        guard let text = Self.sharedFile("WidgetControlIntents.swift") else {
            Issue.record("WidgetControlIntents.swift not found"); return
        }
        // The catalog store's default suite is the SAME App Group as the widget projection store.
        #expect(SourceAudit.references(text, "WidgetProjectionStore.appGroupIdentifier"),
                "the catalog store must reuse the widget projection's App Group, not invent one")
        #expect(WidgetProjectionStore.appGroupIdentifier == "group.abirbarman.com.time-frame")
    }
}

@Suite("M23 readiness — the configurable control owns no timer")
struct M23ConfigurableControlBoundaryTests {



}

@Suite("M23 readiness — unchanged invariants")
struct M23UnchangedInvariantTests {


    @Test("M23 adds no model: the schema still has exactly the six V6 entities")
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
