//
//  PersistenceState.swift
//  time_frame (Milestone 31)
//
//  What the store is currently doing, as a value the UI can render (ADR-109).
//
//  Before this milestone the store had no failure state to be in: an open that did not
//  succeed was turned into a successful open of a *different, empty* store, and the app
//  above it could not tell the difference. That is precisely the behaviour that let a
//  user's history disappear behind a normal-looking, empty Time Frame.
//
//  Making the failure a state — one the app must handle before it can show a library —
//  is what makes "silently show an empty database" unrepresentable rather than merely
//  discouraged.
//

import Foundation

/// The state of the app's persistent store.
nonisolated enum PersistenceState: Sendable, Equatable {

    /// The store opened. The associated mode says whether CloudKit mirroring is active
    /// (`.cloudKit`), or the store is local either by choice (`.local`) or because a
    /// CloudKit attempt degraded (`.fallback`).
    case ready(PersistenceMode)

    /// The store could not be opened, and **nothing has been deleted**. The app is
    /// running on a scratch in-memory store purely so it can render, and must not present
    /// itself as the user's library until the user decides what to do.
    case needsRecovery(StoreOpenFailure)

    /// The user chose to start fresh. Their previous store was preserved at
    /// `preservedAt`, and the app is now running on a new, empty on-disk store.
    case recoveredWithFreshStore(preservedAt: URL, mode: PersistenceMode)

    /// Whether the app may present itself as showing the user's real, durable library.
    ///
    /// False during `.needsRecovery`: what is on screen then is a scratch store, and the
    /// UI must say so rather than look like an empty library.
    var isShowingDurableData: Bool {
        switch self {
        case .ready, .recoveredWithFreshStore: return true
        case .needsRecovery: return false
        }
    }

    /// The failure the user still has to decide about, if any.
    var pendingFailure: StoreOpenFailure? {
        if case let .needsRecovery(failure) = self { return failure }
        return nil
    }

    /// The active persistence mode, once there is a durable store.
    var mode: PersistenceMode? {
        switch self {
        case let .ready(mode), let .recoveredWithFreshStore(_, mode): return mode
        case .needsRecovery: return nil
        }
    }
}
