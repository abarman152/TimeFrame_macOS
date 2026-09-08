//
//  ProductionReadinessM31Tests.swift
//  time_frameTests (Milestone 31)
//
//  The data-safety invariants, enforced by scanning the source tree (ADR-109/110).
//
//  The behaviour this milestone removed did not arrive through a bad decision — it arrived
//  as a *reasonable-looking* one, documented as a "safety net" (ADR-016), that survived
//  eight further milestones and two tests written to confirm it. It would come back the
//  same way. These audits fail the build if it does.
//

import Foundation
import Testing
@testable import time_frame

@Suite("M31 — no automatic store deletion")
struct M31DataSafetyAuditTests {

    /// Every production source file (app, shared core, widget extension).
    private var productionSources: [URL] {
        SourceAudit.swiftSources(inAnyOf: SourceAudit.productionRoots())
    }

    @Test("No production source removes a file from disk")
    func noFileRemoval() {
        // `FileManager.removeItem` is the only API that can delete a user's store, so the
        // rule is enforced at that level rather than at the level of one function's name.
        // `StoreQuarantine` *moves* files and is deliberately the one place that touches
        // store files at all.
        for url in productionSources {
            let text = SourceAudit.code(url)
            #expect(!text.contains("removeItem"),
                    "\(url.lastPathComponent) must not delete files — preserve instead (ADR-109)")
        }
    }

    @Test("The function that used to delete the store no longer exists")
    func removeStoreFilesIsGone() {
        for url in productionSources {
            let text = SourceAudit.code(url)
            #expect(!text.contains("removeStoreFiles"),
                    "\(url.lastPathComponent) must not reintroduce removeStoreFiles")
        }
    }

    @Test("Opening a store classifies its failure instead of rebuilding")
    func openerReportsRatherThanRebuilds() {
        let controller = SourceAudit.code(
            SourceAudit.core().appendingPathComponent("Services/Persistence/PersistenceController.swift"))
        #expect(controller.contains("StoreOpenError"),
                "A failed open must throw a classified error")
        #expect(controller.contains("StoreOpenFailure.classify"))
        // The old shape: open, catch, delete, open again.
        #expect(!controller.contains("rebuilding store"))
    }

    @Test("Quarantine moves store files and never removes them")
    func quarantineOnlyMoves() {
        let url = SourceAudit.core().appendingPathComponent("Services/Persistence/StoreQuarantine.swift")
        let text = SourceAudit.code(url)
        // The sidecar suffixes are string literals, which `code` blanks — read them back
        // from the variant that keeps literals.
        let literals = SourceAudit.codeKeepingStrings(url)
        #expect(text.contains("moveItem"))
        #expect(!text.contains("removeItem"))
        // All three files travel together: the WAL can hold committed transactions the
        // main file does not yet have.
        #expect(literals.contains("-wal"))
        #expect(literals.contains("-shm"))
    }

    @Test("Starting fresh preserves before it opens, and only from an explicit action")
    func startFreshPreservesFirst() {
        let controller = SourceAudit.code(
            SourceAudit.core().appendingPathComponent("Services/Persistence/PersistenceController.swift"))
        guard let range = controller.range(of: "func startFreshPreservingExistingStore") else {
            Issue.record("The explicit recovery entry point must exist")
            return
        }
        let body = controller[range.upperBound...].prefix(600)
        let preserveIndex = body.range(of: "StoreQuarantine.preserve")?.lowerBound
        let openIndex = body.range(of: "openOnDiskContainer")?.lowerBound
        #expect(preserveIndex != nil && openIndex != nil)
        if let preserveIndex, let openIndex {
            #expect(preserveIndex < openIndex,
                    "The existing store must be preserved before a new one is opened")
        }
    }

    @Test("A failed open is a state the UI must handle, not an empty library")
    func failureIsRepresentable() {
        let state = SourceAudit.code(
            SourceAudit.core().appendingPathComponent("Services/Persistence/PersistenceState.swift"))
        #expect(state.contains("case needsRecovery"))
        #expect(state.contains("isShowingDurableData"))

        // The app must actually branch on it, rather than rendering the library regardless.
        let app = SourceAudit.code(
            SourceAudit.appTarget().appendingPathComponent("time_frameApp.swift"))
        #expect(app.contains("pendingFailure"))
        #expect(app.contains("PersistenceRecoveryView"))
    }

    @Test("The recovery surface states that nothing was deleted, and confirms before acting")
    func recoverySurfaceIsHonest() {
        let view = SourceAudit.codeKeepingStrings(
            SourceAudit.appTarget().appendingPathComponent("Views/Persistence/PersistenceRecoveryView.swift"))
        #expect(view.contains("Your data has not been deleted."))
        #expect(view.contains("Try Again"))
        #expect(view.contains("Continue Without Existing Data"))
        // The only action that changes anything must ask first.
        #expect(view.contains("confirmationDialog"))
    }
}

@Suite("M31 — the production store is not reachable by accident")
struct M31StoreIsolationAuditTests {

    @Test("The on-disk store URL is resolved explicitly, not left to SwiftData's default")
    func storeURLIsExplicit() {
        let controller = SourceAudit.code(
            SourceAudit.core().appendingPathComponent("Services/Persistence/PersistenceController.swift"))
        #expect(controller.contains("StoreLocation.resolve()"),
                "The store's location must be an explicit decision (ADR-110)")
    }

    @Test("Reaching the production store requires asking for it by name")
    func productionAccessIsNamed() {
        let location = SourceAudit.code(
            SourceAudit.core().appendingPathComponent("Services/Persistence/StoreLocation.swift"))
        #expect(location.contains("func productionStoreURL"))
        #expect(location.contains("assertNotProductionStore"))
        #expect(location.contains("directoryOverrideKey"))
    }

    @Test("No test source writes to the production store path")
    func testsNeverNameProduction() {
        // A destructive test that reached the real user's default store would do to a
        // developer exactly what this milestone exists to prevent.
        let tests = SourceAudit.swiftSources(
            in: SourceAudit.repoRoot().appendingPathComponent("time_frameTests"))
        // Built from fragments so this file's own assertion is not itself a match, and
        // this file is skipped for the same reason.
        let needle = "Library/" + "Application Support"
        for url in tests where url.lastPathComponent != "ProductionReadinessM31Tests.swift" {
            let text = SourceAudit.codeKeepingStrings(url)
            #expect(!text.contains(needle),
                    "\(url.lastPathComponent) must not name the production store path")
        }
    }

    @Test("The V6 fixture refuses to write to the production store")
    func fixtureRefusesProduction() {
        let fixture = SourceAudit.code(
            SourceAudit.repoRoot()
                .appendingPathComponent("time_frameTests/PersistenceV6FixtureModels.swift"))
        #expect(fixture.contains("assertNotProductionStore"))
    }
}
