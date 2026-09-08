//
//  AppIntentSessionActions.swift
//  time_frame (Milestone 12)
//
//  The one place the App Intents layer *acts*. Every intent's real work lives here as a
//  small `@MainActor` method that routes through the SINGLE authoritative `SessionCoordinator`
//  (ADR-056) — resolving a template/plan/configuration through the existing repositories,
//  then calling the existing `startSession`/`startPlan`/`pause`/`resume`/`skip`/`restart`/
//  `stop`. It creates no timer, no session, and no persistence of its own; it only translates
//  a request into a coordinator call and an internal failure into a friendly
//  `TimeFrameIntentError`.
//
//  Keeping the logic here (not inside `perform()`) is what makes the milestone testable
//  without Siri or Shortcuts: the test suite builds an in-memory coordinator (mock clock,
//  `autoTick: false`) and drives these methods directly, exactly like every other layer's
//  tests.
//

import Foundation

/// Describes what a successful start did, so the intent can phrase a confirmation dialog
/// without re-reading the engine. Pure value.
nonisolated struct AppIntentStartOutcome: Sendable, Equatable {
    let taskName: String
    /// The configuration name for a single-configuration start, or the plan name for a plan.
    let configurationName: String
    /// The number of focus sessions started (a plan reports its focus count).
    let sessionCount: Int
    /// Whether this start came from a multi-configuration plan (affects phrasing).
    let isPlan: Bool
    /// The plan's name, when `isPlan` is true.
    let planName: String?
}

/// Routes App Intent requests through the one coordinator. Never owns timer state.
@MainActor
struct AppIntentSessionActions {
    let coordinator: SessionCoordinator

    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: Start

    /// Starts a session from an (optional) configuration id, falling back to the user's
    /// default configuration when none is supplied — never inventing an invalid one.
    @discardableResult
    func startSession(
        configurationID: UUID?,
        taskName: String?,
        totalSessions: Int?
    ) throws -> AppIntentStartOutcome {
        try requireNoActiveSession()

        let configuration = try resolveConfiguration(id: configurationID)
        let session: FocusSession?
        do {
            session = try coordinator.startSession(
                configuration: configuration,
                taskName: taskName ?? "",
                totalSessions: totalSessions
            )
        } catch {
            throw TimeFrameIntentError.couldNotStartSession
        }
        guard session != nil else { throw TimeFrameIntentError.couldNotStartSession }

        return AppIntentStartOutcome(
            taskName: taskName ?? "",
            configurationName: configuration.name,
            sessionCount: coordinator.engine.totalFocusSessions,
            isPlan: false,
            planName: nil
        )
    }

    /// Starts a session from a `TaskTemplate`, reusing the exact chain the UI uses:
    /// `TaskTemplate → SessionSetupPrefill → SessionCoordinator.startSession` (ADR-056).
    @discardableResult
    func startTemplate(id: UUID) throws -> AppIntentStartOutcome {
        try requireNoActiveSession()

        guard let template = try fetchTemplate(id) else {
            throw TimeFrameIntentError.templateUnavailable
        }
        guard let configuration = template.configuration else {
            throw TimeFrameIntentError.templateNeedsConfiguration
        }

        // Build the same value seam the setup screen consumes, then start through the one
        // existing path. The prefill carries only starting values; the running session is
        // thereafter independent of the template (ADR-023/025).
        let prefill = SessionSetupPrefill(template: template)
        let session: FocusSession?
        do {
            session = try coordinator.startSession(
                configuration: configuration,
                taskName: prefill.taskName,
                totalSessions: prefill.totalSessions
            )
        } catch {
            throw TimeFrameIntentError.couldNotStartSession
        }
        guard session != nil else { throw TimeFrameIntentError.couldNotStartSession }

        return AppIntentStartOutcome(
            taskName: prefill.taskName,
            configurationName: configuration.name,
            sessionCount: coordinator.engine.totalFocusSessions,
            isPlan: false,
            planName: nil
        )
    }

    /// Starts a session from a `SessionPlan`, reusing the existing
    /// `SessionCoordinator.startPlan` with the plan's frozen execution snapshot (ADR-056).
    /// All plan validation, snapshotting, interval generation, persistence, and timer start
    /// remain in the existing services — this only resolves the plan and hands it over.
    @discardableResult
    func startPlan(id: UUID) throws -> AppIntentStartOutcome {
        try requireNoActiveSession()

        guard let plan = try fetchPlan(id) else {
            throw TimeFrameIntentError.planUnavailable
        }
        guard plan.isStartable else {
            throw TimeFrameIntentError.planNotStartable
        }

        let snapshot = plan.executionSnapshot
        let session: FocusSession?
        do {
            session = try coordinator.startPlan(snapshot)
        } catch {
            throw TimeFrameIntentError.couldNotStartSession
        }
        guard session != nil else { throw TimeFrameIntentError.couldNotStartSession }

        return AppIntentStartOutcome(
            taskName: plan.taskName,
            configurationName: plan.name,
            sessionCount: plan.focusCount,
            isPlan: true,
            planName: plan.name
        )
    }

    // MARK: Controls

    func pause() throws {
        try requireActiveSession()
        do { try coordinator.pause() } catch { throw TimeFrameIntentError.actionFailed }
    }

    func resume() throws {
        try requireActiveSession()
        do { try coordinator.resume() } catch { throw TimeFrameIntentError.actionFailed }
    }

    /// Skips the current interval. Returns `true` when skipping completed the whole session.
    @discardableResult
    func skip() throws -> Bool {
        try requireActiveSession()
        do { try coordinator.skip() } catch { throw TimeFrameIntentError.actionFailed }
        return coordinator.engine.state == .completed
    }

    func restart() throws {
        try requireActiveSession()
        do { try coordinator.restart() } catch { throw TimeFrameIntentError.actionFailed }
    }

    func stop() throws {
        try requireActiveSession()
        do { try coordinator.stop() } catch { throw TimeFrameIntentError.actionFailed }
    }

    // MARK: Query

    /// The current authoritative session projection (read-only).
    func status() -> AppIntentSessionState {
        AppIntentSessionState(coordinator: coordinator)
    }

    // MARK: Guards & resolution

    private func requireNoActiveSession() throws {
        if coordinator.engine.state.isActive { throw TimeFrameIntentError.sessionAlreadyRunning }
    }

    private func requireActiveSession() throws {
        if !coordinator.engine.state.isActive { throw TimeFrameIntentError.noActiveSession }
    }

    /// Resolves the configuration to start from: the given id, else the user's default.
    /// Throws `configurationUnavailable` when a named configuration was deleted or the store
    /// has no default to fall back to (never a silent invalid configuration).
    private func resolveConfiguration(id: UUID?) throws -> PomodoroConfiguration {
        if let id {
            guard let configuration = try fetchConfiguration(id) else {
                throw TimeFrameIntentError.configurationUnavailable
            }
            return configuration
        }
        guard let configuration = (try? coordinator.configurations.defaultConfiguration()) ?? nil else {
            throw TimeFrameIntentError.configurationUnavailable
        }
        return configuration
    }

    private func fetchTemplate(_ id: UUID) throws -> TaskTemplate? {
        (try? coordinator.templates.template(with: id)) ?? nil
    }

    private func fetchPlan(_ id: UUID) throws -> SessionPlan? {
        (try? coordinator.plans.plan(with: id)) ?? nil
    }

    private func fetchConfiguration(_ id: UUID) throws -> PomodoroConfiguration? {
        (try? coordinator.configurations.configuration(with: id)) ?? nil
    }
}
