//
//  WidgetConfigurationBoundaryTests.swift
//  time_frameTests (Milestone 14)
//
//  Milestone 14 boundary guards, enforced by scanning the actual source on disk (no WidgetKit
//  host required) so a future edit that crosses the line fails CI. They extend the M11
//  `WidgetBoundaryInvariantTests` for the configurable widget: the widget extension imports no
//  CloudKit and writes no `ModelContext`; and among the shared files only the configuration
//  intent may import AppIntents — the pure model, projection, and timeline builder stay
//  Foundation-only (ADR-064/068).
//

import Foundation
import Testing

@Suite("Configurable widget boundary invariants")
struct WidgetConfigurationBoundaryTests {

    // MARK: Source access (repo root derived from this file's path)

    private static func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // Widgets
            .deletingLastPathComponent()   // time_frameTests
            .deletingLastPathComponent()   // repo root
    }

    private func swiftSources(in directory: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Code with `//` and `/* */` comments stripped, so a scan matches real references, not
    /// the architecture prose in the header comments (which legitimately names these tokens).
    private func read(_ url: URL) -> String {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var out = ""
        var inBlock = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var s = String(rawLine)
            if inBlock {
                if let end = s.range(of: "*/") { s = String(s[end.upperBound...]); inBlock = false } else { continue }
            }
            while let start = s.range(of: "/*") {
                if let end = s.range(of: "*/", range: start.upperBound..<s.endIndex) {
                    s.replaceSubrange(start.lowerBound..<end.upperBound, with: " ")
                } else { s = String(s[..<start.lowerBound]); inBlock = true; break }
            }
            if let line = s.range(of: "//") { s = String(s[..<line.lowerBound]) }
            out += s + "\n"
        }
        return out
    }

    // MARK: Widget extension — no CloudKit, no direct persistence

    @Test("The widget extension imports no CloudKit and writes no ModelContext")
    func widgetHasNoCloudKitOrPersistence() {
        let dir = Self.repoRoot().appendingPathComponent("TimeFrameWidgets")
        let files = swiftSources(in: dir)
        #expect(files.isEmpty == false, "Expected widget sources at \(dir.path)")
        for file in files {
            let text = read(file)
            #expect(text.contains("import CloudKit") == false, "\(file.lastPathComponent) imports CloudKit")
            #expect(text.contains("CKRecord") == false, "\(file.lastPathComponent) references CKRecord")
            #expect(text.contains("import SwiftData") == false, "\(file.lastPathComponent) imports SwiftData")
            #expect(text.contains("ModelContext") == false, "\(file.lastPathComponent) references ModelContext")
        }
    }

    @Test("The widget extension creates no second clock (expanded token set)")
    func widgetHasNoTimerLoop() {
        let forbidden = ["Timer(", "Timer.publish", "DispatchSourceTimer",
                         "Task.sleep", "asyncAfter", "scheduledTimer"]
        let dir = Self.repoRoot().appendingPathComponent("TimeFrameWidgets")
        for file in swiftSources(in: dir) {
            let text = read(file)
            for token in forbidden {
                #expect(text.contains(token) == false, "\(file.lastPathComponent) contains forbidden '\(token)'")
            }
        }
    }

    // MARK: Shared — CloudKit-free; AppIntents only in the configuration intent

    @Test("No shared file imports CloudKit, SwiftData, SwiftUI, WidgetKit, or the app module")
    func sharedStaysPure() {
        let dir = Self.repoRoot().appendingPathComponent("Shared")
        for file in swiftSources(in: dir) {
            let text = read(file)
            for forbidden in ["import CloudKit", "import SwiftData", "import SwiftUI",
                              "import WidgetKit", "import time_frame"] {
                #expect(text.contains(forbidden) == false, "\(file.lastPathComponent) has forbidden '\(forbidden)'")
            }
            #expect(text.contains("TimerEngine") == false, "\(file.lastPathComponent) references TimerEngine")
            #expect(text.contains("SessionCoordinator") == false, "\(file.lastPathComponent) references SessionCoordinator")
        }
    }

    @Test("AppIntents is imported only by the configuration-intent and widget-control shared files")
    func appIntentsImportIsIsolated() {
        // Two shared files legitimately import AppIntents: the Milestone-14 configuration intent
        // and the Milestone-15 widget-control intents (both are App Intents by nature and must be
        // compiled into the widget so it can reference them). Every OTHER shared file — the pure
        // model, projection, and timeline builder — stays Foundation-only.
        let dir = Self.repoRoot().appendingPathComponent("Shared")
        let importers = swiftSources(in: dir)
            .filter { read($0).contains("import AppIntents") }
            .map { $0.lastPathComponent }
            .sorted()
        #expect(importers == ["TimeFrameWidgetConfigurationIntent.swift", "WidgetControlIntents.swift"])
    }
}
