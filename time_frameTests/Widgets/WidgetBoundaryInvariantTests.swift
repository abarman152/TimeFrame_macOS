//
//  WidgetBoundaryInvariantTests.swift
//  time_frameTests (Milestone 11)
//
//  Structural guards for the widget boundary (ADR-055), enforced by scanning the actual
//  source on disk so a future edit that violates the rule fails CI — no WidgetKit host
//  required. The widget extension and the shared projection code must never reach into the
//  domain: no SwiftData, no `TimerEngine`, no `SessionCoordinator`, and NO second clock
//  (`Timer`, `Timer.publish`, `DispatchSourceTimer`, `Task.sleep`, timer scheduling).
//

import Foundation
import Testing

@Suite("Widget boundary invariants")
struct WidgetBoundaryInvariantTests {

    /// Repo root derived from this file: …/time_frameTests/Widgets/<thisFile>.
    private static func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // Widgets
            .deletingLastPathComponent()   // time_frameTests
            .deletingLastPathComponent()   // repo root
    }

    private func swiftSources(in directory: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// The file's CODE with comments stripped, so a rule scans real references — not the
    /// architecture prose in the header/doc comments (which legitimately name the very
    /// domain types these tests forbid in code).
    private func read(_ url: URL) -> String {
        codeOnly((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    /// A deliberately simple comment stripper: drops `/* … */` blocks and `//` line
    /// comments. It is not a full lexer (it does not track string literals), but for a
    /// forbidden-token scan that only over-strips, never under-strips, that is exactly the
    /// safe direction.
    private func codeOnly(_ text: String) -> String {
        var out = ""
        var inBlock = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var s = String(rawLine)
            if inBlock {
                if let end = s.range(of: "*/") { s = String(s[end.upperBound...]); inBlock = false }
                else { continue }
            }
            while let start = s.range(of: "/*") {
                if let end = s.range(of: "*/", range: start.upperBound..<s.endIndex) {
                    s.replaceSubrange(start.lowerBound..<end.upperBound, with: " ")
                } else {
                    s = String(s[..<start.lowerBound]); inBlock = true; break
                }
            }
            if let line = s.range(of: "//") { s = String(s[..<line.lowerBound]) }
            out += s + "\n"
        }
        return out
    }

    // MARK: Widget extension target

    @Test("The widget extension source imports no SwiftData and no app module")
    func widgetImportsAreClean() {
        let dir = Self.repoRoot().appendingPathComponent("TimeFrameWidgets")
        let files = swiftSources(in: dir)
        #expect(files.isEmpty == false, "Expected widget sources at \(dir.path)")
        for file in files {
            let text = read(file)
            #expect(text.contains("import SwiftData") == false, "\(file.lastPathComponent) imports SwiftData")
            #expect(text.contains("import time_frame") == false, "\(file.lastPathComponent) imports the app module")
        }
    }

    @Test("The widget extension source never references the domain engine or coordinator")
    func widgetDoesNotReferenceDomain() {
        let dir = Self.repoRoot().appendingPathComponent("TimeFrameWidgets")
        for file in swiftSources(in: dir) {
            let text = read(file)
            #expect(text.contains("TimerEngine") == false, "\(file.lastPathComponent) references TimerEngine")
            #expect(text.contains("SessionCoordinator") == false, "\(file.lastPathComponent) references SessionCoordinator")
        }
    }

    @Test("The widget extension source creates no second clock")
    func widgetHasNoTimerLoop() {
        // Substrings that would indicate an independent countdown. `Timer(` (with the open
        // paren) and `.scheduledTimer` never match the widget's names (`TimerWidget`,
        // `timerInterval:`), which is exactly the point.
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

    // MARK: Shared projection code (compiled into BOTH app and widget)

    @Test("The shared projection code imports only Foundation")
    func sharedImportsOnlyFoundation() {
        let dir = Self.repoRoot().appendingPathComponent("Shared")
        let files = swiftSources(in: dir)
        #expect(files.isEmpty == false, "Expected shared sources at \(dir.path)")
        for file in files {
            let text = read(file)
            for forbidden in ["import SwiftData", "import SwiftUI", "import WidgetKit", "import time_frame"] {
                #expect(text.contains(forbidden) == false, "\(file.lastPathComponent) has forbidden '\(forbidden)'")
            }
            #expect(text.contains("TimerEngine") == false, "\(file.lastPathComponent) references TimerEngine")
            #expect(text.contains("SessionCoordinator") == false, "\(file.lastPathComponent) references SessionCoordinator")
        }
    }
}
