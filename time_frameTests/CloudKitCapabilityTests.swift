//
//  CloudKitCapabilityTests.swift
//  time_frameTests (Milestone 19)
//
//  The CloudKit capability-detection seam (ADR-080). These prove the launch-time
//  persistence decision across the full entitled × preference × account matrix,
//  deterministically and with no real iCloud account. They also pin the honest
//  build fact: this personal-team build is NOT entitled for CloudKit.
//

import Foundation
import Testing
@testable import time_frame

@Suite("CloudKit capability & readiness")
struct CloudKitCapabilityTests {

    /// A capability provider whose entitlement is fixed by the test.
    private struct FakeCapability: CloudKitCapabilityProviding {
        let isEntitledForCloudKit: Bool
    }

    /// An account provider whose status is fixed by the test.
    private struct FakeAccount: CloudAccountStatusProviding {
        let status: CloudAccountStatus
        func currentStatus() -> CloudAccountStatus { status }
    }

    // MARK: The honest build fact

    @Test("This build is not entitled for CloudKit (personal team; ADR-080)")
    func buildIsNotEntitled() {
        #expect(CloudKitCapability.entitledInThisBuild == false)
        #expect(BuildCloudKitCapabilityProvider().isEntitledForCloudKit == false)
    }

    // MARK: Not entitled → always local, always for the same reason

    @Test("A non-entitled build never requests CloudKit, whatever the account/preference")
    func notEntitledIsAlwaysLocal() {
        for syncEnabled in [true, false] {
            for account in CloudAccountStatus.allCases {
                let decision = CloudKitCapability.resolve(
                    entitled: false, syncEnabled: syncEnabled, account: account
                )
                #expect(decision.requestedMode == .local)
                #expect(decision.willRequestCloud == false)
                #expect(decision.blocker == .cloudKitUnavailable,
                        "non-entitled build should report cloudKitUnavailable (\(syncEnabled), \(account))")
            }
        }
    }

    // MARK: Entitled matrix

    @Test("Entitled + sync off → local, reason syncDisabled")
    func entitledSyncOff() {
        for account in CloudAccountStatus.allCases {
            let decision = CloudKitCapability.resolve(
                entitled: true, syncEnabled: false, account: account
            )
            #expect(decision.requestedMode == .local)
            #expect(decision.blocker == .syncDisabled)
        }
    }

    @Test("Entitled + sync on + no account → local, reason accountUnavailable")
    func entitledNoAccount() {
        let decision = CloudKitCapability.resolve(
            entitled: true, syncEnabled: true, account: .unavailable
        )
        #expect(decision.requestedMode == .local)
        #expect(decision.blocker == .accountUnavailable)
    }

    @Test("Entitled + sync on + account available → requests CloudKit, no blocker")
    func entitledReady() {
        let decision = CloudKitCapability.resolve(
            entitled: true, syncEnabled: true, account: .available
        )
        #expect(decision.requestedMode == .cloudKit)
        #expect(decision.willRequestCloud)
        #expect(decision.blocker == nil)
    }

    @Test("Entitled + sync on + account unknown is treated as usable (store degrades safely)")
    func entitledUnknownAccount() {
        let decision = CloudKitCapability.resolve(
            entitled: true, syncEnabled: true, account: .unknown
        )
        #expect(decision.requestedMode == .cloudKit)
        #expect(decision.blocker == nil)
    }

    // MARK: Provider-driven overload matches the pure resolver

    @Test("The provider overload resolves identically to the pure resolver")
    func providerOverloadMatches() {
        let decision = CloudKitCapability.resolve(
            capability: FakeCapability(isEntitledForCloudKit: true),
            accountProvider: FakeAccount(status: .available),
            syncEnabled: true
        )
        #expect(decision == CloudKitCapability.resolve(
            entitled: true, syncEnabled: true, account: .available
        ))
        #expect(decision.requestedMode == .cloudKit)
    }

    @Test("With the real build provider the app stays local (no doomed cloud container)")
    func realProviderStaysLocal() {
        // Mirrors exactly what the app launch computes: the personal-team build is
        // not entitled, so CloudKit is never requested and the app runs local-first.
        let decision = CloudKitCapability.resolve(
            accountProvider: FakeAccount(status: .available),
            syncEnabled: true
        )
        #expect(decision.requestedMode == .local)
        #expect(decision.blocker == .cloudKitUnavailable)
    }
}
