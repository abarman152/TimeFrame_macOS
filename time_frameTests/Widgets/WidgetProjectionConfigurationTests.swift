//
//  WidgetProjectionConfigurationTests.swift
//  time_frameTests (Milestone 14)
//
//  Milestone 14 adds two ADDITIVE optional fields to the widget projection
//  (`completedFocusIntervalsToday`, `focusTrendToday`) for the Today/Statistics widget modes,
//  WITHOUT bumping the schema version — an older payload that omits them simply reads `nil`.
//  These tests pin: the new fields round-trip; a genuine M11-shaped payload (missing the new
//  keys) still decodes and stays schema-compatible; a malformed trend value degrades to a
//  safe default; and an incompatible schema version is still rejected (reads `nil`), never
//  blindly decoded (ADR-067).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Widget projection — Milestone 14 fields")
struct WidgetProjectionConfigurationTests {

    /// A volatile suite plus the store over it. Raw payloads are written straight to the
    /// suite under the projection's storage key to simulate arbitrary/old/corrupt bytes.
    private func scratch() -> (store: WidgetProjectionStore, defaults: UserDefaults) {
        let suite = "test.widgetproj.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (WidgetProjectionStore(defaults: defaults), defaults)
    }

    private func scratchStore() -> WidgetProjectionStore { scratch().store }

    private func writeRaw(_ data: Data, to defaults: UserDefaults) {
        defaults.set(data, forKey: WidgetProjection.storageKey)
    }

    // MARK: Round-trip

    @Test("The new today/statistics fields round-trip through the store")
    func newFieldsRoundTrip() {
        let store = scratchStore()
        let projection = WidgetProjection.idle(
            at: Date(timeIntervalSinceReferenceDate: 700_000_000),
            focusSecondsToday: 3600,
            completedSessionsToday: 3,
            completedFocusIntervalsToday: 5,
            focusTrendToday: .up
        )
        #expect(store.write(projection))
        let read = store.read()
        #expect(read?.completedFocusIntervalsToday == 5)
        #expect(read?.focusTrendToday == .up)
        #expect(read?.focusSecondsToday == 3600)
        #expect(read?.completedSessionsToday == 3)
    }

    @Test("Every focus-trend value round-trips")
    func trendRoundTrip() throws {
        for trend in WidgetFocusTrend.allCases {
            let projection = WidgetProjection.idle(at: Date(), focusTrendToday: trend)
            let data = try JSONEncoder().encode(projection)
            let decoded = try JSONDecoder().decode(WidgetProjection.self, from: data)
            #expect(decoded.focusTrendToday == trend)
        }
    }

    // MARK: Backward compatibility (M11-shaped payload)

    @Test("An M11-shaped payload without the new keys decodes with them nil, still compatible")
    func backwardCompatibleDecode() {
        let (store, defaults) = scratch()
        let iso = ISO8601DateFormatter().string(from: Date(timeIntervalSinceReferenceDate: 700_000_000))
        let old = """
        {"schemaVersion":1,"generatedAt":"\(iso)","state":"idle","phase":"none","completedFocusCount":0,\
        "focusSecondsToday":1800,"completedSessionsToday":2}
        """
        writeRaw(Data(old.utf8), to: defaults)

        let read = store.read()
        #expect(read != nil)
        #expect(read?.state == .idle)
        #expect(read?.focusSecondsToday == 1800)
        #expect(read?.completedSessionsToday == 2)
        // The Milestone 14 additions are simply absent → nil.
        #expect(read?.completedFocusIntervalsToday == nil)
        #expect(read?.focusTrendToday == nil)
    }

    // MARK: Malformed data

    @Test("A malformed focus-trend value degrades to steady, never a throw")
    func malformedTrendDegrades() {
        let (store, defaults) = scratch()
        let iso = ISO8601DateFormatter().string(from: Date())
        let payload = """
        {"schemaVersion":1,"generatedAt":"\(iso)","state":"idle","phase":"none","completedFocusCount":0,\
        "focusTrendToday":"sideways"}
        """
        writeRaw(Data(payload.utf8), to: defaults)
        let read = store.read()
        #expect(read?.focusTrendToday == .steady)
    }

    @Test("Corrupt bytes read as nil, never a crash")
    func corruptReadsNil() {
        let (store, defaults) = scratch()
        writeRaw(Data("{not json".utf8), to: defaults)
        #expect(store.read() == nil)
    }

    // MARK: Version compatibility

    @Test("An incompatible schema version is rejected, not blindly decoded")
    func incompatibleVersionRejected() {
        let (store, defaults) = scratch()
        let iso = ISO8601DateFormatter().string(from: Date())
        let future = """
        {"schemaVersion":999,"generatedAt":"\(iso)","state":"running","phase":"focus","completedFocusCount":0}
        """
        writeRaw(Data(future.utf8), to: defaults)
        #expect(store.read() == nil)
    }

    @Test("The schema version is unchanged at 1 (additive-only change)")
    func schemaVersionUnchanged() {
        #expect(WidgetProjection.currentSchemaVersion == 1)
        #expect(WidgetProjection.storageKey == "com.time-frame.widget.projection.v1")
    }
}
