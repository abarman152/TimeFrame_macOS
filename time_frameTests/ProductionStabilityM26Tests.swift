//
//  ProductionStabilityM26Tests.swift
//  time_frameTests (Milestone 26)
//
//  The permanent regression suite for the M26 stability work. Every test here
//  corresponds to a defect that was actually reproduced against the shipping code —
//  each one failed before its fix and passes after it. See
//  `docs/34-M26-STABILITY-AND-RELIABILITY.md` for the incident write-ups.
//
//  Two production defects made the app freeze while a Pomodoro was running:
//
//   1. **Heartbeat multiplication** (ADR-099). A cancelled heartbeat cleared the
//      coordinator's `ticker` handle as it unwound — including when a *newer*
//      heartbeat had been started in between. The newer loop then became
//      unreferenced (so `stopTicking()` could not cancel it) while `ticker == nil`
//      let the next control start yet another. Live tick loops grew without bound,
//      each waking the main actor four times a second.
//
//   2. **Unbounded statistics on the control path** (ADR-100). The widget
//      projection writer ran a full-history fetch plus two aggregations
//      *synchronously inside* `pause()`/`resume()`/`stop()`/`skip()`. Pause latency
//      was therefore O(lifetime history) — measured at ~770 ms per control with
//      2,000 recorded sessions, and unbounded thereafter.
//
//  These tests are deterministic: the engine is driven by `MockTimeSource`, and the
//  only real waits are short drains of already-enqueued main-actor tasks.
//

import Foundation
import SwiftData
import Testing
@testable import time_frame

// MARK: - Shared fixtures

@MainActor
private enum M26Fixture {

    static let base = Date(timeIntervalSinceReferenceDate: 700_000_000)

    /// A coordinator running the real production heartbeat.
    static func liveCoordinator(
        _ container: ModelContainer,
        clock: MockTimeSource,
        tick: Duration = .milliseconds(50)
    ) -> SessionCoordinator {
        SessionCoordinator(
            context: container.mainContext,
            timeSource: clock,
            tickInterval: tick,
            autoTick: true
        )
    }

    /// Seeds `count` completed sessions (3 focus + 1 short break each) spread one hour
    /// apart from `base`, i.e. genuine accumulated history.
    @discardableResult
    static func seedHistory(
        _ container: ModelContainer, count: Int, config: PomodoroConfiguration
    ) throws -> Int {
        let ctx = container.mainContext
        for i in 0..<count {
            let start = base.addingTimeInterval(TimeInterval(i) * 3_600)
            let session = FocusSession(taskName: "Task \(i)", configuration: config,
                                       status: .completed, startedAt: start)
            session.configurationName = config.name
            ctx.insert(session)
            var order = 0
            var cursor = start
            for _ in 0..<3 {
                let iv = SessionInterval(phase: .focus, plannedDuration: 1_500, order: order)
                iv.startedAt = cursor
                iv.endedAt = cursor.addingTimeInterval(1_500)
                iv.status = .completed
                iv.configurationName = config.name
                iv.session = session
                ctx.insert(iv)
                cursor = iv.endedAt!
                order += 1
            }
            let brk = SessionInterval(phase: .shortBreak, plannedDuration: 300, order: order)
            brk.startedAt = cursor
            brk.endedAt = cursor.addingTimeInterval(300)
            brk.status = .completed
            brk.session = session
            ctx.insert(brk)
            session.endedAt = brk.endedAt
        }
        try ctx.save()
        return count
    }

    /// Lets already-enqueued main-actor follow-up tasks (deferred projection refresh,
    /// unwinding heartbeats) run to completion.
    static func drain(_ milliseconds: Int = 120) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

// MARK: - 1. Heartbeat lifetime (ADR-099)

@MainActor
@Suite("M26 — timer heartbeat lifetime")
struct TimerHeartbeatLifetimeTests {

    /// The reproduction of the multiplication bug, verbatim: pause → resume → let the
    /// cancelled heartbeat unwind → issue another control. Before ADR-099 this grew the
    /// live tick loops by exactly one per cycle (11 after ten cycles).
    @Test("A control issued after a cancelled heartbeat unwinds never duplicates it")
    func heartbeatNeverMultiplies() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = M26Fixture.liveCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 100_000)
        try coordinator.startSession(configuration: config)

        for _ in 0..<10 {
            try coordinator.pause()
            try coordinator.resume()
            await M26Fixture.drain()          // let the cancelled generation unwind
            try coordinator.restart()          // a control that restarts the heartbeat
            #expect(coordinator.activeTickerCount <= 1,
                    "heartbeat multiplied to \(coordinator.activeTickerCount) live loops")
        }
        await M26Fixture.drain()
        #expect(coordinator.activeTickerCount == 1)
        _ = container
    }

    @Test("Stopping halts every heartbeat")
    func stopHaltsHeartbeat() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = M26Fixture.liveCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 100_000)
        try coordinator.startSession(configuration: config)
        for _ in 0..<20 { try coordinator.pause(); try coordinator.resume() }
        try coordinator.stop()
        await M26Fixture.drain(200)
        #expect(coordinator.activeTickerCount == 0, "a heartbeat survived stop()")
        _ = container
    }

    @Test("Pausing halts the heartbeat; resuming runs exactly one")
    func pauseAndResumeKeepExactlyOne() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = M26Fixture.liveCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 100_000)
        try coordinator.startSession(configuration: config)
        await M26Fixture.drain()
        #expect(coordinator.activeTickerCount == 1)

        try coordinator.pause()
        await M26Fixture.drain(200)
        #expect(coordinator.activeTickerCount == 0, "the heartbeat kept running while paused")

        try coordinator.resume()
        await M26Fixture.drain()
        #expect(coordinator.activeTickerCount == 1)
        try coordinator.stop()
        _ = container
    }

    @Test("Completing a session leaves no heartbeat behind")
    func completionLeavesNoHeartbeat() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = M26Fixture.liveCoordinator(container, clock: clock)
        // One short focus interval only, so the session completes on the next tick.
        let config = try insertConfiguration(container, focus: 10, short: 5, long: 5, before: 4, total: 1)
        try coordinator.startSession(configuration: config)
        clock.advance(by: 100)
        await M26Fixture.drain(250)
        #expect(coordinator.engine.state == .completed)
        #expect(coordinator.activeTickerCount == 0, "a heartbeat outlived completion")
        _ = container
    }

    /// 100 start/stop cycles must not accumulate heartbeats.
    @Test("100 start/stop cycles accumulate no heartbeats")
    func startStopStressLeaksNothing() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = M26Fixture.liveCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 100_000)
        for _ in 0..<100 {
            try coordinator.startSession(configuration: config)
            try coordinator.stop()
            coordinator.prepareForNewSession()
        }
        await M26Fixture.drain(300)
        #expect(coordinator.activeTickerCount == 0,
                "\(coordinator.activeTickerCount) heartbeats leaked across 100 start/stop cycles")
        _ = container
    }

    /// 100 pause/resume cycles must settle to exactly one heartbeat.
    @Test("100 pause/resume cycles settle to exactly one heartbeat")
    func pauseResumeStressSettlesToOne() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = M26Fixture.liveCoordinator(container, clock: clock)
        let config = try insertConfiguration(container, focus: 100_000)
        try coordinator.startSession(configuration: config)
        for _ in 0..<100 {
            try coordinator.pause()
            try coordinator.resume()
        }
        await M26Fixture.drain(400)
        #expect(coordinator.activeTickerCount == 1,
                "settled on \(coordinator.activeTickerCount) heartbeats")
        #expect(coordinator.engine.state == .running)
        try coordinator.stop()
        _ = container
    }
}

// MARK: - 2. Control-path responsiveness (ADR-099 / ADR-100)

@MainActor
@Suite("M26 — control-path responsiveness")
struct ControlPathResponsivenessTests {

    /// Builds the REAL app wiring: the projection writer subscribed to the lifecycle
    /// fan-out with the same full-history-shaped today provider the apps install.
    private func makeRig(
        historyCount: Int
    ) throws -> (SessionCoordinator, WidgetProjectionWriter, ModelContainer, () -> Int) {
        let container = try makeInMemoryContainer()
        let ctx = container.mainContext
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 100_000)
        try M26Fixture.seedHistory(container, count: historyCount, config: config)

        let coordinator = SessionCoordinator(context: ctx, timeSource: clock, autoTick: false)
        let calls = Counter()
        let writer = WidgetProjectionWriter(
            coordinator: coordinator,
            store: WidgetProjectionStore(defaults: nil),
            now: { clock.now() },
            todayProvider: {
                calls.value += 1
                let today = StatisticsPeriod.today.range()
                let yesterday = StatisticsPeriod.today.previousRange()
                guard let inputs = try? StatisticsRepository(context: ctx)
                    .sessionInputs(in: today, or: yesterday) else { return nil }
                let snapshot = StatisticsAggregator.aggregate(sessions: inputs, range: today)
                return TodaySummary(focusSeconds: snapshot.focusDuration,
                                    completedSessions: snapshot.completedSessions)
            },
            reload: {}
        )
        coordinator.onLifecycleEvent = { [weak writer] in writer?.handle($0) }
        coordinator.onMeaningfulTransition = { [weak writer] in writer?.update() }
        try coordinator.startSession(configuration: config)
        calls.value = 0
        return (coordinator, writer, container, { calls.value })
    }

    private final class Counter { var value = 0 }

    /// The headline regression: a timer control must never perform a statistics read.
    @Test("Timer controls perform no statistics read on the control path")
    func controlsDoNoStatisticsWork() throws {
        let (coordinator, _, container, calls) = try makeRig(historyCount: 200)
        for _ in 0..<10 {
            try coordinator.pause()
            try coordinator.resume()
        }
        try coordinator.skip()
        try coordinator.stop()
        #expect(calls() == 0,
                "\(calls()) statistics reads ran synchronously on the timer control path")
        _ = container
    }

    /// Pause/resume latency must not scale with recorded history. Before ADR-100 this
    /// was a measured 137× slowdown between 10 and 2,000 recorded sessions.
    @Test("Pause/resume latency does not scale with recorded history")
    func pauseLatencyIsIndependentOfHistory() throws {
        func measure(_ history: Int) throws -> Double {
            let (coordinator, _, container, _) = try makeRig(historyCount: history)
            let t0 = Date()
            for _ in 0..<10 {
                try coordinator.pause()
                try coordinator.resume()
            }
            let elapsed = Date().timeIntervalSince(t0)
            try coordinator.stop()
            _ = container
            return elapsed
        }
        let small = try measure(10)
        let large = try measure(2_000)
        // Deliberately generous: the point is that the curve is flat, not the absolute
        // number (which is machine-dependent). Before the fix the ratio was ~137×.
        #expect(large < small * 5 + 0.5,
                "pause latency scaled with history: \(small)s (10 sessions) -> \(large)s (2,000)")
        // And an absolute sanity ceiling: 20 controls over a large history stay snappy.
        #expect(large < 1.0, "20 timer controls took \(large)s over 2,000 recorded sessions")
    }

    /// The today summary must still reach the projection — just after the control path.
    @Test("The today summary lands on the coalesced follow-up pass")
    func todaySummaryStillArrives() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 100_000)
        let coordinator = SessionCoordinator(context: container.mainContext,
                                             timeSource: clock, autoTick: false)
        let store = WidgetProjectionStore(defaults: UserDefaults(suiteName: "test.m26.\(UUID().uuidString)")!)
        let writer = WidgetProjectionWriter(
            coordinator: coordinator, store: store, now: { clock.now() },
            todayProvider: { TodaySummary(focusSeconds: 1_234, completedSessions: 2) },
            reload: {}
        )
        coordinator.onLifecycleEvent = { [weak writer] in writer?.handle($0) }
        try coordinator.startSession(configuration: config, taskName: "Deep work")

        // Synchronously: full session state, no today figures yet.
        #expect(store.read()?.state == .running)
        #expect(store.read()?.title == "Deep work")

        await M26Fixture.drain()
        #expect(store.read()?.focusSecondsToday == 1_234)
        #expect(store.read()?.completedSessionsToday == 2)
        _ = container
    }

    /// A burst of transitions must collapse into a single statistics pass.
    @Test("A burst of transitions coalesces into one today refresh")
    func burstsCoalesce() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 100_000)
        let coordinator = SessionCoordinator(context: container.mainContext,
                                             timeSource: clock, autoTick: false)
        let writer = WidgetProjectionWriter(
            coordinator: coordinator, store: WidgetProjectionStore(defaults: nil),
            now: { clock.now() },
            todayProvider: { TodaySummary(focusSeconds: 0, completedSessions: 0) },
            reload: {}
        )
        coordinator.onLifecycleEvent = { [weak writer] in writer?.handle($0) }
        try coordinator.startSession(configuration: config)
        for _ in 0..<25 { try coordinator.pause(); try coordinator.resume() }
        await M26Fixture.drain()
        #expect(writer.todayRefreshCount == 1,
                "51 transitions produced \(writer.todayRefreshCount) statistics passes")
        try coordinator.stop()
        _ = container
    }
}

// MARK: - 3. Bounded statistics equivalence (ADR-100)

@MainActor
@Suite("M26 — bounded statistics equivalence")
struct BoundedStatisticsEquivalenceTests {

    /// The correctness proof for ADR-100: aggregating the period-bounded subset must be
    /// **identical** to aggregating all of history for that same period. If this ever
    /// fails, the superset filter is wrong and statistics are silently losing data.
    @Test("Bounded and unbounded aggregation agree for every period")
    func boundedMatchesUnbounded() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 1_500)
        try M26Fixture.seedHistory(container, count: 400, config: config)
        let repo = StatisticsRepository(context: container.mainContext)
        let all = try repo.sessionInputs()
        #expect(all.count == 400)

        // Ranges spanning the seeded window, its edges, and well outside it.
        let day: TimeInterval = 86_400
        let ranges: [StatisticsDateRange] = [
            StatisticsDateRange(start: M26Fixture.base, end: M26Fixture.base.addingTimeInterval(day)),
            StatisticsDateRange(start: M26Fixture.base.addingTimeInterval(day),
                                end: M26Fixture.base.addingTimeInterval(3 * day)),
            StatisticsDateRange(start: M26Fixture.base.addingTimeInterval(-10 * day),
                                end: M26Fixture.base.addingTimeInterval(-day)),
            StatisticsDateRange(start: M26Fixture.base.addingTimeInterval(100 * day),
                                end: M26Fixture.base.addingTimeInterval(200 * day)),
            StatisticsDateRange(start: M26Fixture.base.addingTimeInterval(-day),
                                end: M26Fixture.base.addingTimeInterval(60 * day)),
            // A range that starts mid-session, to exercise the interval-attribution edge.
            StatisticsDateRange(start: M26Fixture.base.addingTimeInterval(1_800),
                                end: M26Fixture.base.addingTimeInterval(5 * 3_600))
        ]

        for range in ranges {
            let bounded = try repo.sessionInputs(in: range)
            let expected = StatisticsAggregator.aggregate(sessions: all, range: range)
            let actual = StatisticsAggregator.aggregate(sessions: bounded, range: range)
            #expect(actual == expected, "bounded aggregation diverged for \(range)")
            #expect(bounded.count <= all.count)
        }
        _ = container
    }

    @Test("The two-range fetch admits everything either range needs")
    func twoRangeFetchIsComplete() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 1_500)
        try M26Fixture.seedHistory(container, count: 200, config: config)
        let repo = StatisticsRepository(context: container.mainContext)
        let all = try repo.sessionInputs()

        let day: TimeInterval = 86_400
        let first = StatisticsDateRange(start: M26Fixture.base,
                                        end: M26Fixture.base.addingTimeInterval(day))
        let second = StatisticsDateRange(start: M26Fixture.base.addingTimeInterval(day),
                                         end: M26Fixture.base.addingTimeInterval(2 * day))
        let both = try repo.sessionInputs(in: first, or: second)

        #expect(StatisticsAggregator.aggregate(sessions: both, range: first)
                == StatisticsAggregator.aggregate(sessions: all, range: first))
        #expect(StatisticsAggregator.aggregate(sessions: both, range: second)
                == StatisticsAggregator.aggregate(sessions: all, range: second))
        _ = container
    }

    @Test("An open (running) session is never excluded from a bounded fetch")
    func runningSessionAlwaysAdmitted() throws {
        let container = try makeInMemoryContainer()
        let config = try insertConfiguration(container, focus: 1_500)
        let ctx = container.mainContext
        // A session started long ago and still open — its intervals may complete today.
        let session = FocusSession(taskName: "Long runner", configuration: config,
                                   status: .running, startedAt: M26Fixture.base)
        session.configurationName = config.name
        ctx.insert(session)
        try ctx.save()

        let farFuture = StatisticsDateRange(
            start: M26Fixture.base.addingTimeInterval(1_000 * 86_400),
            end: M26Fixture.base.addingTimeInterval(1_001 * 86_400))
        let bounded = try StatisticsRepository(context: ctx).sessionInputs(in: farFuture)
        #expect(bounded.count == 1, "an open session was excluded from a later range")
        _ = container
    }

    @Test("The relevance test is an exact superset at the range boundaries")
    func relevanceBoundaries() {
        let start = M26Fixture.base
        let end = start.addingTimeInterval(3_600)
        let range = StatisticsDateRange(start: start, end: end)

        // Entirely before the range.
        #expect(range.mayContainActivity(startedAt: start.addingTimeInterval(-7_200),
                                         endedAt: start.addingTimeInterval(-3_600)) == false)
        // Ends exactly at the range start — its last interval ends at `start`, which the
        // half-open range excludes, but admitting it is harmless and keeps the test exact.
        #expect(range.mayContainActivity(startedAt: start.addingTimeInterval(-7_200),
                                         endedAt: start) == true)
        // Starts exactly at the range end — excluded by the half-open range.
        #expect(range.mayContainActivity(startedAt: end, endedAt: nil) == false)
        // Straddles the range.
        #expect(range.mayContainActivity(startedAt: start.addingTimeInterval(-1),
                                         endedAt: end.addingTimeInterval(1)) == true)
        // Never started.
        #expect(range.mayContainActivity(startedAt: nil, endedAt: nil) == false)
    }
}

// MARK: - 4. Failure isolation on the control path

@MainActor
@Suite("M26 — projection failure isolation")
struct ProjectionFailureIsolationTests {

    /// A projection that throws/traps on every path must not stop the timer.
    private func rig() throws -> (SessionCoordinator, ModelContainer) {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = SessionCoordinator(context: container.mainContext,
                                             timeSource: clock, autoTick: false)
        let writer = WidgetProjectionWriter(
            coordinator: coordinator,
            store: WidgetProjectionStore(defaults: nil),      // App Group unavailable
            now: { clock.now() },
            todayProvider: { nil },                            // statistics unavailable
            reload: { }                                        // WidgetKit unavailable
        )
        coordinator.onLifecycleEvent = { [weak writer] in writer?.handle($0) }
        coordinator.onMeaningfulTransition = { [weak writer] in writer?.update() }
        return (coordinator, container)
    }

    @Test("Every control succeeds while the projection store is unavailable")
    func controlsSucceedWithoutProjection() async throws {
        let (coordinator, container) = try rig()
        let config = try insertConfiguration(container, focus: 100_000)

        try coordinator.startSession(configuration: config)
        #expect(coordinator.engine.state == .running)
        try coordinator.pause()
        #expect(coordinator.engine.state == .paused)
        try coordinator.resume()
        #expect(coordinator.engine.state == .running)
        try coordinator.skip()
        #expect(coordinator.engine.state == .running)
        try coordinator.restart()
        #expect(coordinator.engine.state == .running)
        try coordinator.stop()
        #expect(coordinator.engine.state == .cancelled)
        await M26Fixture.drain()
        _ = container
    }

    @Test("A today-provider failure never blocks or corrupts a control")
    func failingTodayProviderIsHarmless() async throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let config = try insertConfiguration(container, focus: 100_000)
        let coordinator = SessionCoordinator(context: container.mainContext,
                                             timeSource: clock, autoTick: false)
        let store = WidgetProjectionStore(defaults: UserDefaults(suiteName: "test.m26.\(UUID().uuidString)")!)
        let writer = WidgetProjectionWriter(
            coordinator: coordinator, store: store, now: { clock.now() },
            todayProvider: { nil },   // models a statistics fetch failure
            reload: {}
        )
        coordinator.onLifecycleEvent = { [weak writer] in writer?.handle($0) }
        try coordinator.startSession(configuration: config, taskName: "Resilient")
        try coordinator.pause()
        await M26Fixture.drain()

        // The session projection is still correct; only the today figures are absent.
        #expect(coordinator.engine.state == .paused)
        #expect(store.read()?.state == .paused)
        #expect(store.read()?.title == "Resilient")
        #expect(store.read()?.focusSecondsToday == nil)
        _ = container
    }
}

// MARK: - 5. Repeated / conflicting control stress

@MainActor
@Suite("M26 — control stress and invalid transitions")
struct ControlStressTests {

    private func running() throws -> (SessionCoordinator, ModelContainer) {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = SessionCoordinator(context: container.mainContext,
                                             timeSource: clock, autoTick: false)
        let config = try insertConfiguration(container, focus: 100_000)
        try coordinator.startSession(configuration: config)
        return (coordinator, container)
    }

    @Test("Repeated pause is idempotent and leaves exactly one pause transition")
    func repeatedPauseIsIdempotent() throws {
        let (coordinator, container) = try running()
        for _ in 0..<20 { try coordinator.pause() }
        #expect(coordinator.engine.state == .paused)
        let intervals = coordinator.activeSession?.orderedIntervals ?? []
        #expect(intervals.filter { $0.status == .paused }.count == 1)
        try coordinator.resume()
        #expect(coordinator.engine.state == .running)
        _ = container
    }

    @Test("Repeated stop cannot resurrect or duplicate a session")
    func repeatedStopIsIdempotent() throws {
        let (coordinator, container) = try running()
        let id = coordinator.activeSession?.id
        for _ in 0..<20 { try coordinator.stop() }
        #expect(coordinator.engine.state == .cancelled)
        #expect(coordinator.activeSession?.id == id)
        let all = try SessionRepository(context: container.mainContext).allSessions()
        #expect(all.count == 1, "stop duplicated the session (\(all.count) rows)")
        _ = container
    }

    @Test("Starting while a session is active is refused, never duplicated")
    func doubleStartIsRefused() throws {
        let (coordinator, container) = try running()
        let config = try insertConfiguration(container, name: "Second", isDefault: false)
        for _ in 0..<10 {
            #expect(try coordinator.startSession(configuration: config) == nil)
        }
        let all = try SessionRepository(context: container.mainContext).allSessions()
        #expect(all.count == 1)
        try coordinator.stop()
        _ = container
    }

    @Test("100 skip operations stay consistent and terminate cleanly")
    func skipStress() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = SessionCoordinator(context: container.mainContext,
                                             timeSource: clock, autoTick: false)
        let config = try insertConfiguration(container, focus: 10, short: 5, long: 5,
                                             before: 4, total: 8)
        try coordinator.startSession(configuration: config)
        for _ in 0..<100 {
            guard coordinator.engine.state.isActive else { break }
            try coordinator.skip()
        }
        // The plan is finite, so skipping past its end completes the session; it must
        // never wrap, duplicate, or leave the engine active.
        #expect(coordinator.engine.state == .completed)
        let all = try SessionRepository(context: container.mainContext).allSessions()
        #expect(all.count == 1)
        _ = container
    }

    @Test("100 start/stop cycles produce exactly 100 well-formed sessions")
    func startStopCycleStress() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = SessionCoordinator(context: container.mainContext,
                                             timeSource: clock, autoTick: false)
        let config = try insertConfiguration(container, focus: 100_000)
        for _ in 0..<100 {
            try coordinator.startSession(configuration: config)
            try coordinator.pause()
            try coordinator.resume()
            try coordinator.stop()
            coordinator.prepareForNewSession()
        }
        let all = try SessionRepository(context: container.mainContext).allSessions()
        #expect(all.count == 100)
        #expect(all.allSatisfy { $0.status == .cancelled })
        #expect(all.allSatisfy { $0.endedAt != nil })
        _ = container
    }
}

// MARK: - 6. Menu bar label repaint (ADR-101)

@MainActor
@Suite("M26 — menu bar label repaint")
struct MenuBarLabelRepaintTests {

    /// The bug: a `TimelineView` inside a `MenuBarExtra` **label** re-renders the
    /// `NSStatusBarButton` synchronously and re-arms its schedule during that render, so
    /// SwiftUI requested the next update immediately instead of a second later. The
    /// result was an unbounded `updateButton → setImage: → invalidate → update` loop that
    /// pinned the main thread at 100% CPU for as long as a session was running — i.e. the
    /// app froze the moment a session was started.
    ///
    /// The failure mode lives in SwiftUI's status-item hosting, so no unit test can
    /// observe it; what *can* be pinned is the rule that produced it. This is the same
    /// approach the rest of the production-readiness audits take.
    @Test("The menu bar label contains no TimelineView")
    func labelHasNoTimelineView() {
        let label = SourceAudit.appTarget()
            .appendingPathComponent("Views/MenuBar/TimeFrameMenuBarLabel.swift")
        let code = SourceAudit.code(label)   // comments + string literals blanked
        #expect(code.isEmpty == false, "TimeFrameMenuBarLabel.swift not found")
        #expect(SourceAudit.references(code, "TimelineView") == false,
                "a TimelineView is back in the MenuBarExtra label — this freezes the app (ADR-101)")
        for token in ["Timer(", "scheduledTimer", "asyncAfter", "Task"] {
            #expect(SourceAudit.references(code, token) == false,
                    "the menu bar label gained a scheduling primitive via `\(token)`")
        }
    }

    /// The label must still tick, which it now does by observing the coordinator's
    /// display heartbeat rather than scheduling its own redraws.
    @Test("The menu bar label observes the coordinator's display heartbeat")
    func labelObservesDisplaySecond() {
        let label = SourceAudit.appTarget()
            .appendingPathComponent("Views/MenuBar/TimeFrameMenuBarLabel.swift")
        let code = SourceAudit.code(label)
        #expect(SourceAudit.references(code, "displaySecond"),
                "the label no longer repaints — the countdown would freeze on screen")
    }

    /// `displaySecond` is a *display* signal: whole-second granularity, advanced only by
    /// the existing heartbeat, and never a source of timing authority.
    @Test("displaySecond advances at whole-second granularity only")
    func displaySecondGranularity() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        clock.set(to: Date(timeIntervalSinceReferenceDate: 1_000.25))
        let coordinator = SessionCoordinator(context: container.mainContext,
                                             timeSource: clock, autoTick: false)
        let config = try insertConfiguration(container, focus: 100_000)
        try coordinator.startSession(configuration: config)

        try coordinator.tick()
        #expect(coordinator.displaySecond == Date(timeIntervalSinceReferenceDate: 1_000))

        // Still inside the same whole second: the signal must not change, so the label
        // is not invalidated four times a second by the 250 ms heartbeat.
        clock.advance(by: 0.5)
        let unchanged = coordinator.displaySecond
        try coordinator.tick()
        #expect(coordinator.displaySecond == unchanged)

        // Crossing into the next second advances it exactly once.
        clock.advance(by: 0.5)
        try coordinator.tick()
        #expect(coordinator.displaySecond == Date(timeIntervalSinceReferenceDate: 1_001))

        try coordinator.stop()
        _ = container
    }

    /// The display signal must never become a timing authority: the engine's remaining
    /// time is derived from its own frozen anchors, not from `displaySecond`.
    @Test("displaySecond carries no timing authority")
    func displaySecondIsNotAuthoritative() throws {
        let container = try makeInMemoryContainer()
        let clock = MockTimeSource()
        let coordinator = SessionCoordinator(context: container.mainContext,
                                             timeSource: clock, autoTick: false)
        let config = try insertConfiguration(container, focus: 60)
        try coordinator.startSession(configuration: config)

        clock.advance(by: 25)
        try coordinator.tick()
        let remainingAfterTick = coordinator.engine.remaining

        // Ticking again without advancing the clock must not change the engine at all,
        // even though it refreshes the display signal.
        try coordinator.tick()
        #expect(coordinator.engine.remaining == remainingAfterTick)
        expectClose(remainingAfterTick, 35)

        try coordinator.stop()
        _ = container
    }
}
