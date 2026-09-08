//
//  WidgetProjectionSerializationTests.swift
//  time_frameTests (Milestone 11)
//
//  The projection crosses a process boundary as JSON, so its Codable behaviour is a
//  contract: a clean round-trip, a defined schema-compatibility flag, and — crucially —
//  graceful decoding of unknown enum values and corrupt payloads so a forward-incompatible
//  or damaged write never crashes the widget (ADR-055).
//

import Foundation
import Testing
@testable import time_frame

@Suite("Widget projection serialization")
struct WidgetProjectionSerializationTests {

    private let base = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func roundTrip(_ projection: WidgetProjection) throws -> WidgetProjection {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetProjection.self, from: encoder.encode(projection))
    }

    @Test("A full running projection round-trips unchanged")
    func runningRoundTrip() throws {
        let original = WidgetProjection(
            generatedAt: base, state: .running, phase: .focus,
            title: "Task", configurationName: "Config",
            currentIntervalIndex: 2, totalIntervals: 4, completedFocusCount: 1,
            intervalStartedAt: base, intervalPlannedEndAt: base.addingTimeInterval(1500),
            focusSecondsToday: 3000, completedSessionsToday: 2
        )
        #expect(try roundTrip(original) == original)
    }

    @Test("Every state and phase round-trips")
    func allCasesRoundTrip() throws {
        for state in WidgetSessionState.allCases {
            for phase in WidgetPhase.allCases {
                let p = WidgetProjection(generatedAt: base, state: state, phase: phase)
                #expect(try roundTrip(p) == p)
            }
        }
    }

    @Test("Schema compatibility tracks the current version")
    func schemaCompatibility() {
        let current = WidgetProjection.idle(at: base)
        #expect(current.schemaVersion == WidgetProjection.currentSchemaVersion)
        #expect(current.isSchemaCompatible)

        var future = current
        future.schemaVersion = WidgetProjection.currentSchemaVersion + 1
        #expect(future.isSchemaCompatible == false)
    }

    @Test("An unknown state string decodes to .unavailable, not a throw")
    func unknownStateFallsBack() throws {
        let json = """
        {"schemaVersion":1,"generatedAt":"2023-03-01T00:00:00Z","state":"teleporting","phase":"focus","completedFocusCount":0}
        """.data(using: .utf8)!
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let p = try decoder.decode(WidgetProjection.self, from: json)
        #expect(p.state == .unavailable)
        #expect(p.phase == .focus)
    }

    @Test("An unknown phase string decodes to .none, not a throw")
    func unknownPhaseFallsBack() throws {
        let json = """
        {"schemaVersion":1,"generatedAt":"2023-03-01T00:00:00Z","state":"running","phase":"meditation","completedFocusCount":0}
        """.data(using: .utf8)!
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let p = try decoder.decode(WidgetProjection.self, from: json)
        #expect(p.state == .running)
        #expect(p.phase == .none)
    }

    @Test("A structurally corrupt payload throws (and the store swallows it)")
    func corruptPayloadThrows() {
        let garbage = Data("not json at all".utf8)
        let decoder = JSONDecoder()
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(WidgetProjection.self, from: garbage)
        }
    }
}
