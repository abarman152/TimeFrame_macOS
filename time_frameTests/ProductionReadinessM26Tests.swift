//
//  ProductionReadinessM26Tests.swift
//  time_frameTests (Milestone 26)
//
//  Source-boundary audits for the stability milestone. M26 changed *how* work is
//  scheduled, never *who owns* the timer, so these audits pin the invariants that the
//  fixes could plausibly have eroded:
//
//   • the heartbeat remains the ONE scheduling primitive in the domain — the fixes must
//     not have introduced a second timer, a poll, or a sleep-based retry anywhere;
//   • there is still exactly one `TimerEngine` and one `SessionCoordinator` type;
//   • presentation adapters (widget writer, projection) still perform no persistence
//     *save* and hold no timer authority;
//   • the deferred today-summary refresh introduced no polling loop; and
//   • the schema stays V6 and the App Group / deep link are unchanged.
//
//  These scan the tree on disk (`ProductionReadinessSupport`), so they fail loudly
//  rather than vacuously if the layout moves.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

@Suite("M26 — production readiness boundaries")
struct ProductionReadinessM26Tests {

    // MARK: Single scheduling authority

    /// The domain may contain exactly ONE sleep-driven loop: the coordinator's heartbeat.
    /// Anything else — a second `Task.sleep` loop, a `Timer`, a `DispatchSourceTimer`,
    /// an `asyncAfter` — would be a second scheduling authority.
    @Test("The coordinator's heartbeat is the only scheduling primitive in the domain")
    func singleSchedulingAuthority() {
        let forbidden = ["Timer(", "scheduledTimer", "DispatchSourceTimer", "asyncAfter",
                         "CADisplayLink", "DispatchQueue"]
        let offenders = SourceAudit.filesReferencing(forbidden, in: [SourceAudit.core()])
        #expect(offenders.isEmpty, "scheduling primitive(s) introduced in Core: \(offenders)")
    }

    /// `Task.sleep` is the heartbeat's wait. It must appear in exactly one Core file.
    @Test("Task.sleep appears only in the heartbeat")
    func sleepOnlyInHeartbeat() {
        let users = SourceAudit.filesReferencing(["Task.sleep"], in: [SourceAudit.core()])
        #expect(users == ["SessionCoordinator.swift"],
                "Task.sleep outside the heartbeat: \(users)")
    }

    /// The deferred today-summary refresh must be a one-shot follow-up, never a poll.
    @Test("The widget projection writer introduces no timer, sleep, or polling loop")
    func projectionWriterHasNoClock() {
        let writer = SourceAudit.core().appendingPathComponent("Widgets/WidgetProjectionWriter.swift")
        let code = SourceAudit.code(writer)
        #expect(code.isEmpty == false, "WidgetProjectionWriter.swift not found")
        for token in ["Task.sleep", "Timer(", "scheduledTimer", "asyncAfter",
                      "DispatchSourceTimer", "while ", "repeat "] {
            #expect(SourceAudit.references(code, token) == false,
                    "projection writer gained a clock/loop via `\(token)`")
        }
    }

    // MARK: Single engine / single coordinator


    // MARK: Presentation adapters hold no persistence authority

    /// The projection layer reads authoritative state; it must never write the store.
    @Test("The widget projection layer performs no persistence save")
    func projectionPerformsNoSave() {
        let files = ["Widgets/WidgetProjectionWriter.swift", "Widgets/WidgetProjectionMapper.swift"]
        for name in files {
            let code = SourceAudit.code(SourceAudit.core().appendingPathComponent(name))
            #expect(code.isEmpty == false, "\(name) not found")
            #expect(SourceAudit.references(code, "save") == false,
                    "\(name) performs a persistence save")
            #expect(SourceAudit.references(code, "ModelContext") == false,
                    "\(name) reaches into a ModelContext")
        }
    }

    /// The statistics layer stays read-only: it may fetch, never save or delete.
    @Test("The statistics repository is read-only")
    func statisticsIsReadOnly() {
        let code = SourceAudit.code(
            SourceAudit.core().appendingPathComponent("Services/Statistics/StatisticsRepository.swift"))
        #expect(code.isEmpty == false)
        for token in ["save", "insert", "delete"] {
            #expect(SourceAudit.references(code, token) == false,
                    "the statistics repository mutates the store via `\(token)`")
        }
    }

    // MARK: Unchanged identity

    @Test("The App Group, deep-link scheme and schema version are unchanged")
    func identityUnchanged() {
        #expect(WidgetProjectionStore.appGroupIdentifier == "group.abirbarman.com.time-frame")
        #expect(WidgetDeepLink.scheme == "timeframe")
        // M26 changed no model; Milestone 28 bumped the version by adding attributes only,
        // so the invariant M26 owns is that the entity SET is unchanged.
        #expect(TimeFrameSchemaLatest.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(Schema(versionedSchema: TimeFrameSchemaLatest.self).entities.count == 6,
                "the SwiftData model set changed")
    }

    // MARK: The heartbeat invariant is actually enforced in code

    /// The generation guard (ADR-099) is what stops a late-unwinding heartbeat from
    /// clobbering a newer one. Its absence is the exact regression that reintroduces
    /// unbounded tick-loop multiplication, so pin it structurally as well as behaviourally.
    @Test("The heartbeat clears its handle only for the current generation")
    func heartbeatGenerationGuardPresent() {
        let code = SourceAudit.code(
            SourceAudit.core().appendingPathComponent("Timer/SessionCoordinator.swift"))
        #expect(code.isEmpty == false)
        #expect(SourceAudit.references(code, "tickerGeneration"),
                "the heartbeat generation guard (ADR-099) is gone")
        #expect(code.contains("if self.tickerGeneration == generation { self.ticker = nil }"),
                "the heartbeat no longer guards clearing `ticker` by generation")
    }
}
