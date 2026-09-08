//
//  WidgetControlRouting.swift
//  time_frame (Milestone 15)
//
//  The app-side wiring that makes the widget's interactive buttons act on the ONE authoritative
//  timer. The shared `WidgetControlActions` router (compiled into both app and widget) holds a
//  single main-actor closure; here — in the app target, where the domain lives — we build that
//  closure so it delegates every action to the existing Milestone-12 `AppIntentSessionActions`
//  (the one and only place an intent mutates the timer, ADR-056) and then refreshes the widget
//  projection so the surface reflects the new authoritative state (ADR-069/071).
//
//  Nothing here is a second timer, a second coordinator, or a second store: it constructs no
//  `FocusSession`, writes no `ModelContext`, and introduces no timer primitive. It only
//  translates a `WidgetControlAction` into an existing coordinator call (via the existing seam)
//  and asks the existing `WidgetProjectionWriter` to re-mirror state. Domain failures surface as
//  the existing `TimeFrameIntentError`, which propagates through the shared intent untouched.
//

import Foundation

/// Builds the app's `WidgetControlActions` router. Called once at launch from `time_frameApp`,
/// then registered with the App Intents dependency manager so the shared widget-control intents
/// resolve it when the system runs them in the app process.
@MainActor
enum WidgetControlRouting {

    /// - Parameters:
    ///   - coordinator: the app's single `SessionCoordinator` (never a new one).
    ///   - refreshProjection: pushes a fresh widget projection + reload after an action, so the
    ///     widget always reflects the new authoritative state — including `restart`, which the
    ///     coordinator applies without emitting a lifecycle event. Fire-and-forget; must never
    ///     throw toward the timer.
    static func makeActions(
        coordinator: SessionCoordinator,
        refreshProjection: @escaping @MainActor () -> Void
    ) -> WidgetControlActions {
        WidgetControlActions(
            handler: { action in
                try perform(action, coordinator: coordinator, refreshProjection: refreshProjection)
            },
            // The Control Center adaptive control (Milestone 22): resolve the contextually correct
            // action from LIVE authoritative state — mapped by the SAME projection mapper the widget
            // reads, then the pure `ControlCenterControlSet.primaryAction(for:)` — and perform it
            // through the exact same seam. No second router, no second decision path (ADR-090).
            primaryHandler: {
                let projection = WidgetProjectionMapper.projection(from: coordinator, now: Date())
                let state = ControlCenterSessionState(projection: projection)
                let action = ControlCenterControlSet.primaryAction(for: state)
                return try perform(action, coordinator: coordinator, refreshProjection: refreshProjection)
            },
            // The configurable quick-start control (Milestone 23): start a session from the
            // user-selected configuration id (or the default when `nil`) through the SAME
            // `AppIntentSessionActions.startSession` seam. The selected id is DATA supplied by the
            // control; the app re-resolves the AUTHORITATIVE configuration here, so a deleted
            // configuration fails safely and a rename takes effect on tap (ADR-094/095). One seam,
            // one engine — no second start path.
            quickStartHandler: { configurationID in
                try performQuickStart(
                    configurationID: configurationID,
                    coordinator: coordinator,
                    refreshProjection: refreshProjection
                )
            }
        )
    }

    /// Starts a session from an (optional) configuration id through the ONE mutation seam and
    /// refreshes the widget projection. `nil` starts from the user's default configuration. Domain
    /// failures (configuration deleted, session already running) throw `TimeFrameIntentError`,
    /// which the shared quick-start intent surfaces verbatim — never a crash, never a second timer.
    @MainActor
    private static func performQuickStart(
        configurationID: UUID?,
        coordinator: SessionCoordinator,
        refreshProjection: @MainActor () -> Void
    ) throws -> WidgetControlResult {
        let seam = AppIntentSessionActions(coordinator: coordinator)
        let outcome = try seam.startSession(
            configurationID: configurationID,
            taskName: nil,
            totalSessions: nil
        )
        // Re-mirror authoritative state to the widget surfaces (best-effort; never affects the
        // engine), exactly as an explicit `.start` does.
        refreshProjection()
        return WidgetControlResult(
            confirmation: AppIntentDialogText.started(
                task: outcome.taskName,
                configurationName: outcome.configurationName,
                sessionCount: outcome.sessionCount
            )
        )
    }

    /// Performs one `WidgetControlAction` through the ONE mutation seam and refreshes the widget
    /// projection. Shared by the explicit-action handler and the Control Center primary resolver so
    /// both go through identical logic — there is exactly one place a control action mutates the
    /// timer. Domain failures throw `TimeFrameIntentError`, which the shared intent surfaces verbatim.
    @MainActor
    private static func perform(
        _ action: WidgetControlAction,
        coordinator: SessionCoordinator,
        refreshProjection: @MainActor () -> Void
    ) throws -> WidgetControlResult {
        let seam = AppIntentSessionActions(coordinator: coordinator)
        let confirmation: String
        switch action {
        case .pause:
            try seam.pause()
            confirmation = AppIntentDialogText.paused
        case .resume:
            try seam.resume()
            confirmation = AppIntentDialogText.resumed
        case .skip:
            let didComplete = try seam.skip()
            confirmation = didComplete ? AppIntentDialogText.completedBySkip : AppIntentDialogText.skipped
        case .restart:
            try seam.restart()
            confirmation = AppIntentDialogText.restarted
        case .stop:
            try seam.stop()
            confirmation = AppIntentDialogText.stopped
        case .start:
            let outcome = try seam.startSession(configurationID: nil, taskName: nil, totalSessions: nil)
            confirmation = AppIntentDialogText.started(
                task: outcome.taskName,
                configurationName: outcome.configurationName,
                sessionCount: outcome.sessionCount
            )
        }
        // Re-mirror authoritative state to the widget projection. Idempotent and best-effort:
        // most actions already refreshed it via the lifecycle fan-out; `restart` relies on
        // this call. Never affects the engine.
        refreshProjection()
        return WidgetControlResult(confirmation: confirmation)
    }
}
