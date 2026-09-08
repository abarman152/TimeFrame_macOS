//
//  WidgetDeepLinkTests.swift
//  time_frameTests (Milestone 11)
//
//  Widget taps route through `timeframe://…` URLs onto the app's EXISTING sections. These
//  tests pin the round-trip (each destination → URL → destination), the app-side mapping
//  to `AppSection`, and safe handling of unknown URLs (ignored, never a crash).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Widget deep links")
struct WidgetDeepLinkTests {

    @Test("Every destination round-trips through its URL")
    func roundTrip() {
        for link in WidgetDeepLink.allCases {
            #expect(WidgetDeepLink(url: link.url) == link)
        }
    }

    @Test("The URLs use the timeframe scheme and destination host")
    func urlShape() {
        #expect(WidgetDeepLink.timer.url.absoluteString == "timeframe://timer")
        #expect(WidgetDeepLink.today.url.absoluteString == "timeframe://today")
        #expect(WidgetDeepLink.statistics.url.absoluteString == "timeframe://statistics")
        #expect(WidgetDeepLink.history.url.absoluteString == "timeframe://history")
    }

    @Test("Each destination maps to its existing app section")
    func sectionMapping() {
        #expect(WidgetDeepLink.timer.section == .timer)
        #expect(WidgetDeepLink.today.section == .today)
        #expect(WidgetDeepLink.statistics.section == .statistics)
        #expect(WidgetDeepLink.history.section == .history)
    }

    @Test("Parsing a URL straight to a section works for known links")
    func sectionForURL() {
        #expect(WidgetDeepLink.section(for: URL(string: "timeframe://statistics")!) == .statistics)
        #expect(WidgetDeepLink.section(for: URL(string: "timeframe://history")!) == .history)
    }

    @Test("Unknown scheme or host is ignored safely")
    func unknownIgnored() {
        #expect(WidgetDeepLink(url: URL(string: "https://example.com/timer")!) == nil)
        #expect(WidgetDeepLink(url: URL(string: "timeframe://frobnicate")!) == nil)
        #expect(WidgetDeepLink.section(for: URL(string: "timeframe://nonsense")!) == nil)
        #expect(WidgetDeepLink.section(for: URL(string: "mailto:someone@example.com")!) == nil)
    }
}
