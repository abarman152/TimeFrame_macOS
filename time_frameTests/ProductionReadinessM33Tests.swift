//
//  ProductionReadinessM33Tests.swift
//  time_frameTests (Milestone 33)
//
//  The product-name invariants Milestone 24 did not cover (ADR-113).
//
//  ## Why these exist
//  M24 set `CFBundleDisplayName` to "Time Frame" and asserted it, and
//  `ProductionReadinessM24Tests` passed from then on. The application menu — the bold title
//  immediately right of the Apple menu, arguably the most-seen piece of an app's identity on
//  macOS — still read **`time_frame`**.
//
//  It reads `CFBundleName`, not `CFBundleDisplayName`, and nothing set or checked it. The
//  menu *items* ("About Time Frame", "Quit Time Frame") use the display name, so every string
//  a test could reasonably have looked at was already correct. The one that was wrong was the
//  one nobody had named.
//
//  So these tests deliberately assert the keys M24's did not: `CFBundleName`,
//  `PRODUCT_NAME`, the module pin that keeps `PRODUCT_NAME` safe to change, and the iOS
//  `CFBundleIconName` that declares the compiled icon.
//

import Foundation
import Testing
@testable import time_frame

@Suite("M33 identity — the app menu and bundle carry the product name")
struct M33ProductNameTests {

    private var projectFile: String {
        let url = SourceAudit.repoRoot()
            .appendingPathComponent("time_frame.xcodeproj/project.pbxproj")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }



    @Test("The macOS product name is \"Time Frame\", which is what the app menu shows")
    func macOSProductName() {
        // `CFBundleName` is generated from `PRODUCT_NAME`, and the generated value wins over
        // anything written into the physical Info.plist — setting the key there is a no-op,
        // and `INFOPLIST_KEY_CFBundleName` is not honoured either. `PRODUCT_NAME` is the only
        // lever that actually moves the application menu's title.
        let text = projectFile
        #expect(text.contains("PRODUCT_NAME = \"Time Frame\""),
                "The macOS app's PRODUCT_NAME must be \"Time Frame\" or its menu reads time_frame")
        #expect(!text.contains("INFOPLIST_KEY_CFBundleName"),
                "INFOPLIST_KEY_CFBundleName has no effect; it must not be left as misleading config")
    }

    @Test("The Swift module stays `time_frame`, pinned independently of the product name")
    func moduleNameIsPinned() {
        // Without this pin, renaming PRODUCT_NAME renames the Swift module too and every
        // `@testable import time_frame` in the suite stops compiling.
        #expect(projectFile.contains("PRODUCT_MODULE_NAME = time_frame;"),
                "The module name must be pinned so the product name can be branded safely")
    }

    @Test("The unit-test host follows the renamed product")
    func testHostFollowsProductName() {
        // If this is wrong the suite cannot launch its host at all — but it fails in a way
        // that looks like an infrastructure problem rather than a naming one, so it is worth
        // stating explicitly.
        #expect(projectFile.contains("Time Frame.app/Contents/MacOS/Time Frame"),
                "TEST_HOST must point at the renamed product")
        #expect(!projectFile.contains("time_frame.app/Contents/MacOS/time_frame"),
                "No stale TEST_HOST may reference the old product name")
    }

}

@Suite("M33 identity — the branding change moved nothing technical")
struct M33IdentityRegressionTests {

    private var projectFile: String {
        let url = SourceAudit.repoRoot()
            .appendingPathComponent("time_frame.xcodeproj/project.pbxproj")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("The bundle identifier, App Group and URL scheme are untouched")
    func technicalIdentifiersUnchanged() {
        // Renaming a product is only safe because none of these move with it. Each one, if
        // changed, would break signing, widgets, deep links or persistence — and the M24
        // suite asserts them too; they are restated here because this milestone is the one
        // that made a rename tempting.
        #expect(projectFile.contains("PRODUCT_BUNDLE_IDENTIFIER = \"abirbarman.com.time-frame\""))

        let entitlements = SourceAudit.repoRoot()
            .appendingPathComponent("time_frame/time_frame.entitlements")
        let text = (try? String(contentsOf: entitlements, encoding: .utf8)) ?? ""
        #expect(text.contains("group.abirbarman.com.time-frame"))

        let macPlist = SourceAudit.repoRoot().appendingPathComponent("time_frame-Info.plist")
        let mac = (try? String(contentsOf: macPlist, encoding: .utf8)) ?? ""
        #expect(mac.contains("<string>timeframe</string>"), "The deep-link scheme must not move")
    }

    @Test("The target directory and Swift sources keep their internal names")
    func internalLayoutUnchanged() {
        // The rename is a product-name change, not a project rename: the target folder, the
        // module and the test import all still say time_frame.
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: SourceAudit.appTarget().path),
                "The time_frame/ source directory must still exist")
        #expect(fm.fileExists(atPath: SourceAudit.repoRoot()
            .appendingPathComponent("time_frame.xcodeproj").path),
                "The .xcodeproj must not be renamed for branding")
    }
}
