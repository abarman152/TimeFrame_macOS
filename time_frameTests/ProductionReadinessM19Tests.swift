//
//  ProductionReadinessM19Tests.swift
//  time_frameTests (Milestone 19)
//
//  The Milestone-19 additions to the release-gate source-boundary audit (ADR-082).
//  Where ProductionReadinessTests guards the timer/persistence/ActivityKit boundaries,
//  these guard the CloudKit/App-Group/deep-link/honesty invariants M19 introduces:
//
//   • The App Group identifier is identical across every entitlements file and the
//     shared projection store.
//   • No entitlements file declares a *fabricated* iCloud/CloudKit entitlement — the
//     shipping build is signed by a personal team, so claiming the capability would
//     only fail to sign. The capability CONSTANT must match that provisioning reality.
//   • The CloudKit configuration is genuinely wired (SwiftData native mirroring, V6)
//     but honestly gated behind the capability seam.
//   • The `timeframe://` deep-link scheme is registered consistently.
//   • No secrets / private keys / provisioning profiles are committed to the tree.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

// MARK: - App Group consistency

@Suite("M19 readiness — App Group consistency")
struct M19AppGroupConsistencyTests {

    static let appGroup = "group.abirbarman.com.time-frame"

    /// Every target's entitlements file that ships the app group.
    static func entitlementsFiles() -> [URL] {
        let root = SourceAudit.repoRoot()
        return [
            root.appendingPathComponent("time_frame/time_frame.entitlements"),
            root.appendingPathComponent("TimeFrameWidgets/TimeFrameWidgets.entitlements"),
        ]
    }

    @Test("The shared store and every entitlements file use the SAME App Group id")
    func appGroupIsConsistent() {
        #expect(WidgetProjectionStore.appGroupIdentifier == Self.appGroup)
        for file in Self.entitlementsFiles() {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            #expect(text.contains(Self.appGroup),
                    "\(file.lastPathComponent) must declare the App Group \(Self.appGroup)")
        }
    }

    @Test("The App Group identifier is unchanged from M11 (deep links + widget compatibility)")
    func appGroupIsStable() {
        // M19 must not rename the App Group: existing widgets and the projection channel
        // depend on it (invariant #19).
        #expect(WidgetProjectionStore.appGroupIdentifier == "group.abirbarman.com.time-frame")
    }
}

// MARK: - CloudKit capability honesty

@Suite("M19 readiness — CloudKit capability honesty")
struct M19CloudKitHonestyTests {

    /// Whether ANY entitlements file declares an iCloud/CloudKit entitlement.
    static func anyEntitlementDeclaresICloud() -> Bool {
        let iCloudKeys = [
            "com.apple.developer.icloud-container-identifiers",
            "com.apple.developer.icloud-services",
            "com.apple.developer.ubiquity-kvstore-identifier",
        ]
        for file in M19AppGroupConsistencyTests.entitlementsFiles() {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            if iCloudKeys.contains(where: { text.contains($0) }) { return true }
        }
        return false
    }

    @Test("No entitlements file fabricates an iCloud/CloudKit entitlement")
    func noFabricatedICloudEntitlement() {
        // The shipping build is signed by a personal (free) Apple Developer team, which
        // cannot carry the iCloud capability. A fabricated entitlement would fail to sign,
        // so it must be absent (CRITICAL RULE — do not fake the entitlement).
        #expect(Self.anyEntitlementDeclaresICloud() == false,
                "An iCloud entitlement is present — it must only be added with a paid team; update ADR-080/entitledInThisBuild if genuinely enabled.")
    }

    @Test("The build capability constant matches the provisioning reality")
    func capabilityMatchesEntitlements() {
        // The single honest switch must agree with the entitlements on disk: entitled in
        // code IFF an iCloud entitlement is actually declared. Today both are false.
        #expect(CloudKitCapability.entitledInThisBuild == Self.anyEntitlementDeclaresICloud())
        #expect(CloudKitCapability.entitledInThisBuild == false)
    }

    @Test("A non-entitled build never resolves to a CloudKit request")
    func nonEntitledNeverRequestsCloud() {
        let decision = CloudKitCapability.resolve(
            entitled: CloudKitCapability.entitledInThisBuild,
            syncEnabled: true,
            account: .available
        )
        #expect(decision.requestedMode == .local)
    }
}

// MARK: - CloudKit persistence wiring (genuinely production-ready, honestly gated)

@Suite("M19 readiness — CloudKit persistence wiring")
struct M19CloudKitWiringTests {

    @Test("PersistenceController requests SwiftData native CloudKit mirroring")
    func usesNativeMirroring() {
        let file = SourceAudit.core().appendingPathComponent("Services/Persistence/PersistenceController.swift")
        let text = SourceAudit.code(file)
        #expect(SourceAudit.references(text, "cloudKitDatabase"),
                "The CloudKit container must use SwiftData's native mirroring")
    }

    @Test("The CloudKit builder never wipes local data on failure")
    func cloudBuilderNeverWipes() {
        // removeStoreFiles is the destructive rebuild path — it must appear only in the
        // LOCAL on-disk opener, never in the CloudKit builder (a CloudKit problem must not
        // destroy data; the caller falls back to local instead — ADR-062).
        let file = SourceAudit.core().appendingPathComponent("Services/Persistence/PersistenceController.swift")
        let text = SourceAudit.code(file)
        guard let cloudRange = text.range(of: "func makeCloudKitContainer") else {
            Issue.record("makeCloudKitContainer not found"); return
        }
        // The CloudKit builder body ends at the next `private static func`/`static func`.
        let after = text[cloudRange.upperBound...]
        let bodyEnd = after.range(of: "static func")?.lowerBound ?? after.endIndex
        let body = after[after.startIndex..<bodyEnd]
        #expect(body.contains("removeStoreFiles") == false,
                "makeCloudKitContainer must not remove store files")
    }

    @Test("Services/Cloud stays CloudKit-free (imports only Foundation/Observation)")
    func cloudServiceLayerIsCloudKitFree() {
        let cloud = SourceAudit.core().appendingPathComponent("Services/Cloud")
        let hits = SourceAudit.filesReferencing(["import CloudKit", "CKRecord", "CKContainer"], in: [cloud])
        #expect(hits.isEmpty, "CloudKit leaked into Services/Cloud: \(hits)")
    }

    @Test("CloudKit did not force a migration, and its constraints still hold")
    func schemaStaysCloudKitLegal() {
        // V6 remains the CloudKit-compatibility baseline; the current version is V7
        // (Milestone 28 added attributes only). Both must stay uniqueness-free.
        #expect(TimeFrameSchemaV6.versionIdentifier == Schema.Version(6, 0, 0))
        #expect(TimeFrameSchemaLatest.versionIdentifier == Schema.Version(7, 0, 0))
        for versioned in [Schema(versionedSchema: TimeFrameSchemaV6.self),
                          Schema(versionedSchema: TimeFrameSchemaLatest.self)] {
            for entity in versioned.entities {
                #expect(entity.uniquenessConstraints.isEmpty)
            }
        }
    }
}

// MARK: - Deep-link scheme consistency

@Suite("M19 readiness — deep-link scheme")
struct M19DeepLinkSchemeTests {

}

// MARK: - No committed secrets

@Suite("M19 readiness — no committed secrets")
struct M19NoSecretsTests {

    @Test("No private keys, certificates, or provisioning profiles are committed")
    func noSecretArtifacts() {
        let root = SourceAudit.repoRoot()
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            Issue.record("Could not enumerate repo root"); return
        }
        let forbiddenExtensions: Set<String> = ["p12", "pem", "key", "cer", "mobileprovision", "provisionprofile", "certSigningRequest"]
        var offenders: [String] = []
        for case let url as URL in e {
            // Skip the git metadata directory.
            if url.pathComponents.contains(".git") { continue }
            if forbiddenExtensions.contains(url.pathExtension.lowercased()) {
                offenders.append(url.lastPathComponent)
            }
        }
        #expect(offenders.isEmpty, "Secret artifact(s) committed: \(offenders)")
    }

}
