//
//  InteractiveWidgetBoundaryTests.swift
//  time_frameTests (Milestone 15)
//
//  Structural guards for the interactive-widget boundary (ADR-069/070), enforced by scanning
//  the source on disk so a future edit that crosses the line fails CI — no WidgetKit host
//  required. The shared control intents and the widget view must own no timer, no session
//  state, no persistence, and no CloudKit; and every widget action must route through the ONE
//  `AppIntentSessionActions` seam, never a second timer or a direct engine/store mutation.
//

import Foundation
import Testing

@Suite("Interactive widget boundary invariants")
struct InteractiveWidgetBoundaryTests {

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

    /// Code with comments stripped, so a scan matches real references, not the header prose.
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

    /// Forbidden anywhere the widget can reach: second clocks, manual decrements, persistence,
    /// CloudKit, and new domain-object construction.
    private static let forbiddenTimerTokens = [
        "Timer(", "Timer.publish", "DispatchSourceTimer", "Task.sleep",
        "asyncAfter", "scheduledTimer", "remaining -=", "-= 1"
    ]
    private static let forbiddenPersistenceTokens = [
        "import SwiftData", "ModelContext", "import CloudKit", "CKRecord", "CKContainer"
    ]

    // MARK: Shared control intents

    @Test("The shared control intents own no timer, no persistence, no CloudKit, no domain")
    func sharedControlFileIsClean() {
        let url = Self.repoRoot()
            .appendingPathComponent("Shared")
            .appendingPathComponent("WidgetControlIntents.swift")
        let text = read(url)
        #expect(text.isEmpty == false, "Expected \(url.path) to exist")

        for token in Self.forbiddenTimerTokens {
            #expect(text.contains(token) == false, "WidgetControlIntents.swift contains forbidden '\(token)'")
        }
        for token in Self.forbiddenPersistenceTokens {
            #expect(text.contains(token) == false, "WidgetControlIntents.swift contains forbidden '\(token)'")
        }
        // No domain objects, and it never constructs its own timer/coordinator.
        #expect(text.contains("TimerEngine") == false)
        #expect(text.contains("SessionCoordinator") == false)
    }

    // MARK: Widget extension — new interactive additions stay within the M11/M14 boundary

    @Test("The widget extension still owns no timer, persistence, CloudKit, or domain")
    func widgetExtensionStaysClean() {
        let dir = Self.repoRoot().appendingPathComponent("TimeFrameWidgets")
        let files = swiftSources(in: dir)
        #expect(files.isEmpty == false)
        for file in files {
            let text = read(file)
            for token in Self.forbiddenTimerTokens {
                #expect(text.contains(token) == false, "\(file.lastPathComponent) contains forbidden '\(token)'")
            }
            for token in Self.forbiddenPersistenceTokens {
                #expect(text.contains(token) == false, "\(file.lastPathComponent) contains forbidden '\(token)'")
            }
            #expect(text.contains("TimerEngine") == false, "\(file.lastPathComponent) references TimerEngine")
            #expect(text.contains("SessionCoordinator") == false, "\(file.lastPathComponent) references SessionCoordinator")
        }
    }

    // MARK: Exactly one action seam

    @Test("The app-side router delegates through the one AppIntentSessionActions seam")
    func routerUsesTheOneSeam() {
        // Milestone 18 moved the neutral App-Intents layer into the shared `Core/` group.
        let url = Self.repoRoot()
            .appendingPathComponent("Core")
            .appendingPathComponent("Intents")
            .appendingPathComponent("WidgetControlRouting.swift")
        let text = read(url)
        #expect(text.isEmpty == false, "Expected \(url.path) to exist")

        // It routes through the existing seam …
        #expect(text.contains("AppIntentSessionActions"), "Routing must delegate to AppIntentSessionActions")
        // … and never constructs a second timer/coordinator or writes persistence directly.
        #expect(text.contains("TimerEngine(") == false)
        #expect(text.contains("SessionCoordinator(") == false)
        #expect(text.contains("ModelContext") == false)
        for token in Self.forbiddenTimerTokens {
            #expect(text.contains(token) == false, "WidgetControlRouting.swift contains forbidden '\(token)'")
        }
    }
}
