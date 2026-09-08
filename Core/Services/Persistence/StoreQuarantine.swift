//
//  StoreQuarantine.swift
//  time_frame (Milestone 31)
//
//  Preserving a store that could not be opened, instead of deleting it (ADR-109).
//
//  ## The rule
//  Time Frame never removes a store because opening it failed. When the user explicitly
//  chooses to start fresh, the existing store is **moved aside** into a timestamped
//  recovery folder — it is not erased, and it never overwrites an earlier recovery copy.
//  The user can hand that folder to a future version of the app, to `sqlite3`, or to
//  support, and their history is still there.
//
//  Quarantine is only ever invoked from an explicit user decision. Nothing on the launch
//  path calls it (§20): a failed open leaves every byte where it was.
//
//  ## Why move, not copy
//  A copy would leave the unopenable store in place, so the next launch would fail exactly
//  the same way and the user would be stuck in a loop. Moving clears the path for a fresh
//  store while keeping the original intact. If the move cannot be performed, the operation
//  **fails** and the caller must not proceed — it never falls back to deleting.
//
//  ## The sidecar files
//  A SwiftData store is three files: `X.store`, `X.store-wal`, `X.store-shm`. The WAL can
//  hold committed transactions that are not yet in the main file, so preserving only the
//  `.store` would silently discard recent work. All three move together, into the same
//  folder, keeping their names — which is exactly the layout SQLite expects if the set is
//  later reopened.
//

import Foundation
import os

/// Moves unopenable stores aside so they can be recovered later. Pure filesystem work; it
/// holds no store handles and opens no database.
nonisolated enum StoreQuarantine {

    /// The name of the folder recovery copies are collected in, beside the store itself.
    static let directoryName = "TimeFrame Recovery"

    /// The sidecar suffixes that make up a complete SwiftData/SQLite store.
    static let storeSuffixes = ["", "-wal", "-shm"]

    /// The result of preserving a store.
    struct Outcome: Sendable, Equatable {
        /// The folder the store now lives in.
        let directory: URL
        /// The files that were actually moved (a store may legitimately have no `-wal`).
        let movedFiles: [URL]
    }

    /// Errors that stop a store being preserved. Each one means: **do not continue**, and
    /// above all do not delete anything.
    enum QuarantineError: Error, Equatable {
        /// The recovery folder could not be created.
        case couldNotCreateDirectory(String)
        /// A store file could not be moved. Carries the file's last path component only.
        case couldNotMove(file: String, reason: String)
        /// There was no store at the given URL to preserve.
        case nothingToPreserve
    }

    /// The folder recovery copies live in, for a store at `storeURL`.
    ///
    /// Kept beside the store rather than in a system location, so a user who finds their
    /// data folder finds their recovery copies in the same place.
    static func recoveryRoot(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Every file that makes up the store at `storeURL` and currently exists on disk.
    static func existingStoreFiles(at storeURL: URL, fileManager: FileManager = .default) -> [URL] {
        storeSuffixes
            .map { sidecarURL(for: storeURL, suffix: $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// The URL of one sidecar of a store — `X.store` → `X.store-wal`.
    ///
    /// Built by appending to the *path*, which is how SQLite names these files. Composing
    /// them through `deletingPathExtension`/`appendingPathExtension` mangles a store whose
    /// name contains a dot, so this deliberately does not do that.
    static func sidecarURL(for storeURL: URL, suffix: String) -> URL {
        suffix.isEmpty ? storeURL : URL(fileURLWithPath: storeURL.path + suffix)
    }

    /// Moves the store at `storeURL` (and its sidecars) into a fresh, uniquely named
    /// folder under the recovery root, and returns where they went.
    ///
    /// The folder name carries a filesystem-safe UTC timestamp plus a short unique
    /// suffix, so two recoveries in the same second cannot collide and an existing
    /// recovery copy is never overwritten.
    ///
    /// - Throws: `QuarantineError` if the folder cannot be created or a file cannot be
    ///   moved. On failure the original files are left exactly as they were.
    @discardableResult
    static func preserve(
        storeAt storeURL: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> Outcome {
        let files = existingStoreFiles(at: storeURL, fileManager: fileManager)
        guard !files.isEmpty else { throw QuarantineError.nothingToPreserve }

        let directory = try makeUniqueDirectory(under: recoveryRoot(for: storeURL),
                                                now: now,
                                                fileManager: fileManager)

        var moved: [URL] = []
        for file in files {
            let destination = directory.appendingPathComponent(file.lastPathComponent)
            do {
                try fileManager.moveItem(at: file, to: destination)
                moved.append(destination)
            } catch {
                // Stop at the first failure. Whatever moved is already safe in the
                // recovery folder, and whatever did not is still in place. Nothing is
                // deleted either way.
                AppLog.persistence.error(
                    "Could not preserve store file \(file.lastPathComponent, privacy: .public)."
                )
                throw QuarantineError.couldNotMove(
                    file: file.lastPathComponent,
                    reason: (error as NSError).localizedDescription
                )
            }
        }

        AppLog.persistence.notice(
            "Store preserved: \(moved.count, privacy: .public) file(s) moved to a recovery folder. Nothing was deleted."
        )
        return Outcome(directory: directory, movedFiles: moved)
    }

    /// Creates a new, empty, uniquely named folder under `root`.
    ///
    /// Uniqueness is not assumed from the timestamp alone: the directory is created with
    /// `withIntermediateDirectories: false` so an existing folder is an error rather than
    /// a silent reuse, and a fresh suffix is tried on collision.
    private static func makeUniqueDirectory(
        under root: URL,
        now: Date,
        fileManager: FileManager
    ) throws -> URL {
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw QuarantineError.couldNotCreateDirectory((error as NSError).localizedDescription)
        }

        let stamp = timestamp(from: now)
        for attempt in 0..<16 {
            let name = attempt == 0 ? stamp : "\(stamp)-\(shortToken())"
            let candidate = root.appendingPathComponent(name, isDirectory: true)
            do {
                try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
                return candidate
            } catch {
                let nsError = error as NSError
                // Only a genuine "already exists" is worth retrying with a new name.
                let alreadyExists = nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteFileExistsError
                guard alreadyExists else {
                    throw QuarantineError.couldNotCreateDirectory(nsError.localizedDescription)
                }
            }
        }
        throw QuarantineError.couldNotCreateDirectory("Could not find an unused recovery folder name.")
    }

    /// A filesystem-safe UTC timestamp: `2026-09-07T13-42-10Z`.
    ///
    /// Fixed to UTC and the POSIX locale so the folder name is stable and sortable
    /// regardless of the user's region, and contains no `:` (illegal in a path component
    /// as displayed by Finder).
    static func timestamp(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d-%02d-%02dZ",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    private static func shortToken() -> String {
        String(UUID().uuidString.prefix(8))
    }
}
