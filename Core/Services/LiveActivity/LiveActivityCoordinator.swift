//
//  LiveActivityCoordinator.swift
//  time_frame (Milestone 16)
//
//  The app-side observer/adapter that keeps a Live Activity in step with the ONE authoritative
//  session. It subscribes to the SAME pure `SessionLifecycleEvent` seam Calendar, Notifications,
//  and the widget writer use (§fan-out) plus the coordinator's meaningful-transition hook (auto
//  interval advance), maps authoritative state into a pure `LiveActivitySnapshot`, and drives the
//  isolated `LiveActivityService` (ADR-072/074).
//
//  It is a PRESENTATION surface, not a second timer: it owns no timer state, decrements no
//  counter, constructs no `FocusSession`, writes no `ModelContext`, and imports no ActivityKit.
//  Everything it knows about a session comes from reading the coordinator; everything it does to
//  the surface goes through the service protocol. Failure isolation is total — a service that is
//  unsupported, unauthorized, or throwing simply yields no activity, and the timer runs on.
//
//  Duplicate prevention & recovery (ADR-073): activity identity is the `FocusSession.id`. Starts
//  are idempotent per session id, stale activities (a different id, or an id with no live session)
//  are ended, and `reconcileOnLaunch()` converges to exactly one activity for the recovered
//  session — so relaunch, crash, sleep/wake, or repeated callbacks never leave two activities for
//  one session. Because recovery only ever surfaces this device's session (M13 device-origin
//  policy), a session owned by another device is never controlled here.
//

import Foundation
import Observation

/// Observes authoritative session state and mirrors it onto a single Live Activity.
@MainActor
@Observable
final class LiveActivityCoordinator {

    @ObservationIgnored private let session: SessionCoordinator
    @ObservationIgnored private let service: any LiveActivityService
    @ObservationIgnored let preferences: LiveActivityPreferencesStore
    @ObservationIgnored private let now: () -> Date

    /// - Parameters:
    ///   - session: the one shared coordinator (read-only here — never mutated).
    ///   - service: the isolated Live Activity service (ActivityKit adapter in the app; a fake in
    ///     tests; the no-op service under the test host).
    ///   - preferences: the UserDefaults-backed presentation preferences.
    ///   - now: the app clock (injected for deterministic tests).
    init(
        session: SessionCoordinator,
        service: any LiveActivityService,
        preferences: LiveActivityPreferencesStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.service = service
        self.preferences = preferences
        self.now = now
    }

    // MARK: Lifecycle fan-out

    /// Subscribed to the app's lifecycle fan-out. Translates a meaningful transition into a Live
    /// Activity start / update / end. Never touches the timer.
    func handle(_ event: SessionLifecycleEvent) {
        guard preferences.enabled, service.isSupported else {
            // Disabled or unsupported: ensure nothing is left running (idempotent).
            service.endAll(dismissal: .immediate)
            return
        }

        switch event {
        case .started:
            startForCurrentSession()
        case .paused, .resumed, .skipped:
            update()
        case .stopped:
            service.end(sessionID: event.context.session.id, finalContent: nil, dismissal: .immediate)
        case .completed:
            windDown(dismissal: .systemDefault, fallbackSessionID: event.context.session.id)
        }
    }

    /// Refreshes the activity from authoritative state. Called at auto interval boundaries
    /// (focus→break→focus) via the coordinator's meaningful-transition hook, which advances the
    /// engine without emitting a lifecycle event. Idempotent and best-effort.
    func update() {
        guard preferences.enabled, service.isSupported else { return }
        guard let snapshot = currentSnapshot() else { return }

        switch snapshot.content.runState {
        case .running, .paused:
            if service.activeSessionIDs().contains(snapshot.sessionID) {
                service.update(snapshot)
            } else {
                // Enabled mid-run, or a dropped activity: (re)start for this session.
                startForCurrentSession()
            }
        case .completed, .interrupted:
            windDown(dismissal: .systemDefault, fallbackSessionID: snapshot.sessionID)
        }
    }

    // MARK: Launch / recovery reconciliation

    /// Converges the Live Activity surface with the authoritative state after launch/recovery, so
    /// there is *exactly one* activity for a recovered running/paused session and *none* otherwise
    /// (ADR-073). Ends stale activities (a different session id, or any id when idle/terminal),
    /// then starts or updates the one for the current session.
    func reconcileOnLaunch() {
        guard service.isSupported else { return }
        guard preferences.enabled else { service.endAll(dismissal: .immediate); return }

        let existing = Set(service.activeSessionIDs())
        guard let snapshot = currentSnapshot(), snapshot.content.runState.isActive else {
            // No live session to surface: clear everything left over from before.
            if !existing.isEmpty { service.endAll(dismissal: .immediate) }
            return
        }

        for staleID in existing where staleID != snapshot.sessionID {
            service.end(sessionID: staleID, finalContent: nil, dismissal: .immediate)
        }

        if existing.contains(snapshot.sessionID) {
            service.update(snapshot)
        } else {
            service.start(snapshot)
        }
    }

    /// Applies a preference change immediately: if the user disabled Live Activities mid-run, end
    /// the current one; if they enabled it while a session is active, start it. Wired from the
    /// Settings toggle so the change is not deferred to the next transition.
    func preferencesDidChange() {
        guard service.isSupported else { return }
        if preferences.enabled {
            update()
        } else {
            service.endAll(dismissal: .immediate)
        }
    }

    // MARK: Helpers

    /// Starts (idempotently) the activity for the current session, ending any stale activity for
    /// a *different* session first — the core duplicate-prevention step.
    private func startForCurrentSession() {
        guard let snapshot = currentSnapshot() else { return }
        for staleID in service.activeSessionIDs() where staleID != snapshot.sessionID {
            service.end(sessionID: staleID, finalContent: nil, dismissal: .immediate)
        }
        service.start(snapshot)
    }

    /// Ends the current activity with a final content update, falling back to the given session id
    /// when no snapshot can be built (e.g. the engine already returned to idle).
    private func windDown(dismissal: LiveActivityDismissal, fallbackSessionID: UUID) {
        if let snapshot = currentSnapshot() {
            service.end(sessionID: snapshot.sessionID, finalContent: snapshot.content, dismissal: dismissal)
        } else {
            service.end(sessionID: fallbackSessionID, finalContent: nil, dismissal: dismissal)
        }
    }

    /// The current authoritative snapshot, redacted per the user's presentation preferences
    /// (hide task / configuration), or `nil` when there is nothing to show. Redaction touches
    /// only the frozen identity — the dynamic content (phase, timestamps, progress) is untouched.
    private func currentSnapshot() -> LiveActivitySnapshot? {
        guard var snapshot = LiveActivityContentMapper.snapshot(from: session, now: now()) else { return nil }
        if !preferences.showsTaskName { snapshot.identity.taskName = "" }
        if !preferences.showsConfiguration { snapshot.identity.configurationName = "" }
        return snapshot
    }
}
