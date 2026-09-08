//
//  PersistenceRecoveryTests.swift
//  time_frameTests (Milestone 31)
//
//  The data-safety contract (ADR-109), asserted.
//
//  One rule sits behind all of it: **a store that cannot be opened is never deleted.** Not
//  when the schema does not match, not when the file is damaged, not when it is locked, and
//  not when the app cannot tell what went wrong. The app preserves, reports, and waits for
//  the user; it does not trade their history for a clean launch.
//
//  Every test here runs against a temporary directory, and `StoreLocation` is asserted to
//  keep the production store out of reach of this process entirely.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

// MARK: - Failure classification

@Suite("Persistence: failure classification")
struct StoreOpenFailureClassificationTests {

    @Test("A SQLite 'not a database' code is a malformed store, not a corrupt one")
    func notADatabase() {
        #expect(StoreOpenFailure.classifyKind(domain: NSCocoaErrorDomain, code: 259,
                                              sqliteCode: 26) == .malformedStore)
    }

    @Test("Distinct causes classify distinctly — no cause is folded into 'corrupt'")
    func causesAreDistinguished() {
        // This is the heart of the fix. Before Milestone 31 each of these reached one
        // `catch` and produced one response: delete the store.
        #expect(StoreOpenFailure.classifyKind(domain: NSCocoaErrorDomain, code: 134100,
                                              sqliteCode: nil) == .schemaMismatch)
        #expect(StoreOpenFailure.classifyKind(domain: NSCocoaErrorDomain, code: 134110,
                                              sqliteCode: nil) == .migrationFailed)
        #expect(StoreOpenFailure.classifyKind(domain: NSCocoaErrorDomain, code: 257,
                                              sqliteCode: nil) == .permissionDenied)
        #expect(StoreOpenFailure.classifyKind(domain: NSCocoaErrorDomain, code: 513,
                                              sqliteCode: nil) == .permissionDenied)
        #expect(StoreOpenFailure.classifyKind(domain: NSCocoaErrorDomain, code: 260,
                                              sqliteCode: nil) == .fileAccessFailed)
        #expect(StoreOpenFailure.classifyKind(domain: NSCocoaErrorDomain, code: 259,
                                              sqliteCode: nil) == .malformedStore)
        #expect(StoreOpenFailure.classifyKind(domain: "NSSQLiteErrorDomain", code: 11,
                                              sqliteCode: 11) == .storeCorrupt)
        #expect(StoreOpenFailure.classifyKind(domain: NSCocoaErrorDomain, code: 1,
                                              sqliteCode: 5) == .fileLocked)
    }

    @Test("An unrecognised failure is 'unknown', never assumed to be corruption")
    func unknownIsNotCorrupt() {
        // The old code's implicit assumption was "open failed, therefore the store is
        // rubbish". Being unable to explain a failure is not evidence about the data.
        let kind = StoreOpenFailure.classifyKind(domain: "com.example.mystery",
                                                 code: 42, sqliteCode: nil)
        #expect(kind == .unknown)
        #expect(kind != .storeCorrupt)
    }

    @Test("Every classification warrants preserving the store")
    func everyKindIsPreserved() {
        for kind in StoreOpenFailureKind.allCases {
            #expect(kind.warrantsPreservation,
                    "\(kind.rawValue) must still preserve the user's data")
            #expect(!kind.userExplanation.isEmpty)
            #expect(!kind.userSuggestion.isEmpty)
        }
    }

    @Test("Only a lock is treated as worth retrying on its own")
    func transience() {
        #expect(StoreOpenFailureKind.fileLocked.isTransient)
        #expect(!StoreOpenFailureKind.schemaMismatch.isTransient)
        #expect(!StoreOpenFailureKind.storeCorrupt.isTransient)
        #expect(!StoreOpenFailureKind.unknown.isTransient)
    }

    @Test("A classified failure logs its codes but not the store's full path")
    func logSummaryIsSafe() {
        let failure = StoreOpenFailure(kind: .schemaMismatch,
                                       storeURL: URL(fileURLWithPath: "/Users/someone/secret.store"),
                                       domain: NSCocoaErrorDomain, code: 134100,
                                       underlying: "…")
        #expect(failure.logSummary.contains("schemaMismatch"))
        #expect(!failure.logSummary.contains("someone"))
    }
}

// MARK: - Quarantine

@Suite("Persistence: quarantine preserves, never deletes")
struct StoreQuarantineTests {

    private func makeStoreFiles(named name: String = "default.store") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tf-quarantine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = dir.appendingPathComponent(name)
        try Data("main".utf8).write(to: store)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: store.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: store.path + "-shm"))
        return store
    }

    @Test("The store and both sidecars are moved, and the originals are gone from the path")
    func movesTheWholeStore() throws {
        let store = try makeStoreFiles()
        StoreLocation.assertNotProductionStore(store)

        let outcome = try StoreQuarantine.preserve(storeAt: store)

        #expect(outcome.movedFiles.count == 3)
        // The WAL matters: it can hold committed transactions the main file does not yet
        // have, so preserving only `.store` would silently drop the user's recent work.
        let names = Set(outcome.movedFiles.map(\.lastPathComponent))
        #expect(names.contains("default.store"))
        #expect(names.contains("default.store-wal"))
        #expect(names.contains("default.store-shm"))

        // The originals moved out of the way so a fresh store can be created...
        #expect(!FileManager.default.fileExists(atPath: store.path))
        // ...but every byte is still on disk, in the recovery folder.
        for file in outcome.movedFiles {
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
        let recovered = try String(contentsOf: outcome.directory.appendingPathComponent("default.store"),
                                  encoding: .utf8)
        #expect(recovered == "main")
    }

    @Test("Recovery folders never collide, so an earlier copy is never overwritten")
    func recoveryFoldersAreUnique() throws {
        let first = try makeStoreFiles()
        let root = StoreQuarantine.recoveryRoot(for: first)
        let fixedInstant = Date(timeIntervalSince1970: 1_750_000_000)

        // Same store path, same timestamp, twice: the second must not land on the first.
        let a = try StoreQuarantine.preserve(storeAt: first, now: fixedInstant)
        try Data("second".utf8).write(to: first)
        let b = try StoreQuarantine.preserve(storeAt: first, now: fixedInstant)

        #expect(a.directory != b.directory)
        #expect(a.directory.deletingLastPathComponent() == root)
        #expect(b.directory.deletingLastPathComponent() == root)
        // The first copy is intact, not replaced by the second.
        let firstCopy = try String(contentsOf: a.directory.appendingPathComponent("default.store"),
                                   encoding: .utf8)
        #expect(firstCopy == "main")
    }

    @Test("Preserving nothing fails loudly rather than reporting a phantom success")
    func nothingToPreserve() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("tf-absent-\(UUID().uuidString)")
            .appendingPathComponent("default.store")
        #expect(throws: StoreQuarantine.QuarantineError.nothingToPreserve) {
            try StoreQuarantine.preserve(storeAt: missing)
        }
    }

    @Test("The timestamp is filesystem-safe, UTC and sortable")
    func timestampFormat() {
        let stamp = StoreQuarantine.timestamp(from: Date(timeIntervalSince1970: 1_750_000_000))
        #expect(!stamp.contains(":"), "A colon is not usable in a path component in Finder")
        #expect(stamp.hasSuffix("Z"))
        // Sortable: an earlier instant must order before a later one as plain text.
        let later = StoreQuarantine.timestamp(from: Date(timeIntervalSince1970: 1_750_003_600))
        #expect(stamp < later)
    }

    @Test("A store whose name contains a dot still names its sidecars correctly")
    func sidecarNamingIsPathBased() {
        let store = URL(fileURLWithPath: "/tmp/my.data.store")
        #expect(StoreQuarantine.sidecarURL(for: store, suffix: "-wal").lastPathComponent
                == "my.data.store-wal")
        #expect(StoreQuarantine.sidecarURL(for: store, suffix: "").lastPathComponent
                == "my.data.store")
    }
}

// MARK: - The no-delete contract, end to end

@MainActor
@Suite("Persistence: a failed open never destroys data")
struct PersistenceFailureTests {

    private func corruptStore() throws -> (url: URL, bytes: Data) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tf-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("default.store")
        let bytes = Data("definitely not a database".utf8)
        try bytes.write(to: url)
        return (url, bytes)
    }

    @Test("Opening an unopenable store throws a classified error and changes nothing")
    func failedOpenPreservesBytes() throws {
        let (url, bytes) = try corruptStore()
        StoreLocation.assertNotProductionStore(url)

        var thrown: Error?
        do {
            _ = try PersistenceController.openOnDiskContainer(
                schema: PersistenceController.schema,
                configuration: ModelConfiguration(schema: PersistenceController.schema, url: url))
        } catch {
            thrown = error
        }

        let storeError = thrown as? StoreOpenError
        #expect(storeError != nil)
        #expect(storeError?.failure.storeURL == url)
        #expect(try Data(contentsOf: url) == bytes, "The store must be byte-for-byte untouched")
    }

    @Test("Bootstrap reports needsRecovery instead of silently substituting an empty store")
    func bootstrapAsksRatherThanErases() throws {
        let (url, bytes) = try corruptStore()

        let bootstrap = PersistenceController.bootstrap(
            requestedMode: .local,
            inMemory: false,
            makeCloud: { throw StoreOpenError(failure: .init(kind: .unknown, storeURL: url,
                                                             domain: "test", code: 0, underlying: "")) },
            makeLocal: {
                try PersistenceController.openOnDiskContainer(
                    schema: PersistenceController.schema,
                    configuration: ModelConfiguration(schema: PersistenceController.schema, url: url))
            }
        )

        // The app can still launch — but it must know, and be able to say, that what it is
        // holding is not the user's library.
        #expect(bootstrap.state.pendingFailure != nil)
        #expect(bootstrap.state.isShowingDurableData == false)
        // And the user's bytes are still exactly where they were.
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test("A successful open reports ready, and shows durable data")
    func successfulOpenIsReady() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tf-ok-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("default.store")

        let bootstrap = PersistenceController.bootstrap(
            requestedMode: .local, inMemory: false,
            makeCloud: { throw CancellationError() },
            makeLocal: {
                try PersistenceController.openOnDiskContainer(
                    schema: PersistenceController.schema,
                    configuration: ModelConfiguration(schema: PersistenceController.schema, url: url))
            }
        )

        #expect(bootstrap.state.isShowingDurableData)
        #expect(bootstrap.state.pendingFailure == nil)
        #expect(bootstrap.state == .ready(.local))
    }

    @Test("Starting fresh preserves the old store and only then opens a new one")
    func startFreshPreservesFirst() throws {
        let (url, bytes) = try corruptStore()

        let result = try PersistenceController.startFreshPreservingExistingStore(storeURL: url)

        // A usable, empty store is now at the original path...
        let configs = try result.container.mainContext.fetch(FetchDescriptor<PomodoroConfiguration>())
        #expect(configs.isEmpty)

        // ...and the previous store is intact in a recovery folder, not gone.
        guard case let .recoveredWithFreshStore(preservedAt, _) = result.state else {
            Issue.record("Expected a recovered state carrying the recovery location")
            return
        }
        let preserved = preservedAt.appendingPathComponent("default.store")
        #expect(FileManager.default.fileExists(atPath: preserved.path))
        #expect(try Data(contentsOf: preserved) == bytes)
    }
}

// MARK: - Development / test isolation

@Suite("Persistence: the production store is out of reach")
struct PersistenceIsolationTests {

    @Test("Under the XCTest host the store resolves somewhere isolated, never production")
    func testHostIsIsolated() {
        let resolution = StoreLocation.resolve(
            environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"])
        #expect(resolution.origin == .testHostIsolated)
        #expect(resolution.isProduction == false)
        #expect(!StoreLocation.isProductionStore(resolution.url))
    }

    @Test("This very process resolves to an isolated store")
    func thisProcessIsIsolated() {
        // Not a synthetic environment: the live one. If this ever fails, the suite is
        // running against the developer's real library and must stop.
        let resolution = StoreLocation.resolve()
        #expect(resolution.origin == .testHostIsolated)
        #expect(!StoreLocation.isProductionStore(resolution.url))
    }

    @Test("An explicit directory override wins, so a developer build can be redirected")
    func overrideWins() {
        let resolution = StoreLocation.resolve(
            environment: [StoreLocation.directoryOverrideKey: "/tmp/timeframe-dev",
                          "XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"])
        #expect(resolution.origin == .environmentOverride)
        #expect(resolution.url.deletingLastPathComponent().path == "/tmp/timeframe-dev")
    }

    @Test("A normal launch still resolves to the app's long-standing production path")
    func productionPathUnchanged() {
        // Milestone 31 must not orphan anyone's existing data by moving the store.
        let resolution = StoreLocation.resolve(environment: [:])
        #expect(resolution.origin == .production)
        #expect(resolution.url.lastPathComponent == "default.store")
        #expect(StoreLocation.isProductionStore(resolution.url))
    }

    @Test("Isolated stores are unique per resolution, so tests cannot collide")
    func isolatedStoresAreUnique() {
        let env = ["XCTestBundlePath": "/tmp/x.xctest"]
        #expect(StoreLocation.resolve(environment: env).url
                != StoreLocation.resolve(environment: env).url)
    }
}
