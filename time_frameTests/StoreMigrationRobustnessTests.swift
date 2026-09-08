//
//  StoreMigrationRobustnessTests.swift
//  time_frameTests (Milestone 17)
//
//  Store-robustness audit, always against a temporary on-disk store, never the app's real
//  store.
//
//  ## Rewritten in Milestone 31 (ADR-109)
//  Two of these tests used to assert the opposite of what they assert now. They read:
//
//      "An incompatible legacy store is rebuilt into a usable V6 store"
//      "A corrupt store file is rebuilt, never crashed on"
//
//  and they passed — because the store *was* deleted and rebuilt, which is exactly the
//  behaviour that destroyed a real user's history. The tests were not wrong about what the
//  code did; they encoded a policy that should never have been the policy.
//
//  They are kept, inverted, as regression protection: an unopenable store must now be left
//  **completely untouched** and the failure reported. Deleting these tests would have
//  discarded the clearest statement of what must not happen again.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

/// A throwaway model with a shape unrelated to Time Frame's, used only to write a store
/// whose schema is structurally incompatible with the current V6 schema, so the
/// rebuild-on-incompatibility path is genuinely triggered.
@Model
final class _LegacyIncompatibleProbe {
    var marker: String = ""
    var count: Int = 0
    init(marker: String) { self.marker = marker }
}

@MainActor
@Suite("Store migration & robustness")
struct StoreMigrationRobustnessTests {

    // MARK: Temp store helpers

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tf-migrate-\(UUID().uuidString).store")
    }

    private func removeStore(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func appConfig(at url: URL) -> ModelConfiguration {
        ModelConfiguration(schema: PersistenceController.schema, url: url)
    }

    // MARK: Rebuild-on-incompatibility

    @Test("A store written by an unrelated schema is never deleted, whatever the outcome")
    func foreignSchemaStoreIsNeverDeleted() throws {
        let url = tempStoreURL()

        // Write a store with a completely different schema at this URL.
        do {
            let probeSchema = Schema([_LegacyIncompatibleProbe.self])
            let probeContainer = try ModelContainer(
                for: probeSchema,
                configurations: [ModelConfiguration(schema: probeSchema, url: url)]
            )
            probeContainer.mainContext.insert(_LegacyIncompatibleProbe(marker: "old"))
            try probeContainer.mainContext.save()
        }

        // Milestone 31 note: this case used to assert the store was *rebuilt*. It no longer
        // reaches that path at all — SwiftData lightweight-migrates a store carrying
        // unrelated entities by adding the missing ones, so the open simply succeeds. The
        // premise of the old test ("incompatible therefore expendable") was obsolete as
        // well as unsafe.
        //
        // What matters is the invariant, which holds either way: the file is still there.
        var thrown: Error?
        var opened: ModelContainer?
        do {
            opened = try PersistenceController.openOnDiskContainer(
                schema: PersistenceController.schema,
                configuration: appConfig(at: url)
            )
        } catch {
            thrown = error
        }

        // If it did fail, it failed the new way: reported, not resolved by deletion.
        if let thrown {
            #expect(thrown is StoreOpenError)
        } else {
            // It opened. The app's own entities are simply empty — nothing was erased to
            // achieve that, and the store stays usable.
            let ctx = try #require(opened).mainContext
            let configs = try ctx.fetch(FetchDescriptor<PomodoroConfiguration>())
            #expect(configs.isEmpty)
        }

        // The decisive assertion in both branches: the user's file still exists.
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try fileSize(at: url) > 0)
    }

    @Test("A corrupt store file is reported and preserved, never deleted")
    func corruptStoreIsPreserved() throws {
        let url = tempStoreURL()

        // Garbage where a SQLite store should be. In the real world this is a truncated
        // write or a damaged disk — and it is somebody's only copy.
        let garbage = Data("this is not a database".utf8)
        try garbage.write(to: url)

        var thrown: Error?
        do {
            _ = try PersistenceController.openOnDiskContainer(
                schema: PersistenceController.schema,
                configuration: appConfig(at: url)
            )
        } catch {
            thrown = error
        }

        #expect(thrown is StoreOpenError)
        // Byte-for-byte identical: nothing rewrote, truncated or removed it.
        #expect(try Data(contentsOf: url) == garbage)
    }

    /// The size of a file, for proving a failed open changed nothing.
    private func fileSize(at url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize ?? -1
    }

    @Test("A fresh on-disk store opens cleanly")
    func freshStoreOpens() throws {
        let url = tempStoreURL()
        defer { removeStore(at: url) }
        let container = try PersistenceController.openOnDiskContainer(
            schema: PersistenceController.schema,
            configuration: appConfig(at: url)
        )
        #expect(try ConfigurationRepository(context: container.mainContext).all().isEmpty)
    }

    // MARK: V6 round-trip across a real relaunch (no data loss)

    @Test("Every model survives a real V6 close/reopen with no data loss")
    func v6RoundTripAcrossReopen() throws {
        let url = tempStoreURL()
        defer { removeStore(at: url) }

        let configID: UUID
        // Launch 1: write one of each model.
        do {
            let container = try PersistenceController.openOnDiskContainer(
                schema: PersistenceController.schema, configuration: appConfig(at: url)
            )
            let ctx = container.mainContext
            let config = PomodoroConfiguration.classic()
            configID = config.id
            ctx.insert(config)

            let template = TaskTemplate(name: "Deep Work", taskName: "Write", configuration: config,
                                        defaultTotalSessions: 4)
            ctx.insert(template)

            let plan = SessionPlan(name: "Morning", taskName: "Ship")
            ctx.insert(plan)
            plan.items = [SessionPlanItem(order: 0, phase: .focus, duration: 1500,
                                          configuration: config, configurationName: config.name)]

            let session = FocusSession(taskName: "Write", configuration: config)
            session.status = .completed
            ctx.insert(session)
            session.intervals = [SessionInterval(phase: .focus, plannedDuration: 1500, order: 0)]

            try ctx.save()
        }

        // Launch 2: a fresh container over the same file reads everything back. The
        // container is held for the whole test — a `ModelContext` does not retain it.
        let container = try PersistenceController.openOnDiskContainer(
            schema: PersistenceController.schema, configuration: appConfig(at: url)
        )
        let ctx = container.mainContext
        #expect(try ctx.fetch(FetchDescriptor<PomodoroConfiguration>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<TaskTemplate>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<SessionPlan>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<SessionPlanItem>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<FocusSession>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<SessionInterval>()).count == 1)

        let restoredConfig = try #require(try ctx.fetch(FetchDescriptor<PomodoroConfiguration>()).first)
        #expect(restoredConfig.id == configID)
        // The completed session's frozen interval and its configuration link survive.
        let restoredSession = try #require(try ctx.fetch(FetchDescriptor<FocusSession>()).first)
        #expect(restoredSession.status == .completed)
        #expect(restoredSession.orderedIntervals.count == 1)
    }

    // MARK: originatingDeviceID (additive optional, ADR-063)

    @Test("A new session defaults originatingDeviceID to nil (additive optional migrates cleanly)")
    func newSessionHasNilOrigin() {
        let session = FocusSession(taskName: "x")
        #expect(session.originatingDeviceID == nil)
    }

    @Test("A legacy nil-origin session is treated as local; a foreign-origin session is not")
    func deviceLocalityBackCompat() {
        let legacy = FocusSession(taskName: "legacy") // nil origin (pre-device-tracking row)
        #expect(legacy.belongsToDevice("device-A") == true)
        #expect(legacy.belongsToDevice("device-B") == true)

        let owned = FocusSession(taskName: "owned")
        owned.originatingDeviceID = "device-A"
        #expect(owned.belongsToDevice("device-A") == true)
        #expect(owned.belongsToDevice("device-B") == false)
    }
}
