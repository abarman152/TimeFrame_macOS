//
//  TestHostEnvironment.swift
//  time_frame
//
//  Detecting whether the app process is currently hosting the XCTest bundle.
//
//  The app target doubles as the unit-test **host**, so `@testable import time_frame`
//  works. That means `time_frameApp.init()` runs inside the test process too. To keep
//  the suite hermetic — so it can never recover, seed, or mutate the developer's real
//  persisted session, touch the real App Group, or reach CloudKit — launch skips all
//  live-store side effects when it detects the XCTest host (Milestone 17).
//
//  This helper isolates that detection into one pure, testable place. Pulling it out of
//  the `App` initialiser lets the production-readiness suite assert both directions:
//  that a synthetic XCTest environment is detected, and that the *actual* running test
//  process is detected (proving the guard is live right now). Behaviour is identical to
//  the previous inline check.
//

import Foundation

/// Pure, `Sendable` detection of the XCTest host. No app state, no side effects.
nonisolated enum TestHostEnvironment {

    /// Environment-variable keys XCTest sets in the process it hosts. Any one being
    /// present means the app is running as a test host, not as a normal launch.
    ///
    /// - `XCTestConfigurationFilePath` — set for every `xcodebuild test` run.
    /// - `XCTestBundlePath` — set when a test bundle is injected.
    /// - `XCTestSessionIdentifier` — set for a live test session.
    static let indicatorKeys = [
        "XCTestConfigurationFilePath",
        "XCTestBundlePath",
        "XCTestSessionIdentifier",
    ]

    /// Whether the given environment describes an XCTest host. Injectable so tests can
    /// exercise both the positive and negative cases without spawning a process.
    static func isHostingUnitTests(environment: [String: String]) -> Bool {
        indicatorKeys.contains { environment[$0] != nil }
    }

    /// Whether *this* process is an XCTest host, read from the live environment.
    static func isHostingUnitTests() -> Bool {
        isHostingUnitTests(environment: ProcessInfo.processInfo.environment)
    }
}
