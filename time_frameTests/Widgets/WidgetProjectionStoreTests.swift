//
//  WidgetProjectionStoreTests.swift
//  time_frameTests (Milestone 11)
//
//  The App Group store is the only channel between app and widget. These tests pin its
//  guarantees over a volatile suite: a write is readable back atomically, a missing suite
//  degrades to an inert no-op, a corrupt or schema-incompatible payload reads as `nil`
//  (never a throw), and the store never touches app model state (ADR-055).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Widget projection store")
struct WidgetProjectionStoreTests {

    private let base = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func scratchStore() -> (WidgetProjectionStore, UserDefaults) {
        let suite = "test.widget.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (WidgetProjectionStore(defaults: defaults), defaults)
    }

    @Test("A written projection reads back equal")
    func writeThenRead() {
        let (store, _) = scratchStore()
        let projection = WidgetProjection(
            generatedAt: base, state: .running, phase: .shortBreak,
            title: "Break time", currentIntervalIndex: 1, totalIntervals: 3
        )
        #expect(store.isAvailable)
        #expect(store.write(projection))
        #expect(store.read() == projection)
    }

    @Test("A missing App Group suite makes the store an inert no-op")
    func missingSuiteFallback() {
        let store = WidgetProjectionStore(defaults: nil)
        #expect(store.isAvailable == false)
        #expect(store.write(.idle(at: base)) == false)
        #expect(store.read() == nil)
    }

    @Test("A corrupt payload reads as nil, never a throw")
    func corruptPayloadReadsNil() {
        let (store, defaults) = scratchStore()
        defaults.set(Data("garbage".utf8), forKey: WidgetProjection.storageKey)
        #expect(store.read() == nil)
    }

    @Test("A schema-incompatible payload reads as nil")
    func incompatibleSchemaReadsNil() {
        let (store, defaults) = scratchStore()
        var future = WidgetProjection.idle(at: base)
        future.schemaVersion = 999
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        defaults.set(try! encoder.encode(future), forKey: WidgetProjection.storageKey)
        #expect(store.read() == nil)
    }

    @Test("clear removes the stored projection")
    func clearRemoves() {
        let (store, _) = scratchStore()
        store.write(.idle(at: base))
        #expect(store.read() != nil)
        store.clear()
        #expect(store.read() == nil)
    }

    @Test("Reading before any write returns nil")
    func emptyStoreReadsNil() {
        let (store, _) = scratchStore()
        #expect(store.read() == nil)
    }
}
