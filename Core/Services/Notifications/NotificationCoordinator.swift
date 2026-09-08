//
//  NotificationCoordinator.swift
//  time_frame
//
//  The junction between Time Frame and the notification integration. It owns the
//  scheduler and preferences, and it *subscribes* to the execution core's pure
//  `SessionLifecycleEvent`s to keep the OS notification queue in step with the
//  authoritative timer. It imports neither UserNotifications nor SwiftData: it speaks
//  only in pure value types and reads model values on the main actor before handing
//  work off.
//
//  The one inviolable rule: nothing here can affect the timer. Every scheduling
//  operation is deferred onto a fresh main-actor task (so the timer path has fully
//  returned) and every failure is caught, logged, and turned into a non-blocking
//  status — never rethrown toward the engine (ADR-042). It is fully independent of the
//  Calendar integration (they never call each other — §8/§63).
//

import Foundation
import Observation
import os
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The compact, user-facing state surfaced in Settings.
nonisolated enum NotificationSyncStatus: Equatable, Sendable {
    case notConfigured
    case idle
    case scheduled
    case permissionDenied
    case unavailable(String)
    case error(String)
}

@MainActor
@Observable
final class NotificationCoordinator {

    @ObservationIgnored let scheduler: NotificationScheduling
    let preferences: NotificationPreferencesStore

    /// The latest known authorization status (refreshed on demand; never prompts on
    /// its own).
    private(set) var authorizationStatus: NotificationAuthorizationStatus = .notDetermined

    /// The compact status for Settings.
    private(set) var status: NotificationSyncStatus

    /// A friendly message for the most recent failure, or nil.
    private(set) var lastErrorMessage: String?

    /// Routes a resolved timer control back through `SessionCoordinator` (§37). Wired
    /// by the app; the coordinator never touches the engine directly.
    @ObservationIgnored var performAction: ((NotificationAction) -> Void)?

    /// Supplies the current active session id and engine state so a received action can
    /// be validated against the live session (§40). Wired by the app.
    @ObservationIgnored var timerStateProvider: (() -> (activeSessionID: UUID?, state: TimerState))?

    init(
        scheduler: NotificationScheduling,
        preferences: NotificationPreferencesStore
    ) {
        self.scheduler = scheduler
        self.preferences = preferences
        self.status = preferences.isEnabled ? .idle : .notConfigured
        self.scheduler.registerCategories(Self.categoryDescriptors)
        self.scheduler.onAction = { [weak self] received in
            self?.handleAction(received)
        }
    }

    /// The categories (and their action buttons) the app registers once at launch.
    /// Running-phase notifications carry Pause/Skip; completion carries none (only the
    /// default tap opens the app). Kept deliberately small (§39).
    static let categoryDescriptors: [NotificationCategoryDescriptor] = [
        NotificationCategoryDescriptor(category: .focusStarted, actions: [.pause, .skip]),
        NotificationCategoryDescriptor(category: .shortBreakStarted, actions: [.pause, .skip]),
        NotificationCategoryDescriptor(category: .longBreakStarted, actions: [.pause, .skip]),
        NotificationCategoryDescriptor(category: .sessionCompleted, actions: [])
    ]

    // MARK: Authorization

    /// Re-reads the current authorization status without prompting.
    func refreshAuthorization() async {
        authorizationStatus = await scheduler.authorizationStatus()
        reconcileStatusWithAuthorization()
    }

    /// Requests notification authorization (prompts only when undecided). Returns the
    /// resulting status.
    @discardableResult
    func requestAuthorization() async -> NotificationAuthorizationStatus {
        let status = await scheduler.requestAuthorization()
        authorizationStatus = status
        reconcileStatusWithAuthorization()
        return status
    }

    /// Opens the system notification settings so the user can grant access after a denial
    /// (§67). macOS opens the Notifications preference pane; iOS/iPadOS opens the app's own
    /// Settings screen (the platform-correct place to flip the permission).
    func openSystemSettings() {
        #if canImport(AppKit)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    // MARK: Enabling / disabling (§17)

    /// Turns the integration on or off. Turning it off cancels every pending Time Frame
    /// notification (but never another app's) and schedules nothing further; the timer
    /// is untouched. Turning it on (re)schedules the active session, if any.
    func setEnabled(_ enabled: Bool, activeSession context: SessionLifecycleContext?, isRunning: Bool) {
        preferences.isEnabled = enabled
        if enabled {
            status = .idle
            Task { [weak self] in
                guard let self else { return }
                if self.authorizationStatus.canRequest {
                    await self.requestAuthorization()
                } else {
                    await self.refreshAuthorization()
                }
                self.reconcileActiveSession(context, isRunning: isRunning)
            }
        } else {
            status = .notConfigured
            deferWork { await $0.cancelAllPending() }
        }
    }

    // MARK: Session lifecycle subscription (§20/§24)

    /// Translates a lifecycle transition into notification scheduling. Reads the model
    /// on the main actor, then defers all scheduler work so the timer path is never
    /// blocked and never affected by a failure.
    func handle(_ event: SessionLifecycleEvent) {
        guard preferences.isEnabled else { return }
        let session = event.context.session
        let sessionID = session.id
        let prefix = NotificationIdentifier.sessionPrefix(sessionID)

        switch event {
        case .started, .resumed, .skipped:
            guard authorizationStatus.isAuthorized else { return }
            guard let snapshot = NotificationSessionSnapshot(session: session) else {
                // No running interval to anchor to; clear anything stale.
                deferWork { await $0.reschedule(prefix: prefix, descriptors: []) }
                return
            }
            let descriptors = NotificationScheduleBuilder.upcomingDescriptors(
                for: snapshot, preferences: preferences.settings)
            deferWork { await $0.reschedule(prefix: prefix, descriptors: descriptors) }

        case .paused, .stopped:
            // Cancel the session's pending transitions; the timer is paused/stopped so
            // none of them should fire (§25/§29).
            deferWork { await $0.reschedule(prefix: prefix, descriptors: []) }

        case .completed:
            let completion = completionDescriptor(for: session)
            deferWork { coordinator in
                // Cancel every pending transition for the session, then deliver the one
                // completion notification (immediate; never pre-scheduled, so it can't
                // duplicate — §30).
                await coordinator.scheduler.cancelPending(withPrefix: prefix)
                if let completion { await coordinator.trySchedule(completion) }
            }
        }
    }

    /// Reconciles the notification queue with the authoritative timer state — used on
    /// app relaunch after recovery and when the user re-enables notifications mid-run
    /// (§31/§33). Cancels stale notifications and schedules the next future transitions
    /// for a still-running session; schedules nothing for a session that is not running.
    func reconcileActiveSession(_ context: SessionLifecycleContext?, isRunning: Bool) {
        guard preferences.isEnabled, authorizationStatus.isAuthorized else {
            // Not scheduling: make sure no stale Time Frame notifications linger.
            deferWork { await $0.cancelAllPending() }
            return
        }
        guard isRunning, let session = context?.session,
              let snapshot = NotificationSessionSnapshot(session: session) else {
            deferWork { await $0.cancelAllPending() }
            return
        }
        let prefix = NotificationIdentifier.sessionPrefix(snapshot.sessionID)
        let descriptors = NotificationScheduleBuilder.upcomingDescriptors(
            for: snapshot, preferences: preferences.settings)
        deferWork { await $0.reschedule(prefix: prefix, descriptors: descriptors) }
    }

    // MARK: Received actions (§37/§40)

    /// Validates a received action against the live session and routes it — never
    /// touching the engine directly. An action for a missing/mismatched/finished
    /// session is ignored gracefully and logged.
    func handleAction(_ received: ReceivedNotificationAction) {
        let (activeID, state) = timerStateProvider?() ?? (nil, .idle)
        switch NotificationActionResolver.resolve(received, activeSessionID: activeID, state: state) {
        case let .perform(action):
            AppLog.notifications.info("Notification action performed: \(action.rawValue, privacy: .public).")
            performAction?(action)
        case .activateApp:
            activateApp()
        case let .ignore(reason):
            AppLog.notifications.info("Notification action ignored: \(reason, privacy: .public).")
        }
    }

    // MARK: Deferred scheduling helpers (the isolation guarantee)

    /// Runs scheduler work on a fresh main-actor task so the timer path has already
    /// returned, and never lets a failure escape.
    private func deferWork(_ work: @escaping (NotificationCoordinator) async -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await work(self)
        }
    }

    /// Cancels the session's pending notifications and schedules the given set. Best
    /// effort: a failure updates status but never propagates.
    private func reschedule(prefix: String, descriptors: [NotificationDescriptor]) async {
        await scheduler.cancelPending(withPrefix: prefix)
        guard !descriptors.isEmpty else {
            if preferences.isEnabled { status = .idle }
            return
        }
        var scheduledAny = false
        for descriptor in descriptors where await trySchedule(descriptor) {
            scheduledAny = true
        }
        if scheduledAny {
            status = .scheduled
            lastErrorMessage = nil
        }
    }

    /// Schedules one descriptor, catching and recording any failure. Returns whether it
    /// succeeded.
    @discardableResult
    private func trySchedule(_ descriptor: NotificationDescriptor) async -> Bool {
        do {
            try await scheduler.schedule(descriptor)
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    /// Cancels every pending Time Frame notification (only Time Frame's — §35).
    private func cancelAllPending() async {
        await scheduler.cancelPending(withPrefix: NotificationIdentifier.rootPrefix)
    }

    /// Builds the completion descriptor from the live session (main actor), or nil if
    /// there is nothing to describe or completion notifications are off.
    private func completionDescriptor(for session: FocusSession) -> NotificationDescriptor? {
        // A completed session's current interval no longer has a running target end, so
        // build the snapshot from a synthetic end (now) purely to carry task/focus
        // counts; the completion descriptor fires immediately regardless.
        let ordered = session.orderedIntervals
        guard !ordered.isEmpty else { return nil }
        let snapshot = NotificationSessionSnapshot(
            sessionID: session.id,
            taskName: session.taskName,
            currentIndex: session.currentIntervalIndex,
            currentIntervalEnd: Date(),
            intervals: ordered.map {
                NotificationSessionSnapshot.Interval(
                    index: $0.order, phase: $0.phase,
                    duration: $0.plannedDuration, configurationName: $0.configurationName)
            }
        )
        return NotificationScheduleBuilder.completionDescriptor(
            for: snapshot, preferences: preferences.settings)
    }

    private func activateApp() {
        #if canImport(AppKit)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
        AppLog.notifications.info("Notification opened Time Frame.")
    }

    // MARK: Status / failure handling

    private func reconcileStatusWithAuthorization() {
        guard preferences.isEnabled else { status = .notConfigured; return }
        switch authorizationStatus {
        case .authorized, .provisional:
            if case .permissionDenied = status { status = .idle }
        case .denied:
            status = .permissionDenied
        case .notDetermined:
            status = .idle
        }
    }

    /// Maps a failure to a friendly status/message. Never rethrows (§50).
    private func recordFailure(_ error: Error) {
        let notificationError = (error as? NotificationIntegrationError) ?? .schedulingFailed
        lastErrorMessage = notificationError.errorDescription
        switch notificationError {
        case .notAuthorized:
            status = .permissionDenied
        case .settingsUnavailable:
            status = .unavailable(notificationError.shortStatus)
        default:
            status = .error(notificationError.shortStatus)
        }
        AppLog.notifications.error("Notification operation failed: \(notificationError.shortStatus, privacy: .public).")
    }
}
