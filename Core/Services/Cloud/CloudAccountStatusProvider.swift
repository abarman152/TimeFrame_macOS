//
//  CloudAccountStatusProvider.swift
//  time_frame
//
//  Reports whether an iCloud account is available, without importing CloudKit.
//

import Foundation

/// Supplies the current iCloud account availability. Abstracted so the coordinator
/// can be driven by a fake in tests (no real iCloud account required).
///
/// Deliberately CloudKit-free: availability is inferred from Foundation's iCloud
/// *ubiquity identity*, which is present only when the user is signed in to iCloud
/// and the app is entitled for it. The provider never reads the account identifier
/// itself — only whether one exists — so no personal information is handled.
nonisolated protocol CloudAccountStatusProviding: Sendable {
    func currentStatus() -> CloudAccountStatus
}

/// The production provider: reports `.available` when an iCloud ubiquity identity
/// exists, `.unavailable` otherwise.
nonisolated struct SystemCloudAccountStatusProvider: CloudAccountStatusProviding {
    func currentStatus() -> CloudAccountStatus {
        FileManager.default.ubiquityIdentityToken != nil ? .available : .unavailable
    }
}
