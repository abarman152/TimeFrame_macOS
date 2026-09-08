//
//  CloudKitCapability.swift
//  time_frame
//
//  A pure, testable representation of whether THIS BUILD can use CloudKit at all
//  (Milestone 19 / ADR-080). It separates a **build-time** fact — is the target
//  entitled for iCloud/CloudKit — from the **runtime** fact of iCloud account
//  availability, so the launch-time persistence-mode decision (and the reason sync
//  is off) is explicit and fully unit-testable without a real iCloud account.
//
//  Deliberately CloudKit-free (imports only Foundation), so it stays inside the
//  neutral `Core/` domain and never trips the "no CloudKit import" boundary audit.
//  It owns no timer state, no store, and no scheduling primitive (ADR-060).
//

import Foundation

/// Reports whether the running build carries the iCloud/CloudKit entitlement.
///
/// This is a *build/provisioning* fact, not a runtime one: a CloudKit-mirrored
/// container can only be created when the app is signed with an iCloud container
/// entitlement, which in turn requires a **paid** Apple Developer team. A personal
/// (free) team cannot add the capability, so a free-team build is never entitled —
/// and the correct behaviour is to run local-first, not to attempt (and fail to
/// create) a cloud container on every launch.
///
/// Abstracted behind a protocol so tests can drive both the entitled and the
/// not-entitled branch deterministically, and so the single place that decides
/// "is this build entitled" can be swapped when a paid team ships the entitlement.
nonisolated protocol CloudKitCapabilityProviding: Sendable {
    /// Whether this build is entitled to create a CloudKit-mirrored store.
    var isEntitledForCloudKit: Bool { get }
}

/// The production capability provider.
///
/// It reports the value of `CloudKitCapability.entitledInThisBuild`, the **single
/// honest switch** for the whole app. It is `false` today because the shipping
/// project is signed by a personal (free) Apple Developer team, which cannot carry
/// the iCloud entitlement, so no `*.entitlements` file declares
/// `com.apple.developer.icloud-container-identifiers` (a fabricated entitlement
/// would simply fail to sign). When a paid team adds the real capability +
/// entitlement + container, flip this one constant to `true`; every dependent
/// decision and its tests already exist. See `docs/28-CLOUDKIT-DEVICE-VALIDATION.md`.
nonisolated struct BuildCloudKitCapabilityProvider: CloudKitCapabilityProviding {
    var isEntitledForCloudKit: Bool { CloudKitCapability.entitledInThisBuild }
}

/// The build-time CloudKit capability constant and the pure readiness resolver.
nonisolated enum CloudKitCapability {

    /// Whether *this build* is entitled to use CloudKit.
    ///
    /// **`false`** on the shipping personal-team build: the target has no iCloud
    /// entitlement, so a CloudKit-mirrored container cannot be created and the app
    /// runs local-first. This is not a runtime probe — it states the provisioning
    /// reality honestly rather than pretending the capability is present. Flip to
    /// `true` only in a build actually signed with the iCloud/CloudKit entitlement
    /// and container (a paid Apple Developer team). See ADR-080 and `docs/28-…`.
    static let entitledInThisBuild = false

    /// The resolved launch-time decision: which persistence mode to request, and —
    /// if sync will not be active — the precise reason.
    ///
    /// A pure value so the launch path and its tests agree exactly.
    struct Decision: Equatable, Sendable {
        /// The persistence mode to request from `PersistenceController.bootstrap`.
        let requestedMode: PersistenceMode
        /// Why sync is inactive, or `nil` when CloudKit is being requested and can run.
        let blocker: CloudSyncError?

        /// Whether CloudKit mirroring will actually be requested this launch.
        var willRequestCloud: Bool { requestedMode == .cloudKit }
    }

    /// Resolves the launch-time persistence decision from the three authoritative
    /// inputs. CloudKit is requested **only** when the build is entitled, the user
    /// wants sync, and an iCloud account is available — so the app never constructs a
    /// cloud-backed container it plainly cannot sync, and the reason it stays local
    /// is always a specific, user-explainable one.
    ///
    /// Ordering of the blockers is intentional (most fundamental first): a missing
    /// entitlement is reported as `cloudKitUnavailable` (the build simply cannot
    /// sync), a disabled preference as `syncDisabled`, and a missing account as
    /// `accountUnavailable`.
    ///
    /// - Parameters:
    ///   - entitled: whether the build carries the iCloud/CloudKit entitlement.
    ///   - syncEnabled: the user's "iCloud Sync" preference.
    ///   - account: the iCloud account status.
    static func resolve(
        entitled: Bool,
        syncEnabled: Bool,
        account: CloudAccountStatus
    ) -> Decision {
        guard entitled else {
            // No entitlement → this build cannot sync at all, regardless of the
            // account or preference. Run local-first (never attempt a doomed cloud
            // container). The store still degrades safely if anything else fails.
            return Decision(requestedMode: .local, blocker: .cloudKitUnavailable)
        }
        guard syncEnabled else {
            return Decision(requestedMode: .local, blocker: .syncDisabled)
        }
        guard account != .unavailable else {
            // Entitled and wants sync, but no iCloud account: stay local until the
            // user signs in. (`.unknown` is treated as usable — the store falls back
            // safely if CloudKit turns out to be unreachable.)
            return Decision(requestedMode: .local, blocker: .accountUnavailable)
        }
        return Decision(requestedMode: .cloudKit, blocker: nil)
    }

    /// Convenience overload using the production providers, so the app launch resolves
    /// the decision identically to the tests. Pure aside from reading the injected
    /// providers.
    static func resolve(
        capability: CloudKitCapabilityProviding = BuildCloudKitCapabilityProvider(),
        accountProvider: CloudAccountStatusProviding = SystemCloudAccountStatusProvider(),
        syncEnabled: Bool
    ) -> Decision {
        resolve(
            entitled: capability.isEntitledForCloudKit,
            syncEnabled: syncEnabled,
            account: accountProvider.currentStatus()
        )
    }
}
