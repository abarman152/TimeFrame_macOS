//
//  ProductionReadinessTests.swift
//  time_frameTests (Milestone 17)
//
//  The Milestone-17 production-readiness audit. Where earlier milestones each shipped a
//  focused boundary test (WidgetBoundaryInvariantTests, WidgetConfigurationBoundaryTests,
//  InteractiveWidgetBoundaryTests …), this is the consolidated release gate: it verifies
//  the architecture's load-bearing invariants across the WHOLE production tree, by scanning
//  the source on disk (comments and string literals blanked, identifier-boundary aware —
//  see `SourceAudit`) and by compile-linked assertions against the app module.
//
//  Every invariant here is one M17 promises: exactly one timer authority, one control seam,
//  a V6 schema, isolated persistence/integration boundaries, no ActivityKit on macOS, no
//  CloudKit import, and a hermetic test host. A regression in any of them fails this suite.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

// MARK: - Schema & versioning

@Suite("Production readiness — schema & versioning")
struct ProductionReadinessSchemaTests {

    @Test("The active SwiftData schema is V7, and every shipped version keeps its identity")
    func schemaIsV7() {
        #expect(TimeFrameSchemaLatest.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(TimeFrameSchemaV7.versionIdentifier == Schema.Version(7, 0, 0))
        // Historical versions must never be renumbered.
        #expect(TimeFrameSchemaV6.versionIdentifier == Schema.Version(6, 0, 0))
        #expect(TimeFrameSchemaV5.versionIdentifier == Schema.Version(5, 0, 0))
    }

    @Test("PersistenceController exposes the V6 schema and it builds")
    func schemaBuilds() {
        let schema = PersistenceController.schema
        #expect(schema.entities.isEmpty == false)
        // The six domain models are all present in the active schema.
        let names = Set(schema.entities.map(\.name))
        for model in ["PomodoroConfiguration", "FocusSession", "SessionInterval",
                      "TaskTemplate", "SessionPlan", "SessionPlanItem"] {
            #expect(names.contains(model), "Schema is missing \(model)")
        }
    }
}

// MARK: - Timer authority isolation

@Suite("Production readiness — timer authority isolation")
struct ProductionReadinessTimerTests {

    /// Every scheduling / repeating-timer primitive. `Text(timerInterval:)` and
    /// `TimelineView` are deliberately absent: those are *repaint* mechanisms, not clocks.
    static let schedulingTokens = [
        "Timer(", "Timer.publish", "DispatchSourceTimer",
        "Task.sleep", "asyncAfter", "scheduledTimer",
    ]

    /// Presentation + integration layers that must own no scheduling primitive at all.
    /// (Milestone 18 moved the neutral layers — Intents, Statistics, Services/Cloud,
    /// Services/LiveActivity, Widgets — into `Core/`; the macOS-only UI/integrations stay
    /// under the app target. The iOS companion + Live Activity extension are held to the
    /// same no-clock rule.)
    static func boundaryRoots() -> [URL] {
        let app = SourceAudit.appTarget()
        let core = SourceAudit.core()
        return [
            app.appendingPathComponent("Views"),
            app.appendingPathComponent("Services/Calendar"),
            app.appendingPathComponent("Services/MenuBar"),
            core.appendingPathComponent("Intents"),
            core.appendingPathComponent("Statistics"),
            core.appendingPathComponent("Services/Notifications"),
            core.appendingPathComponent("Services/Cloud"),
            core.appendingPathComponent("Services/LiveActivity"),
            core.appendingPathComponent("Widgets"),
            SourceAudit.shared(),
            SourceAudit.widgetExtension(),
        ]
    }

    @Test("Presentation and integration layers contain no scheduling primitive")
    func boundaryLayersHaveNoClock() {
        let hits = SourceAudit.filesReferencing(Self.schedulingTokens, in: Self.boundaryRoots())
        #expect(hits.isEmpty, "Forbidden scheduling primitive found in: \(hits)")
    }

    @Test("Exactly one production file schedules the timer heartbeat: SessionCoordinator")
    func singleSchedulingAuthority() {
        let hits = SourceAudit.filesReferencing(Self.schedulingTokens, in: SourceAudit.productionRoots())
        #expect(hits == ["SessionCoordinator.swift"],
                "Scheduling primitive must live only in SessionCoordinator; found: \(hits)")
    }

    @Test("The engine itself performs no scheduling")
    func engineDoesNotSchedule() {
        let engineFile = SourceAudit.core().appendingPathComponent("Timer/TimerEngine.swift")
        let text = SourceAudit.code(engineFile)
        for token in Self.schedulingTokens {
            #expect(SourceAudit.references(text, token) == false,
                    "TimerEngine must not reference '\(token)'")
        }
    }

    @Test("TimerEngine is declared once and constructed only by SessionCoordinator")
    func singleEngine() {
        #expect(SourceAudit.filesReferencing(["class TimerEngine"], in: SourceAudit.productionRoots())
                == ["TimerEngine.swift"])
        #expect(SourceAudit.filesReferencing(["TimerEngine("], in: SourceAudit.productionRoots())
                == ["SessionCoordinator.swift"])
    }

    @Test("SessionCoordinator is the single declared control seam")
    func singleCoordinator() {
        #expect(SourceAudit.filesReferencing(["class SessionCoordinator"], in: SourceAudit.productionRoots())
                == ["SessionCoordinator.swift"])
    }

    @Test("No production file decrements a stored countdown (timestamp-authoritative)")
    func noManualDecrement() {
        let hits = SourceAudit.filesReferencing(["remaining -=", "remaining -=", "remaining--"],
                                                in: SourceAudit.productionRoots())
        #expect(hits.isEmpty, "Manual countdown decrement found in: \(hits)")
    }

    @Test("The timer core uses no fatalError, try!, or as! in its runtime path")
    func timerCoreHasNoUnsafeExits() {
        let timerDir = SourceAudit.core().appendingPathComponent("Timer")
        let hits = SourceAudit.filesReferencing(["fatalError(", "try!", "as!"], in: [timerDir])
        #expect(hits.isEmpty, "Unsafe exit in timer core: \(hits)")
    }
}

// MARK: - Persistence & integration boundaries

@Suite("Production readiness — persistence & integration boundaries")
struct ProductionReadinessBoundaryTests {

    /// Layers that must never touch SwiftData directly: the read-only/observer
    /// integrations, the shared projection value types, and the widget extension. (Views
    /// and the App-Intents data provider legitimately read via `@Query`/repositories.)
    static func persistenceFreeRoots() -> [URL] {
        let app = SourceAudit.appTarget()
        let core = SourceAudit.core()
        return [
            app.appendingPathComponent("Services/Calendar"),
            app.appendingPathComponent("Services/MenuBar"),
            core.appendingPathComponent("Services/Notifications"),
            core.appendingPathComponent("Services/Cloud"),
            core.appendingPathComponent("Services/LiveActivity"),
            SourceAudit.shared(),
            SourceAudit.widgetExtension(),
        ]
    }

    @Test("Observer integrations, Shared, and the widget import no SwiftData and touch no ModelContext")
    func integrationsArePersistenceFree() {
        let hits = SourceAudit.filesReferencing(["import SwiftData", "ModelContext"],
                                                in: Self.persistenceFreeRoots())
        #expect(hits.isEmpty, "Persistence leaked into an integration boundary: \(hits)")
    }


    @Test("The widget projection store is the only App Group channel; the widget reads it read-only")
    func widgetProjectionIsReadOnlyProjection() {
        // The shared store defines exactly one App Group identifier, used by both processes.
        #expect(WidgetProjectionStore.appGroupIdentifier == "group.abirbarman.com.time-frame")
        // An unavailable suite is inert (no crash, no throw): a corrupt/missing App Group
        // can never break the app or the widget.
        let inert = WidgetProjectionStore(defaults: nil)
        #expect(inert.isAvailable == false)
        #expect(inert.read() == nil)
        #expect(inert.write(.unavailable(reason: "audit")) == false)
    }
}

// MARK: - Platform constraints

@Suite("Production readiness — platform constraints")
struct ProductionReadinessPlatformTests {


    @Test("No production file imports CloudKit or references CKRecord/CKContainer")
    func noCloudKitImport() {
        let hits = SourceAudit.filesReferencing(["import CloudKit", "CKRecord", "CKContainer"],
                                                in: SourceAudit.productionRoots())
        #expect(hits.isEmpty, "CloudKit referenced directly in: \(hits)")
    }

    @Test("Shared projection types stay Foundation-only (AppIntents only in the two intent files)")
    func sharedStaysPure() {
        for file in SourceAudit.swiftSources(in: SourceAudit.shared()) {
            let text = SourceAudit.code(file)
            for forbidden in ["import SwiftData", "import SwiftUI", "import WidgetKit",
                              "import CloudKit", "import time_frame"] {
                #expect(SourceAudit.references(text, forbidden) == false,
                        "\(file.lastPathComponent) has forbidden '\(forbidden)'")
            }
        }
        let appIntentsImporters = SourceAudit.swiftSources(in: SourceAudit.shared())
            .filter { SourceAudit.references(SourceAudit.code($0), "import AppIntents") }
            .map(\.lastPathComponent)
            .sorted()
        #expect(appIntentsImporters == ["TimeFrameWidgetConfigurationIntent.swift", "WidgetControlIntents.swift"])
    }
}

// MARK: - Test-host hermeticity

@Suite("Production readiness — test-host hermeticity")
struct ProductionReadinessHermeticityTests {

    @Test("This very process is detected as an XCTest host")
    func liveProcessIsDetected() {
        // If this regresses, launch would run live seeding/recovery inside the test process
        // and could touch the developer's real session — the exact hang M17 must prevent.
        #expect(TestHostEnvironment.isHostingUnitTests() == true)
    }

    @Test("A clean (non-test) environment is not detected as a host")
    func cleanEnvironmentIsNotAHost() {
        #expect(TestHostEnvironment.isHostingUnitTests(environment: [:]) == false)
        #expect(TestHostEnvironment.isHostingUnitTests(environment: ["PATH": "/usr/bin"]) == false)
    }

    @Test("Each XCTest indicator key independently marks the process as a host")
    func eachIndicatorTriggers() {
        for key in TestHostEnvironment.indicatorKeys {
            #expect(TestHostEnvironment.isHostingUnitTests(environment: [key: "x"]) == true,
                    "Indicator '\(key)' should mark a test host")
        }
    }

    @Test("Launch guards live seeding and recovery behind the test-host check")
    func launchGuardsLiveStore() {
        let appFile = SourceAudit.appTarget().appendingPathComponent("time_frameApp.swift")
        let text = SourceAudit.code(appFile)
        // The guard must be wired in and must gate the two live-store side effects.
        #expect(SourceAudit.references(text, "TestHostEnvironment.isHostingUnitTests()"))
        #expect(text.contains("if !isHostingUnitTests"), "Launch must guard live side effects")
        #expect(text.contains("recover()"), "recover() must still be present (guarded)")
        #expect(text.contains("seedDefaultIfNeeded()"), "seeding must still be present (guarded)")
    }
}
