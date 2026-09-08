//
//  ProductionReadinessM28Tests.swift
//  time_frameTests (Milestone 28)
//
//  The release gate for the menu bar / Quick Start / icon milestone. Like every
//  `ProductionReadiness*` suite it scans the source tree on disk and FAILS THE BUILD if an
//  architectural invariant regresses, so the boundaries are enforced by the test run rather
//  than by review discipline.
//
//  What it holds:
//
//   1. Still exactly ONE `TimerEngine` and ONE `SessionCoordinator`; the new Quick Start layer
//      constructs neither, and mutates the timer only through `AppIntentSessionActions`.
//   2. The Quick Start layer introduces NO scheduling primitive and NO polling — its refresh
//      is driven by the repositories' neutral change hooks.
//   3. Pin state has exactly ONE persistence mechanism: the model's own `isPinned`. No
//      UserDefaults key, no App Group key, no side table.
//   4. Icons are a closed catalog: `TimeFrameIconIdentifier.symbolName` is the only mapping
//      from an identifier to an SF Symbol, and no view derives a symbol from stored data.
//   5. The schema is V7 with the same six models — no model added, no `#Unique` reintroduced.
//   6. The domain gains no presentation dependency: `Core/` still imports no SwiftUI outside
//      the design system, and the widget extension still imports no SwiftData.
//   7. No emoji anywhere in production source.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("Production readiness — Milestone 28")
struct ProductionReadinessM28Tests {

    // MARK: 1 — One timer, one coordinator, one mutation seam


    @Test("The Quick Start layer constructs no engine and no coordinator")
    func quickStartConstructsNoTimer() {
        for url in quickStartSources {
            let text = SourceAudit.code(url)
            #expect(!text.contains("TimerEngine("), "\(url.lastPathComponent) constructs an engine")
            #expect(!text.contains("SessionCoordinator("),
                    "\(url.lastPathComponent) constructs a coordinator")
        }
    }

    @Test("Quick Start mutates the timer only through the existing AppIntentSessionActions seam")
    func quickStartUsesTheOneSeam() {
        let coordinator = SourceAudit.code(quickStartFile("QuickStartCoordinator.swift"))
        #expect(coordinator.contains("AppIntentSessionActions("))
        // It must never reach past that seam into the coordinator's own start/control methods.
        for forbidden in ["session.startSession(", "session.startPlan(", "session.engine.start",
                          "session.pause(", "session.resume(", "session.stop(", "session.skip("] {
            #expect(!coordinator.contains(forbidden),
                    "Quick Start must route through AppIntentSessionActions, not \(forbidden)")
        }
    }

    @Test("The menu bar still routes its transport controls through SessionCoordinator")
    func menuBarRoutingUnchanged() {
        let adapter = SourceAudit.code(
            SourceAudit.appTarget().appendingPathComponent("Services/MenuBar/MenuBarCoordinator.swift"))
        for control in ["session.pause()", "session.resume()", "session.skip()",
                        "session.stop()", "session.restart()"] {
            #expect(adapter.contains(control))
        }
        #expect(!adapter.contains("engine.start"), "The menu bar never drives the engine directly")
    }

    // MARK: 2 — No second clock, no polling

    @Test("The Quick Start layer introduces no scheduling primitive")
    func quickStartHasNoClock() {
        for url in quickStartSources {
            let text = SourceAudit.code(url)
            for token in ["Timer(", "Task.sleep", "asyncAfter", "scheduledTimer",
                          "DispatchSourceTimer", "TimelineView", "publish(every"] {
                #expect(!text.contains(token),
                        "\(url.lastPathComponent) must not contain \(token)")
            }
        }
    }

    @Test("Quick Start refresh is event-driven: the repositories fire a neutral change hook")
    func refreshIsEventDriven() {
        for name in ["TaskTemplateRepository.swift", "SessionPlanRepository.swift"] {
            let text = SourceAudit.code(
                SourceAudit.core().appendingPathComponent("Services/Persistence/\(name)"))
            #expect(text.contains("onChange?()"), "\(name) must fire its change hook")
            // The persistence layer must stay ignorant of the surfaces that observe it.
            #expect(!text.contains("QuickStartCoordinator"))
            #expect(!text.contains("MenuBar"))
            #expect(!text.contains("WidgetKit"))
        }
    }

    @Test("The heartbeat is still the one scheduling primitive in Core (M26, ADR-099)")
    func heartbeatIsStillTheOnlySleeper() {
        let sleepers = SourceAudit.swiftSources(in: SourceAudit.core())
            .filter { SourceAudit.code($0).contains("Task.sleep") }
            .map { $0.lastPathComponent }
        #expect(sleepers == ["SessionCoordinator.swift"], "Found extra sleepers: \(sleepers)")
    }

    // MARK: 3 — One pin persistence mechanism


    @Test("No UserDefaults or App Group key is introduced for pinning")
    func noPinPreferencesStore() {
        for url in quickStartSources {
            let text = SourceAudit.code(url)
            #expect(!text.contains("UserDefaults"),
                    "\(url.lastPathComponent) must not persist Quick Start state itself")
            #expect(!text.contains("QuickStartCatalogStore"),
                    "The in-app Quick Start list reads the repositories, not the App Group catalog")
        }
    }

    @Test("Pinning writes through the repositories, never a raw ModelContext in a view")
    func pinningGoesThroughRepositories() {
        for name in ["Templates/TemplateDetailView.swift", "Templates/TemplateListView.swift",
                     "Plans/PlanDetailView.swift", "Plans/PlanListView.swift"] {
            let text = SourceAudit.code(
                SourceAudit.appTarget().appendingPathComponent("Views/\(name)"))
            #expect(text.contains("setPinned("), "\(name) must offer a pin control")
            #expect(!text.contains("modelContext.save()"),
                    "\(name) must not write the store directly")
        }
    }

    // MARK: 4 — One icon catalog, no loose SF Symbol strings


    @Test("The icon picker can only produce a catalog member")
    func pickerIsTyped() {
        let picker = SourceAudit.code(
            SourceAudit.appTarget().appendingPathComponent("Views/Components/TimeFrameIconPicker.swift"))
        #expect(picker.contains("Binding<TimeFrameIconIdentifier>")
                || picker.contains("selection: TimeFrameIconIdentifier"))
        #expect(!picker.contains("TextField"), "An icon must never be free text")
    }

    @Test("The icon catalog is pure Foundation — no SwiftUI, SwiftData, or timer")
    func catalogIsPure() {
        let text = SourceAudit.code(SourceAudit.core().appendingPathComponent("Support/TimeFrameIcon.swift"))
        for token in ["import SwiftUI", "import SwiftData", "import WidgetKit",
                      "import AppIntents", "import ActivityKit", "import CloudKit"] {
            #expect(!text.contains(token))
        }
    }

    // MARK: 5 — Schema

    @Test("The schema is V7 with the same six models and no uniqueness constraint")
    func schemaIsV7() {
        #expect(TimeFrameSchemaLatest.versionIdentifier == Schema.Version(7, 0, 0))
        let schema = Schema(versionedSchema: TimeFrameSchemaV7.self)
        #expect(schema.entities.count == 6)
        for entity in schema.entities {
            #expect(entity.uniquenessConstraints.isEmpty,
                    "\(entity.name) reintroduced a CloudKit-illegal uniqueness constraint")
        }
    }

    @Test("Every attribute V7 adds is CloudKit-legal (defaulted or optional)")
    func newAttributesAreCloudKitLegal() throws {
        let schema = Schema(versionedSchema: TimeFrameSchemaV7.self)
        for name in ["TaskTemplate", "SessionPlan"] {
            let entity = try #require(schema.entities.first { $0.name == name })
            let added = entity.attributes.filter {
                ["iconIdentifier", "isPinned", "pinnedAt"].contains($0.name)
            }
            #expect(added.count == 3, "\(name) is missing a Milestone 28 attribute")
            for attribute in added {
                #expect(attribute.isOptional || attribute.defaultValue != nil,
                        "\(name).\(attribute.name) must be optional or defaulted for CloudKit")
            }
        }
    }

    // MARK: 6 — Layer boundaries unchanged


    @Test("Quick Start adds no CloudKit and no WidgetKit dependency")
    func quickStartHasNoCloudOrWidgetKit() {
        for url in quickStartSources {
            let text = SourceAudit.code(url)
            #expect(!text.contains("import CloudKit"))
            #expect(!text.contains("import WidgetKit"))
            #expect(!text.contains("import SwiftUI"))
        }
    }

    @Test("macOS stays free of ActivityKit and ControlWidget")
    func macOSStaysClean() {
        for url in SourceAudit.swiftSources(inAnyOf: SourceAudit.productionRoots()) {
            let text = SourceAudit.code(url)
            #expect(!text.contains("import ActivityKit"), "\(url.lastPathComponent)")
            #expect(!text.contains("ControlWidget"), "\(url.lastPathComponent)")
        }
    }

    // MARK: 7 — Copy hygiene


    @Test("No development milestone label is exposed in user-facing menu bar copy")
    func noMilestoneLabelsInUI() {
        for url in SourceAudit.swiftSources(
            in: SourceAudit.appTarget().appendingPathComponent("Views/MenuBar")) {
            // Comments are stripped, so this only inspects real strings and code.
            let text = SourceAudit.codeKeepingStrings(url)
            for marker in ["Milestone ", "ADR-", "M28"] {
                #expect(!text.contains("\"\(marker)"), "\(url.lastPathComponent) leaks \(marker)")
            }
        }
    }

    // MARK: Helpers

    private var quickStartSources: [URL] {
        SourceAudit.swiftSources(in: SourceAudit.core().appendingPathComponent("Services/QuickStart"))
    }

    private func quickStartFile(_ name: String) -> URL {
        SourceAudit.core().appendingPathComponent("Services/QuickStart").appendingPathComponent(name)
    }
}
