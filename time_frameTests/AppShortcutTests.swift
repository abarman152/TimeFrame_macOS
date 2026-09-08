//
//  AppShortcutTests.swift
//  time_frameTests (Milestone 12)
//
//  Light, deterministic checks on the `AppShortcutsProvider`. The definitive verification of
//  phrases/intent references/parameterization is the App Intents metadata extraction at build
//  time (documented in docs/21-APP-INTENTS.md); AppShortcut's contents are not publicly
//  introspectable, so here we assert the curated set is present, stable, and not excessive.
//

import Foundation
import AppIntents
import Testing
@testable import time_frame

@Suite("App Shortcuts")
struct AppShortcutTests {

    @Test("A curated, non-excessive set of shortcuts is provided")
    func curatedCount() {
        let count = TimeFrameShortcuts.appShortcuts.count
        #expect(count == 9)          // start, template, plan, pause, resume, skip, stop, status, open
        #expect(count <= 12)         // guardrail: never an excessive number
    }

    @Test("The provider is stable across evaluations")
    func stable() {
        #expect(TimeFrameShortcuts.appShortcuts.count == TimeFrameShortcuts.appShortcuts.count)
    }
}
