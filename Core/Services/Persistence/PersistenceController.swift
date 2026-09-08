//
//  PersistenceController.swift
//  time_frame
//
//  Central construction point for the app's SwiftData ModelContainer.
//

import Foundation
import SwiftData
import os

/// Builds the app's `ModelContainer` from the versioned schema.
///
/// Kept separate from the `App` so the same container configuration can be
/// reused by previews and tests, and so persistence concerns stay out of the
/// view layer.
///
/// From Milestone 13 the controller can build the store **local-only** or
/// **CloudKit-mirrored**, and it always degrades safely: if a CloudKit-backed
/// container cannot be created it falls back to the *existing local store* (never
/// an empty in-memory one), so a CloudKit problem can never lose local data or
/// block the timer (ADR-060/062). CloudKit itself is provided by SwiftData's
/// native mirroring — this type imports no CloudKit and touches no `CKRecord`.
enum PersistenceController {

    /// The active schema (latest version).
    static var schema: Schema { Schema(versionedSchema: TimeFrameSchemaLatest.self) }

    /// The outcome of bringing the store up: the container plus the mode that is
    /// actually active (which may be `.fallback` if CloudKit was requested but
    /// could not initialise).
    struct Bootstrap {
        let container: ModelContainer
        let activeMode: PersistenceMode
        /// What actually happened. `.needsRecovery` means the container above is a
        /// scratch in-memory store and the user's real store is untouched on disk,
        /// waiting for an explicit decision (ADR-109).
        let state: PersistenceState

        init(container: ModelContainer, activeMode: PersistenceMode, state: PersistenceState? = nil) {
            self.container = container
            self.activeMode = activeMode
            self.state = state ?? .ready(activeMode)
        }
    }

    // MARK: Bootstrap (mode resolution + fallback)

    /// Brings the store up in the requested mode, degrading safely to local.
    ///
    /// - `.local` / `.fallback` requested → a local on-disk (or in-memory) store.
    /// - `.cloudKit` requested → a CloudKit-mirrored store; if that cannot be
    ///   created, the **same on-disk store** is reopened local-only and the active
    ///   mode is reported as `.fallback`. The CloudKit attempt never wipes the
    ///   store — a rebuild only ever happens for a genuine *local* schema
    ///   incompatibility (see `makeContainer`).
    ///
    /// Never returns an empty in-memory store in place of real data: only if the
    /// local on-disk store itself cannot be opened at all does it fall back to an
    /// in-memory store so the app can still launch.
    static func bootstrap(requestedMode: PersistenceMode, inMemory: Bool = false) -> Bootstrap {
        bootstrap(
            requestedMode: requestedMode,
            inMemory: inMemory,
            makeCloud: { try makeCloudKitContainer(inMemory: inMemory) },
            makeLocal: { try makeContainer(mode: .local, inMemory: inMemory) }
        )
    }

    /// Testable core of `bootstrap`: the CloudKit and local container builders are
    /// injected so a test can force a CloudKit failure deterministically without a
    /// real iCloud account, and confirm the store falls back to local intact.
    static func bootstrap(
        requestedMode: PersistenceMode,
        inMemory: Bool,
        makeCloud: () throws -> ModelContainer,
        makeLocal: () throws -> ModelContainer
    ) -> Bootstrap {
        switch requestedMode {
        case .local, .fallback:
            return openLocalOrRequestRecovery(makeLocal, mode: .local)

        case .cloudKit:
            do {
                let container = try makeCloud()
                AppLog.persistence.info("Store opened with CloudKit mirroring active.")
                return Bootstrap(container: container, activeMode: .cloudKit)
            } catch {
                // A CloudKit-availability failure (no account, no entitlement,
                // CloudKit down) must NOT lose local data. Reopen the *same*
                // on-disk store local-only and carry on offline (ADR-062).
                AppLog.persistence.error(
                    "CloudKit store unavailable (\(String(describing: error), privacy: .public)); using local store."
                )
                return openLocalOrRequestRecovery(makeLocal, mode: .fallback)
            }
        }
    }

    /// Opens the local store, or — if it cannot be opened — hands back a **scratch
    /// in-memory** container together with `.needsRecovery`, leaving every byte of the
    /// user's store where it was (ADR-109).
    ///
    /// This is the method that used to delete the user's data. It now does the opposite:
    /// the on-disk store is never modified on a failed open, and the caller is told
    /// explicitly that what it is holding is not the user's library. The in-memory
    /// container exists only so the app can launch far enough to *show* the recovery
    /// surface — it is never presented as the user's data (`PersistenceState`
    /// `.isShowingDurableData` is false), and because it is in-memory it cannot
    /// overwrite anything.
    private static func openLocalOrRequestRecovery(
        _ makeLocal: () throws -> ModelContainer,
        mode: PersistenceMode
    ) -> Bootstrap {
        do {
            let container = try makeLocal()
            return Bootstrap(container: container, activeMode: mode)
        } catch {
            let failure = (error as? StoreOpenError)?.failure
                ?? StoreOpenFailure.classify(error, storeURL: StoreLocation.resolve().url)
            AppLog.persistence.error(
                "Store could not be opened: \(failure.logSummary, privacy: .public). The existing store was left untouched; awaiting the user's recovery choice."
            )
            // A scratch store so the app can render its recovery surface. Never on disk.
            let scratch = try! makeContainer(mode: .local, inMemory: true)
            return Bootstrap(container: scratch, activeMode: mode, state: .needsRecovery(failure))
        }
    }

    // MARK: Explicit recovery (only ever from a user decision)

    /// Starts fresh **after the user has explicitly asked to**, preserving the existing
    /// store rather than deleting it.
    ///
    /// The old store (and its `-wal`/`-shm` sidecars) is moved into a timestamped folder
    /// under `TimeFrame Recovery/`, then a new empty store is opened in its place. If the
    /// preservation step fails the whole operation fails and **nothing is removed** — the
    /// app stays in `.needsRecovery` rather than trading the user's data for a clean
    /// launch.
    ///
    /// Nothing on the launch path calls this. It exists solely to serve the recovery
    /// surface's "Continue Without Existing Data" action (§9/§20).
    static func startFreshPreservingExistingStore(
        storeURL: URL,
        now: Date = Date()
    ) throws -> (container: ModelContainer, state: PersistenceState) {
        let outcome = try StoreQuarantine.preserve(storeAt: storeURL, now: now)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try openOnDiskContainer(schema: schema, configuration: configuration)
        AppLog.persistence.notice(
            "Started a fresh store after explicit user consent; the previous store is preserved."
        )
        return (container, .recoveredWithFreshStore(preservedAt: outcome.directory, mode: .local))
    }

    /// Re-attempts the same open, for the recovery surface's "Try Again" action. Purely a
    /// retry: it modifies nothing on disk whether it succeeds or fails.
    static func retryOpening(storeURL: URL) -> Bootstrap {
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return openLocalOrRequestRecovery(
            { try openOnDiskContainer(schema: schema, configuration: configuration) },
            mode: .local
        )
    }

    // MARK: Container builders

    /// Creates a **local-only** container backed by the on-disk store (or an
    /// in-memory store), migrating via the migration plan.
    ///
    /// For an **on-disk** container, if opening fails because a legacy store is
    /// incompatible with the current schema, the store is rebuilt once (ADR-016)
    /// so the app keeps working with real on-disk persistence rather than
    /// silently degrading. The only data lost is the re-seedable default
    /// configuration and any dev-only prior data. In-memory containers never touch
    /// disk and never rebuild.
    ///
    /// Retained parameterless overload (`inMemory:`) so existing call sites and the
    /// whole test suite keep building local containers unchanged.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try makeContainer(mode: .local, inMemory: inMemory)
    }

    /// Creates a container for `mode`. `.local`/`.fallback` build a plain local
    /// store (with the rebuild-on-incompatibility safety net); `.cloudKit` builds a
    /// CloudKit-mirrored store with **no** wipe on failure (a CloudKit problem is
    /// not a reason to destroy local data — the caller's `bootstrap` handles that
    /// by falling back to local).
    static func makeContainer(mode: PersistenceMode, inMemory: Bool = false) throws -> ModelContainer {
        if mode == .cloudKit {
            return try makeCloudKitContainer(inMemory: inMemory)
        }
        // In-memory stores never touch disk (a failure there is a real programming
        // error, so it is surfaced as-is).
        if inMemory {
            return try ModelContainer(
                for: schema,
                migrationPlan: TimeFrameMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
        // On-disk: the URL is resolved explicitly (ADR-110) rather than left to
        // SwiftData's default, so a test host or a redirected developer build cannot
        // silently land on the user's production store. For a normal launch this
        // resolves to exactly the path the app has always used, so existing data is
        // found where it already is.
        let resolution = StoreLocation.resolve()
        StoreLocation.log(resolution)
        let configuration = ModelConfiguration(schema: schema, url: resolution.url)
        return try openOnDiskContainer(schema: schema, configuration: configuration)
    }

    /// Opens an **on-disk** store from `configuration`.
    ///
    /// ## This method no longer deletes anything (ADR-109, supersedes ADR-016)
    /// It used to answer a failed open by removing the store files and building a new
    /// one in their place. That destroyed real user data — irreversibly, with no backup,
    /// no prompt, and a log line as the only trace — whenever *any* error reached the
    /// `catch`: a schema mismatch, yes, but equally a locked file, a denied permission,
    /// or a half-written WAL.
    ///
    /// The store is now left exactly as it is. The failure is classified
    /// (`StoreOpenFailure`) and thrown as a `StoreOpenError` so the caller can preserve,
    /// inform, and ask — the three things that must happen before anyone considers
    /// starting fresh. The only code that moves a store aside is
    /// `startFreshPreservingExistingStore`, and it runs only on an explicit user choice.
    ///
    /// Exposed (with an explicit `configuration`, hence an explicit store URL) so this
    /// path can be exercised hermetically against a temporary store in tests.
    ///
    /// - Throws: `StoreOpenError` carrying the classified failure.
    static func openOnDiskContainer(schema: Schema, configuration: ModelConfiguration) throws -> ModelContainer {
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: TimeFrameMigrationPlan.self,
                configurations: [configuration]
            )
            AppLog.persistence.info(
                "Store opened (schema v\(schemaVersionDescription, privacy: .public))."
            )
            return container
        } catch {
            let failure = StoreOpenFailure.classify(error, storeURL: configuration.url)
            AppLog.persistence.error(
                "Opening on-disk store failed: \(failure.logSummary, privacy: .public). The store was NOT modified."
            )
            throw StoreOpenError(failure: failure)
        }
    }

    /// The active schema version, for logging. Log-safe: a version number, nothing else.
    static var schemaVersionDescription: String {
        let v = TimeFrameSchemaLatest.versionIdentifier
        return "\(v.major).\(v.minor).\(v.patch)"
    }

    /// Creates a CloudKit-mirrored container via SwiftData's native mirroring.
    ///
    /// Uses `cloudKitDatabase: .automatic`, so SwiftData reads the CloudKit
    /// container from the app's iCloud entitlement. With the entitlement present
    /// and an available iCloud account this mirrors the private database; without
    /// it (or if CloudKit is unreachable) container creation throws and the caller
    /// falls back to local (ADR-062). Unlike the local builder this **never**
    /// removes store files on failure — a CloudKit problem must not wipe data.
    private static func makeCloudKitContainer(inMemory: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .automatic
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeFrameMigrationPlan.self,
            configurations: [configuration]
        )
    }

    // `removeStoreFiles(at:)` was deliberately deleted in Milestone 31, not merely left
    // unused. While it existed, the safest-looking `catch` in the file was one line away
    // from erasing a user's history. Preserving a store is now the only option the type
    // offers: see `StoreQuarantine`, which moves files aside and never removes them.
}
