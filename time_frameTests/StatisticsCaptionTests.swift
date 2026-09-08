//
//  StatisticsCaptionTests.swift
//  time_frameTests (Milestone 27)
//
//  Regression cover for a user-visible defect found by looking at the running macOS app
//  during the documentation pass: the Statistics screen displayed the literal string
//  "^[3 focus interval](inflect: true)" under Focus Time.
//
//  Cause: those captions are built as Swift `String`s and passed to `Text(_: String)` and
//  `accessibilityValue(_:)`. Those are the NON-localized initializers, so SwiftUI never
//  applied the automatic grammar agreement markup and showed it verbatim. Inflection
//  markup only works when the literal reaches the view as a `LocalizedStringKey`.
//
//  These tests pin both halves: the helper pluralises correctly, and no inflection markup
//  is left anywhere it would be rendered through a `String`.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Statistics captions")
struct StatisticsCaptionTests {

    @Test("Counts are pluralised explicitly, never with inflection markup")
    func pluralisation() {
        #expect(statisticsCount(0, "focus interval") == "0 focus intervals")
        #expect(statisticsCount(1, "focus interval") == "1 focus interval")
        #expect(statisticsCount(2, "focus interval") == "2 focus intervals")
        #expect(statisticsCount(3, "completed session") == "3 completed sessions")
        #expect(statisticsCount(1, "completed session") == "1 completed session")
    }

    @Test("A caption never contains raw inflection markup")
    func noMarkupLeaks() {
        for n in 0...5 {
            let caption = statisticsCount(n, "focus interval")
            #expect(caption.contains("^[") == false, "markup leaked into: \(caption)")
            #expect(caption.contains("inflect") == false, "markup leaked into: \(caption)")
            #expect(caption.contains("](") == false, "markup leaked into: \(caption)")
        }
    }

    /// The statistics views must not reintroduce `^[…](inflect: true)` markup, because the
    /// values there travel through `String` and would be shown to the user verbatim.
    /// Literal markup inside `Text("…")` elsewhere in the app is fine and is not audited here.
    @Test("Statistics view sources contain no inflection markup")
    func statisticsSourcesAreMarkupFree() {
        let statistics = SourceAudit.appTarget().appendingPathComponent("Views/Statistics")
        let files = SourceAudit.swiftSources(in: statistics)
        #expect(files.isEmpty == false, "no Statistics view sources found")
        for file in files {
            // `codeKeepingStrings` strips comments but PRESERVES string literals — the
            // markup being audited lives inside a literal, so `code()` would blank it and
            // make this assertion vacuous.
            let code = SourceAudit.codeKeepingStrings(file)
            #expect(code.contains("inflect: true") == false,
                    "\(file.lastPathComponent) reintroduced inflection markup, which renders verbatim here")
        }
    }
}
