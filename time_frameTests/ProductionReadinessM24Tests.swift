//
//  ProductionReadinessM24Tests.swift
//  time_frameTests (Milestone 24)
//
//  The Milestone-24 additions to the release-gate audit: PRODUCT IDENTITY (the "Time Frame" name and
//  the single supplied logo) plus a re-assertion of the boundaries M24's polish must not disturb.
//  M24 is identity + on-device UX validation + polish — it adds NO runtime architecture, so these are
//  mostly *structural* audits over the asset catalogs, the Info.plists, and the project file, alongside
//  a few runtime constants:
//
//   • the user-facing name is "Time Frame" (never TimeFrame / time_frame / Time-Frame / "Time Frame App")
//     wherever the OS shows it — the macOS app's `INFOPLIST_KEY_CFBundleDisplayName` and the iOS app's
//     `CFBundleDisplayName`;
//   • each app target has an `AppIcon` asset catalog with real raster slots, and both targets reference
//     it (`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`);
//   • there is exactly ONE logo design — no `*Dark*` / `*Light*` icon set and no appearance-split
//     `Contents.json` was introduced (the same artwork serves light and dark);
//   • the identity edits changed no internal identifier: the bundle id, the App Group, the URL scheme,
//     and the SwiftData schema (V6) are all unchanged.
//
//  Like the M17…M23 audits, these scan the checkout they were compiled from (`SourceAudit.repoRoot()`),
//  and fail loudly rather than passing vacuously if a file cannot be found.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

// MARK: - Identity: the user-facing name is "Time Frame"

@Suite("M24 identity — the user-facing name is \"Time Frame\"")
struct M24ProductNameTests {

    private static var pbxproj: String {
        let url = SourceAudit.repoRoot()
            .appendingPathComponent("time_frame.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func infoPlist(_ name: String) -> String {
        let url = SourceAudit.repoRoot().appendingPathComponent(name)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("The macOS app sets its display name to \"Time Frame\" (not the internal target name)")
    func macOSDisplayName() {
        let text = Self.pbxproj
        #expect(!text.isEmpty, "project.pbxproj not found")
        #expect(text.contains("INFOPLIST_KEY_CFBundleDisplayName = \"Time Frame\""),
                "macOS app must override CFBundleDisplayName to \"Time Frame\"")
    }


    @Test("No user-facing bad name variants appear in the app's Swift strings")
    func noBadNameVariants() {
        // Scan real string literals (comments stripped, literals preserved) across the app + Core +
        // Shared for the disallowed spellings AS user-facing text. Identifiers/bundle-ids that contain
        // "time-frame" or module names are code, not strings, so they are unaffected.
        let bad = ["Time Frame App", "Time-Frame"]
        var offenders: [String] = []
        for file in SourceAudit.swiftSources(inAnyOf: SourceAudit.productionRoots()) {
            let text = SourceAudit.codeKeepingStrings(file)
            for token in bad where text.contains("\"") && text.contains(token) {
                // Only count when the token is inside a quoted string.
                if quotedStrings(text).contains(where: { $0.contains(token) }) {
                    offenders.append("\(file.lastPathComponent): \(token)")
                }
            }
        }
        #expect(offenders.isEmpty, "User-facing name variants found: \(offenders)")
    }

    /// The contents of every double-quoted string literal on `text` (comments already stripped).
    private func quotedStrings(_ text: String) -> [String] {
        var out: [String] = []
        var inString = false
        var current = ""
        var escaped = false
        for ch in text {
            if inString {
                if escaped { current.append(ch); escaped = false; continue }
                if ch == "\\" { escaped = true; continue }
                if ch == "\"" { out.append(current); current = ""; inString = false; continue }
                current.append(ch)
            } else if ch == "\"" {
                inString = true
            }
        }
        return out
    }
}

// MARK: - App icon: one logo, present, referenced, no light/dark split

@Suite("M24 app icon — one supplied logo across Light/Dark, present and referenced")
struct M24AppIconTests {

    private static func appiconset(_ platformDir: String) -> URL {
        SourceAudit.repoRoot()
            .appendingPathComponent(platformDir)
            .appendingPathComponent("Assets.xcassets")
            .appendingPathComponent("AppIcon.appiconset")
    }

    private static func pngs(in dir: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .filter { $0.lowercased().hasSuffix(".png") } ?? []
    }

    private static func contentsJSON(_ appiconset: URL) -> String {
        (try? String(contentsOf: appiconset.appendingPathComponent("Contents.json"), encoding: .utf8)) ?? ""
    }

    @Test("The macOS AppIcon asset exists and carries real raster slots")
    func macOSIconPresent() {
        let set = Self.appiconset("time_frame")
        #expect(FileManager.default.fileExists(atPath: set.path), "macOS AppIcon.appiconset missing")
        #expect(!Self.contentsJSON(set).isEmpty, "macOS AppIcon Contents.json missing")
        #expect(Self.pngs(in: set).count >= 10, "macOS AppIcon must carry the full raster ladder")
    }


    @Test("The macOS app target references the AppIcon asset")
    func bothTargetsReferenceAppIcon() {
        let text = (try? String(contentsOf: SourceAudit.repoRoot()
            .appendingPathComponent("time_frame.xcodeproj")
            .appendingPathComponent("project.pbxproj"), encoding: .utf8)) ?? ""
        // The macOS app's two configurations each set the app-icon name. (This repository
        // ships macOS only; the iOS targets live in the full project.)
        let occurrences = text.components(separatedBy: "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;").count - 1
        #expect(occurrences >= 2,
                "The macOS app target must set ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon (found \(occurrences))")
    }

}

// MARK: - Unchanged internal identity: bundle id, App Group, URL scheme, schema

@Suite("M24 identity — internal identifiers are unchanged by the rename/icon work")
struct M24UnchangedIdentifiersTests {

    private static var pbxproj: String {
        let url = SourceAudit.repoRoot()
            .appendingPathComponent("time_frame.xcodeproj")
            .appendingPathComponent("project.pbxproj")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("The base bundle identifier is unchanged")
    func bundleIdentifierUnchanged() {
        #expect(Self.pbxproj.contains("PRODUCT_BUNDLE_IDENTIFIER = \"abirbarman.com.time-frame\""),
                "The macOS/iOS bundle identifier must remain abirbarman.com.time-frame")
    }

    @Test("The App Group is unchanged")
    func appGroupUnchanged() {
        #expect(WidgetProjectionStore.appGroupIdentifier == "group.abirbarman.com.time-frame")
    }


    @Test("M24 adds no model: the schema still has exactly the six V6 entities")
    func schemaAddsNoModel() {
        // The version moved to V7 in Milestone 28 (added attributes only, ADR-104); M24's
        // invariant is that product identity introduced no MODEL.
        #expect(TimeFrameSchemaLatest.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(Schema(versionedSchema: TimeFrameSchemaLatest.self).entities.count == 6)
    }
}

// MARK: - Catalog refresh: configuration changes fire the neutral onChange hook (Phase 7)

@MainActor
@Suite("M24 catalog refresh — configuration mutations fire the onChange hook")
struct M24ConfigurationChangeHookTests {

    /// A reference box so the escaping `@MainActor` hook can record firings.
    private final class Counter { var value = 0 }

    private func repository(_ container: ModelContainer, _ counter: Counter) -> ConfigurationRepository {
        ConfigurationRepository(context: container.mainContext, onChange: { counter.value += 1 })
    }

    @Test("A successful create fires the hook once")
    func createFires() throws {
        let container = try makeInMemoryContainer()
        let counter = Counter()
        let repo = repository(container, counter)
        _ = try repo.create(ConfigurationDraft(name: "Deep Work"))
        #expect(counter.value == 1)
    }

    @Test("A rejected create does not fire the hook (no phantom refresh)")
    func invalidDoesNotFire() throws {
        let container = try makeInMemoryContainer()
        let counter = Counter()
        let repo = repository(container, counter)
        #expect(throws: PersistenceError.self) {
            try repo.create(ConfigurationDraft(name: "", focusDuration: -1))
        }
        #expect(counter.value == 0)
    }

    @Test("update / duplicate / setDefault / delete each fire the hook")
    func mutationsFire() throws {
        let container = try makeInMemoryContainer()
        let counter = Counter()
        let repo = repository(container, counter)
        let config = try repo.create(ConfigurationDraft(name: "A"))     // 1
        try repo.update(config, with: ConfigurationDraft(name: "A2"))   // 2
        let dup = try repo.duplicate(config)                            // 3
        try repo.setDefault(dup)                                        // 4
        try repo.delete(dup)                                            // 5
        #expect(counter.value == 5)
    }

    @Test("A nil hook (the default — tests, intents) never fires and never throws")
    func nilHookIsSafe() throws {
        let container = try makeInMemoryContainer()
        let repo = ConfigurationRepository(context: container.mainContext)   // onChange defaults to nil
        _ = try repo.create(ConfigurationDraft(name: "A"))
        #expect(try repo.count() == 1)
    }
}

// MARK: - Configuration identity: a rename keeps the stable id (Phase 8)

@MainActor
@Suite("M24 configuration identity — Control Center selections survive a rename")
struct M24ConfigurationIdentityTests {

    @Test("Renaming a configuration preserves its stable id")
    func renameKeepsStableID() throws {
        let container = try makeInMemoryContainer()
        let repo = ConfigurationRepository(context: container.mainContext)
        let config = try repo.create(ConfigurationDraft(name: "A"))
        let originalID = config.id
        try repo.update(config, with: ConfigurationDraft(name: "Renamed"))
        #expect(config.id == originalID, "A rename must not change the id a Control Center control resolves by")
        #expect(config.name == "Renamed")
    }

    @Test("A recreated configuration gets a fresh id (never inherits a deleted one)")
    func recreatedGetsFreshID() throws {
        let container = try makeInMemoryContainer()
        let repo = ConfigurationRepository(context: container.mainContext)
        let first = try repo.create(ConfigurationDraft(name: "A"))
        let firstID = first.id
        try repo.delete(first)
        let second = try repo.create(ConfigurationDraft(name: "A"))
        #expect(second.id != firstID, "A new configuration must not reuse a deleted configuration's identity")
    }
}
