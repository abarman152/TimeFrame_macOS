//
//  CloudSyncError.swift
//  time_frame
//
//  The closed set of reasons iCloud sync may be inactive. A plain value type with
//  no CloudKit framework types, so it can flow into the UI and tests (Milestone 13).
//

import Foundation

/// Why iCloud sync is not currently active.
///
/// A *closed* enum (like `TimeFrameIntentError`) so the reason surfaced to the user
/// is always one the app understands and phrases itself — never a leaked
/// CloudKit/SwiftData error. It describes a situation, never blocks the timer.
nonisolated enum CloudSyncError: String, Equatable, Sendable, CaseIterable, LocalizedError {
    /// The user has turned iCloud sync off in Settings.
    case syncDisabled
    /// No iCloud account is available (the user is not signed in to iCloud).
    case accountUnavailable
    /// CloudKit could not be initialised (missing entitlement / container), so the
    /// app fell back to the local store.
    case cloudKitUnavailable

    var errorDescription: String? {
        switch self {
        case .syncDisabled:       return "iCloud Sync is turned off."
        case .accountUnavailable: return "You're not signed in to iCloud."
        case .cloudKitUnavailable: return "iCloud is currently unavailable."
        }
    }

    /// The reason (if any) sync is inactive for the given mode/account/preference.
    /// `nil` means sync is active. Pure, so it is fully unit-testable.
    static func reason(
        mode: PersistenceMode,
        account: CloudAccountStatus,
        syncEnabled: Bool
    ) -> CloudSyncError? {
        switch mode {
        case .cloudKit:
            return account == .unavailable ? .accountUnavailable : nil
        case .fallback:
            return account == .unavailable ? .accountUnavailable : .cloudKitUnavailable
        case .local:
            return syncEnabled ? .accountUnavailable : .syncDisabled
        }
    }
}
