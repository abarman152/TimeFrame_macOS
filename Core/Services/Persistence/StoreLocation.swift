//
//  StoreLocation.swift
//  time_frame (Milestone 31)
//
//  Where the app's SwiftData store lives — decided explicitly, once (ADR-110).
//
//  ## Why this exists
//  The macOS app is **not sandboxed**, so its default SwiftData store is a single shared
//  file: `~/Library/Application Support/default.store`, keyed by nothing more specific
//  than the process's Application Support directory. Every build of Time Frame on a
//  machine — the installed copy, a Debug build from Xcode, a build launched by tooling —
//  resolved to that same file and to the same `UserDefaults` domain.
//
//  That is how a locally built copy came to open, and then destroy, a real user's store.
//  Nothing warned, because nothing had ever stated where the store was supposed to be.
//
//  This type makes the choice explicit and, more importantly, makes the *production*
//  store something a development or test process has to opt into rather than something it
//  gets by default:
//
//  - a normal launch uses the production store;
//  - the XCTest host uses an isolated store under the temporary directory, never the
//    production one, even if a test forgets to pass a URL;
//  - a developer can redirect any build with `TIMEFRAME_STORE_DIRECTORY`.
//
//  It performs no I/O beyond creating the directory it returns, opens no database, and is
//  pure enough to test every branch by injecting an environment dictionary.
//

import Foundation
import os

/// Resolves the on-disk location of the app's store.
nonisolated enum StoreLocation {

    /// The store file's name, unchanged from every prior version so an existing
    /// production store is found exactly where it already is.
    static let storeFileName = "default.store"

    /// Environment key that redirects the store to a different directory.
    ///
    /// Set it on a scheme's Run action to develop against a scratch store:
    /// `TIMEFRAME_STORE_DIRECTORY=/tmp/timeframe-dev`
    static let directoryOverrideKey = "TIMEFRAME_STORE_DIRECTORY"

    /// How the active store location was arrived at. Carried so the app can say so in
    /// diagnostics, and so a test can assert *which* rule applied rather than just
    /// comparing paths.
    enum Origin: String, Sendable, Equatable {
        /// The real user's store.
        case production
        /// Redirected by `TIMEFRAME_STORE_DIRECTORY`.
        case environmentOverride
        /// An isolated store because this process hosts XCTest.
        case testHostIsolated
    }

    struct Resolution: Sendable, Equatable {
        let url: URL
        let origin: Origin

        /// True only for the real user's store. The guard rails read this rather than
        /// re-deriving the rule.
        var isProduction: Bool { origin == .production }
    }

    /// Resolves where this process should keep its store.
    ///
    /// Precedence, highest first:
    /// 1. `TIMEFRAME_STORE_DIRECTORY` — an explicit developer choice always wins.
    /// 2. XCTest host — isolated, so a test that forgets to pass a URL still cannot reach
    ///    production data.
    /// 3. Production.
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> Resolution {
        if let override = environment[directoryOverrideKey], !override.isEmpty {
            let directory = URL(fileURLWithPath: override, isDirectory: true)
            return Resolution(url: store(in: directory, fileManager: fileManager),
                              origin: .environmentOverride)
        }

        if TestHostEnvironment.isHostingUnitTests(environment: environment) {
            let directory = fileManager.temporaryDirectory
                .appendingPathComponent("TimeFrameTestStores", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            return Resolution(url: store(in: directory, fileManager: fileManager),
                              origin: .testHostIsolated)
        }

        return Resolution(url: store(in: productionDirectory(fileManager: fileManager),
                                     fileManager: fileManager),
                          origin: .production)
    }

    /// The production store's URL, with no isolation rules applied.
    ///
    /// This is the path a real user's data occupies. It is deliberately a separate,
    /// explicitly-named function: anything that wants the user's real store has to ask for
    /// it by this name, which makes such call sites easy to find and to audit.
    static func productionStoreURL(fileManager: FileManager = .default) -> URL {
        productionDirectory(fileManager: fileManager).appendingPathComponent(storeFileName)
    }

    /// `~/Library/Application Support` — where SwiftData's default store already lives, so
    /// the production path is unchanged by this milestone.
    private static func productionDirectory(fileManager: FileManager) -> URL {
        if let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return url
        }
        // Defensive only — the search path above does not fail in practice. `NSHomeDirectory()`
        // is used rather than `homeDirectoryForCurrentUser`, which is macOS-only, because this
        // file compiles into the iOS app as well.
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// The store file inside `directory`, creating the directory if needed.
    private static func store(in directory: URL, fileManager: FileManager) -> URL {
        // Best effort: if this fails the container open will fail and be classified and
        // reported, which is the correct outcome — never a silent fallback elsewhere.
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(storeFileName)
    }

    /// Whether `url` is the real user's production store.
    ///
    /// Used by the test-safety guard so a destructive test can assert, in-process, that it
    /// is not about to operate on production data.
    static func isProductionStore(_ url: URL, fileManager: FileManager = .default) -> Bool {
        url.standardizedFileURL == productionStoreURL(fileManager: fileManager).standardizedFileURL
    }

    /// Traps if `url` is the production store.
    ///
    /// Destructive persistence tests call this before they touch a path. It is a
    /// programming-error guard, not error handling: a test that reaches the user's real
    /// store has a bug that must stop the suite, not be reported and continued past.
    static func assertNotProductionStore(
        _ url: URL,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        precondition(
            !isProductionStore(url),
            "Refusing to operate on the production store at \(url.path).",
            file: file, line: line
        )
    }

    /// Logs the resolved location once at launch, so a support report says which store the
    /// process actually used. Logs the *origin*, and only the store's file name — never the
    /// user's home directory path.
    static func log(_ resolution: Resolution) {
        AppLog.persistence.info(
            "Store location resolved: origin=\(resolution.origin.rawValue, privacy: .public), file=\(resolution.url.lastPathComponent, privacy: .public)."
        )
    }
}
