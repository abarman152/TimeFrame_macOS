//
//  StoreOpenFailure.swift
//  time_frame (Milestone 31)
//
//  Why a SwiftData store could not be opened — classified, rather than assumed.
//
//  ## Why this type exists (ADR-109)
//  Until Milestone 31 the store had exactly one answer for "opening failed": delete the
//  user's data and build a fresh store in its place (ADR-016). That answer treated every
//  failure as though it were a schema incompatibility in a developer's throwaway store.
//  It is not: a locked file, a denied permission, a half-written WAL, or a genuine
//  migration bug all reach the same `catch`, and all of them were answered by destroying
//  the only copy of the user's history.
//
//  Classifying the failure is the first half of the fix. It decides what the app tells the
//  user, what it offers to do, and — critically — it makes "we do not actually know what
//  went wrong" an explicit outcome (`.unknown`) rather than a licence to erase.
//
//  The type is pure and `Sendable`: it holds codes and descriptions, never an open store
//  handle and never user content. It is safe to log (§19) and safe to carry across actors.
//

import Foundation

/// The kind of failure that stopped a store from opening.
///
/// Deliberately finer-grained than the app strictly needs today: the point is that a
/// permission problem can never again be mistaken for corruption, because the two are
/// different cases in one closed enum.
nonisolated enum StoreOpenFailureKind: String, Sendable, Equatable, CaseIterable {
    /// The store's model hashes do not match the current schema — an upgrade that needs a
    /// migration path the plan does not provide.
    case schemaMismatch
    /// A migration was attempted and failed part-way.
    case migrationFailed
    /// The file is a database, but its contents are damaged.
    case storeCorrupt
    /// The file exists but is not a database at all (or its header is unreadable).
    case malformedStore
    /// The file could not be read or written for a filesystem reason other than permissions.
    case fileAccessFailed
    /// The process is not permitted to read or write the store.
    case permissionDenied
    /// Another process (or another connection) holds the store.
    case fileLocked
    /// None of the above could be established from the error.
    case unknown

    /// Whether the underlying data is plausibly still intact and worth preserving.
    ///
    /// Every case answers `true` except none — that is the point. Even a corrupt store is
    /// preserved: "corrupt" is a diagnosis made from an error code, not a certainty, and a
    /// damaged SQLite file is very often still readable by recovery tooling. Nothing in
    /// this app deletes a store because of a value returned here.
    var warrantsPreservation: Bool { true }

    /// Whether retrying the same open could plausibly succeed without the user doing
    /// anything. A lock clears on its own; a schema mismatch never does.
    var isTransient: Bool {
        switch self {
        case .fileLocked: return true
        case .schemaMismatch, .migrationFailed, .storeCorrupt, .malformedStore,
             .fileAccessFailed, .permissionDenied, .unknown: return false
        }
    }

    /// A short, non-technical explanation for the recovery surface. States the situation;
    /// never blames the user and never promises the data is gone.
    var userExplanation: String {
        switch self {
        case .schemaMismatch:
            return "Your data was saved by a different version of Time Frame and needs an update this version can't perform."
        case .migrationFailed:
            return "Time Frame started updating your data to a new format and couldn't finish."
        case .storeCorrupt:
            return "Your data file appears to be damaged."
        case .malformedStore:
            return "The file where your data is kept isn't in a format Time Frame recognises."
        case .fileAccessFailed:
            return "Time Frame couldn't read the file where your data is kept."
        case .permissionDenied:
            return "Time Frame doesn't have permission to read the file where your data is kept."
        case .fileLocked:
            return "Another copy of Time Frame appears to be using your data."
        case .unknown:
            return "Time Frame couldn't open your data, and couldn't determine why."
        }
    }

    /// The most useful next step for this particular failure, in one line.
    var userSuggestion: String {
        switch self {
        case .fileLocked:
            return "Quit any other copy of Time Frame, then try again."
        case .permissionDenied:
            return "Check the file's permissions in Finder, then try again."
        case .schemaMismatch, .migrationFailed:
            return "Reinstalling the newest version of Time Frame may be able to complete the update."
        case .storeCorrupt, .malformedStore, .fileAccessFailed, .unknown:
            return "Your data has not been deleted. You can keep a copy and start fresh."
        }
    }
}

/// A classified store-open failure: what kind, where, and the raw diagnosis.
///
/// `underlying` is a **string**, not an `Error`, so the value stays `Sendable` and
/// log-safe — the same convention `PersistenceError` already uses.
nonisolated struct StoreOpenFailure: Sendable, Equatable {
    let kind: StoreOpenFailureKind
    /// The store the app was trying to open.
    let storeURL: URL
    /// The error's domain and code, kept for diagnosis. Never user content.
    let domain: String
    let code: Int
    /// A description of the original error, for the log and for a diagnostics view.
    let underlying: String

    init(kind: StoreOpenFailureKind, storeURL: URL, domain: String, code: Int, underlying: String) {
        self.kind = kind
        self.storeURL = storeURL
        self.domain = domain
        self.code = code
        self.underlying = underlying
    }

    /// A one-line, log-safe summary: the classification and the codes, never the path's
    /// user-visible content beyond its last component.
    var logSummary: String {
        "\(kind.rawValue) (\(domain) \(code))"
    }
}

// MARK: - Classification

extension StoreOpenFailure {

    /// Classifies a store-open error.
    ///
    /// Reads the Cocoa/Core Data error domain and code, plus the `NSSQLiteErrorDomain`
    /// code Core Data nests in `userInfo`, which is usually the only place the real cause
    /// (not-a-database, corrupt, busy) is actually stated. Anything it cannot place
    /// becomes `.unknown` — never a default of "corrupt", because that default is what
    /// justified deleting data.
    static func classify(_ error: Error, storeURL: URL) -> StoreOpenFailure {
        let nsError = error as NSError
        let kind = classifyKind(domain: nsError.domain,
                                code: nsError.code,
                                sqliteCode: sqliteCode(in: nsError))
        return StoreOpenFailure(
            kind: kind,
            storeURL: storeURL,
            domain: nsError.domain,
            code: nsError.code,
            underlying: String(describing: error)
        )
    }

    /// The pure decision, split out so tests can drive every branch without having to
    /// manufacture a real Core Data failure for each one.
    static func classifyKind(domain: String, code: Int, sqliteCode: Int?) -> StoreOpenFailureKind {
        // The nested SQLite code is the most specific signal when it is present.
        if let sqliteCode {
            switch sqliteCode {
            case 26: return .malformedStore      // SQLITE_NOTADB — "file is not a database"
            case 11: return .storeCorrupt        // SQLITE_CORRUPT
            case 5, 6: return .fileLocked        // SQLITE_BUSY / SQLITE_LOCKED
            case 8: return .permissionDenied     // SQLITE_READONLY
            case 14: return .fileAccessFailed    // SQLITE_CANTOPEN
            default: break
            }
        }

        switch domain {
        case NSCocoaErrorDomain:
            switch code {
            case 134100: return .schemaMismatch          // NSPersistentStoreIncompatibleVersionHashError
            case 134110, 134120, 134130, 134140, 134170: return .migrationFailed
            case 134080: return .fileAccessFailed        // NSPersistentStoreOpenError
            case 257, 513: return .permissionDenied      // NSFileRead/WriteNoPermissionError
            case 259: return .malformedStore             // NSFileReadCorruptFileError
            case 260: return .fileAccessFailed           // NSFileNoSuchFileError
            default: return .unknown
            }
        case "NSSQLiteErrorDomain":
            return .storeCorrupt
        default:
            return .unknown
        }
    }

    /// Digs the `NSSQLiteErrorDomain` code out of a Core Data error's `userInfo`, at the
    /// top level or inside a nested underlying error.
    private static func sqliteCode(in error: NSError) -> Int? {
        if let value = error.userInfo["NSSQLiteErrorDomain"] as? Int { return value }
        if let nested = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            if let value = nested.userInfo["NSSQLiteErrorDomain"] as? Int { return value }
            if nested.domain == "NSSQLiteErrorDomain" { return nested.code }
        }
        return nil
    }
}

/// The error the persistence layer throws when a store cannot be opened, carrying the
/// classification with it so callers never have to re-diagnose.
nonisolated struct StoreOpenError: Error, Sendable, Equatable {
    let failure: StoreOpenFailure
}
