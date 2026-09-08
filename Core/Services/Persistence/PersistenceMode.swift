//
//  PersistenceMode.swift
//  time_frame
//
//  How the app's SwiftData store is backed: local-only, CloudKit-mirrored, or a
//  safe fallback to local after CloudKit could not be initialised (Milestone 13).
//

import Foundation

/// How the SwiftData store is backed at runtime.
///
/// This is a **persistence-transport** concern, not a timer concern: the timer
/// derives `remaining` from its authoritative clock regardless of this value, and
/// nothing here ever participates in the countdown (ADR-060). CloudKit sits below
/// the repositories via SwiftData's native mirroring — there is no second store and
/// no custom sync engine.
///
/// A pure, `Sendable` value with no CloudKit types, so it can flow freely into the
/// presentation layer and tests.
nonisolated enum PersistenceMode: String, Equatable, Sendable, CaseIterable {
    /// Local-only. No CloudKit mirroring is requested (the user turned iCloud sync
    /// off, or the build has no iCloud entitlement). The store works fully offline.
    case local

    /// CloudKit-mirrored. The store is backed by SwiftData's private-database
    /// CloudKit mirroring. It remains **local-first**: reads and writes hit the
    /// local store immediately and sync happens in the background, eventually.
    case cloudKit

    /// Fallback. CloudKit mirroring was requested but could not be initialised
    /// (no account, missing entitlement, CloudKit unavailable, …), so the app fell
    /// back to the **existing local store**. Data is preserved and fully usable;
    /// only cross-device sync is inactive. Distinct from `.local` so the UI can
    /// explain *why* sync is off.
    case fallback

    /// Whether CloudKit mirroring is actually active in this mode.
    var isCloudActive: Bool { self == .cloudKit }
}
