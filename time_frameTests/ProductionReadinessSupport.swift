//
//  ProductionReadinessSupport.swift
//  time_frameTests (Milestone 17)
//
//  Shared machinery for the Milestone-17 production-readiness audit: locate the repo
//  source roots from this file's own path, read a Swift file with comments and string
//  literals blanked out (so a scan matches real code, never the architecture prose in a
//  header or a token quoted inside a boundary test), and match a token only on an
//  identifier boundary (so `openTimer(` never masquerades as a `Timer(` construction).
//
//  These audits scan the source tree on disk. That is intentionally machine-dependent:
//  they assert the invariant on the checkout they were compiled from (`#filePath`). If
//  the tree cannot be found the audit fails loudly rather than passing vacuously.
//

import Foundation

/// Reads and scans the project's Swift sources for boundary-invariant audits.
enum SourceAudit {

    // MARK: Roots (derived from this file's compiled path)

    /// The repository root: `.../time_frame` (the inner git root that contains the app
    /// target, `Shared/`, `TimeFrameWidgets/`, and `time_frameTests/`).
    static func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // time_frameTests
            .deletingLastPathComponent()   // repo root
    }

    static func appTarget() -> URL { repoRoot().appendingPathComponent("time_frame") }
    /// The platform-neutral shared domain extracted in Milestone 18 (`Core/`), compiled into
    /// both the macOS app and the iOS companion. `TimerEngine`, `SessionCoordinator`, the
    /// models, persistence, statistics, and the Live Activity *core* live here now (ADR-078).
    static func core() -> URL { repoRoot().appendingPathComponent("Core") }
    static func shared() -> URL { repoRoot().appendingPathComponent("Shared") }
    static func widgetExtension() -> URL { repoRoot().appendingPathComponent("TimeFrameWidgets") }


    /// Every ActivityKit-free production source root: the macOS app, the shared `Core/`
    /// domain, the shared projection value types, and the macOS widget extension. Excludes
    /// `time_frameTests/` (which legitimately quotes forbidden tokens inside assertions) and
    /// the iOS targets (which are the sanctioned ActivityKit zone — see `iosRoots()`).
    static func productionRoots() -> [URL] { [appTarget(), core(), shared(), widgetExtension()] }


    // MARK: Enumeration

    /// All `.swift` files under a directory, recursively.
    static func swiftSources(in directory: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// All `.swift` files under any of the directories.
    static func swiftSources(inAnyOf directories: [URL]) -> [URL] {
        directories.flatMap { swiftSources(in: $0) }
    }

    // MARK: Reading (comments + string literals blanked)

    /// A file's source with `//` line comments, `/* */` block comments, and the contents
    /// of `"..."` string literals blanked. This keeps a token scan honest: the doc
    /// headers name these tokens on purpose, and a log/message string might too — neither
    /// is real timer code.
    static func code(_ url: URL) -> String {
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var out = ""
        var inBlock = false
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
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
            out += blankStringLiterals(s) + "\n"
        }
        return out
    }

    /// A file's source with only comments stripped — string literals are preserved. Use
    /// this when the thing being asserted is legitimately a string constant (e.g. an
    /// accessibility identifier), where blanking literals would hide it.
    static func codeKeepingStrings(_ url: URL) -> String {
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var out = ""
        var inBlock = false
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
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

    /// Replaces the contents of double-quoted string literals with spaces, preserving the
    /// quotes and line length. A backslash escapes the next character. Best-effort and
    /// line-local — enough to stop a token inside a `"..."` from being mistaken for code.
    private static func blankStringLiterals(_ line: String) -> String {
        var result = ""
        var inString = false
        var escaped = false
        for ch in line {
            if inString {
                if escaped { result.append(" "); escaped = false; continue }
                if ch == "\\" { result.append(" "); escaped = true; continue }
                if ch == "\"" { result.append("\""); inString = false; continue }
                result.append(" ")
            } else {
                result.append(ch)
                if ch == "\"" { inString = true }
            }
        }
        return result
    }

    // MARK: Token matching (identifier-boundary aware)

    /// Whether `code` references `token` at an identifier boundary — i.e. the character
    /// before it is not a letter, digit, or underscore. So `Timer(` matches ` Timer(`,
    /// `.Timer(`, and `(Timer(` but not `openTimer(`.
    static func references(_ code: String, _ token: String) -> Bool {
        var searchStart = code.startIndex
        while let range = code.range(of: token, range: searchStart..<code.endIndex) {
            if range.lowerBound == code.startIndex {
                return true
            }
            let before = code[code.index(before: range.lowerBound)]
            if !(before.isLetter || before.isNumber || before == "_") {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    /// The `.lastPathComponent` of each production file that references any of `tokens`.
    static func filesReferencing(_ tokens: [String], in roots: [URL]) -> [String] {
        var hits: [String] = []
        for file in swiftSources(inAnyOf: roots) {
            let text = code(file)
            if tokens.contains(where: { references(text, $0) }) {
                hits.append(file.lastPathComponent)
            }
        }
        return hits.sorted()
    }
}
