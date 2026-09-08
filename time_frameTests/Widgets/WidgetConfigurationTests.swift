//
//  WidgetConfigurationTests.swift
//  time_frameTests (Milestone 14)
//
//  The pure widget configuration model is Foundation-only, deterministic, and defensive
//  (ADR-064/066). These tests pin its defaults, the value sets of each choice, Codable
//  round-tripping, Hashable behaviour, its destination→deep-link mapping, and — importantly
//  — that malformed/partial payloads degrade to the safe default instead of throwing.
//

import Foundation
import Testing
@testable import time_frame

@Suite("Widget configuration model")
struct WidgetConfigurationTests {

    // MARK: Defaults

    @Test("The default configuration is Current Timer → Timer → countdown on")
    func defaults() {
        let config = TimeFrameWidgetConfiguration.default
        #expect(config.displayMode == .timer)
        #expect(config.destination == .timer)
        #expect(config.showsCountdown == true)
    }

    @Test("A default-initialised configuration matches the canonical default")
    func memberwiseDefault() {
        #expect(TimeFrameWidgetConfiguration() == .default)
        #expect(WidgetDisplayMode.default == .timer)
        #expect(WidgetDestination.default == .timer)
    }

    // MARK: Value sets

    @Test("Display modes and destinations expose stable raw values")
    func rawValues() {
        #expect(WidgetDisplayMode.allCases.map(\.rawValue) == ["timer", "today", "statistics"])
        #expect(WidgetDestination.allCases.map(\.rawValue) == ["timer", "today", "statistics", "history"])
    }

    // MARK: Destination → deep link

    @Test("Each destination maps to its matching deep link (and existing section)")
    func destinationDeepLink() {
        #expect(WidgetDestination.timer.deepLink == .timer)
        #expect(WidgetDestination.today.deepLink == .today)
        #expect(WidgetDestination.statistics.deepLink == .statistics)
        #expect(WidgetDestination.history.deepLink == .history)
        // And through to the existing app section, proving no new navigation mechanism.
        #expect(WidgetDestination.history.deepLink.section == .history)
    }

    // MARK: Codable round-trip

    @Test("Every configuration round-trips through Codable unchanged")
    func codableRoundTrip() throws {
        for mode in WidgetDisplayMode.allCases {
            for dest in WidgetDestination.allCases {
                for countdown in [true, false] {
                    let original = TimeFrameWidgetConfiguration(
                        displayMode: mode, destination: dest, showsCountdown: countdown
                    )
                    let data = try JSONEncoder().encode(original)
                    let decoded = try JSONDecoder().decode(TimeFrameWidgetConfiguration.self, from: data)
                    #expect(decoded == original)
                }
            }
        }
    }

    // MARK: Hashable

    @Test("Equal configurations hash equally; different ones are distinguishable")
    func hashable() {
        let a = TimeFrameWidgetConfiguration(displayMode: .today, destination: .history, showsCountdown: false)
        let b = TimeFrameWidgetConfiguration(displayMode: .today, destination: .history, showsCountdown: false)
        let c = TimeFrameWidgetConfiguration(displayMode: .statistics, destination: .history, showsCountdown: false)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        let set: Set<TimeFrameWidgetConfiguration> = [a, b, c]
        #expect(set.count == 2)
    }

    // MARK: Defensive decoding

    @Test("An unknown display mode / destination decodes to the safe default")
    func malformedEnumsDegrade() throws {
        let json = #"{"displayMode":"hologram","destination":"teleport","showsCountdown":true}"#
        let decoded = try JSONDecoder().decode(TimeFrameWidgetConfiguration.self, from: Data(json.utf8))
        #expect(decoded.displayMode == .timer)
        #expect(decoded.destination == .timer)
        #expect(decoded.showsCountdown == true)
    }

    @Test("A partial payload fills every missing field with its default")
    func partialPayloadFallsBack() throws {
        let json = #"{"displayMode":"today"}"#
        let decoded = try JSONDecoder().decode(TimeFrameWidgetConfiguration.self, from: Data(json.utf8))
        #expect(decoded.displayMode == .today)
        #expect(decoded.destination == .default)      // missing → default
        #expect(decoded.showsCountdown == true)        // missing → default
    }

    @Test("An empty object decodes to the full default configuration")
    func emptyObjectIsDefault() throws {
        let decoded = try JSONDecoder().decode(TimeFrameWidgetConfiguration.self, from: Data("{}".utf8))
        #expect(decoded == .default)
    }
}
