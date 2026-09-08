//
//  CalendarCoordinator.swift
//  time_frame
//
//  The junction between Time Frame and the Calendar integration. It owns the
//  service, preferences, and stored associations, and it *subscribes* to the
//  execution core's pure `SessionLifecycleEvent`s to reflect a running session on
//  the calendar. It imports neither EventKit nor SwiftData: it speaks only in pure
//  value types and reads model values on the main actor before handing work off.
//
//  The one inviolable rule: nothing here can affect the timer. Every calendar
//  operation is deferred onto a fresh main-actor task (so the timer path has fully
//  returned) and every failure is caught, logged, and turned into a non-blocking
//  status — never rethrown toward the engine (ADR-035).
//

import Foundation
import Observation
import os
#if canImport(AppKit)
import AppKit
#endif

/// The compact, user-facing sync state surfaced by `CalendarSyncStatusView`.
nonisolated enum CalendarSyncStatus: Equatable, Sendable {
    case notConfigured
    case idle
    case syncing
    case synced
    case unavailable(String)
    case permissionDenied
    case error(String)
}

@MainActor
@Observable
final class CalendarCoordinator {

    @ObservationIgnored let service: CalendarService
    let preferences: CalendarPreferencesStore
    @ObservationIgnored let records: CalendarEventRecordStore

    /// The latest known authorization status (refreshed on demand; never prompts
    /// on its own).
    private(set) var authorizationStatus: CalendarAuthorizationStatus = .notDetermined

    /// Writable calendars, loaded once access is granted.
    private(set) var availableCalendars: [CalendarDescriptor] = []

    /// The compact sync status for the timer/plan UI.
    private(set) var syncStatus: CalendarSyncStatus = .notConfigured

    /// A friendly message for the most recent failure, or nil.
    private(set) var lastErrorMessage: String?

    init(
        service: CalendarService,
        preferences: CalendarPreferencesStore,
        records: CalendarEventRecordStore
    ) {
        self.service = service
        self.preferences = preferences
        self.records = records
        self.authorizationStatus = service.authorizationStatus()
        self.syncStatus = preferences.isEnabled ? .idle : .notConfigured
    }

    // MARK: Authorization

    /// Re-reads the current authorization status without prompting.
    func refreshAuthorization() {
        authorizationStatus = service.authorizationStatus()
    }

    /// Requests Calendar access (prompts only when undecided), then refreshes
    /// calendars if the grant is sufficient. Returns the resulting status.
    @discardableResult
    func requestAccess() async -> CalendarAuthorizationStatus {
        let status = await service.requestAccess()
        authorizationStatus = status
        if status.isSufficient {
            await loadCalendars()
        } else if status.requiresSystemSettings {
            syncStatus = .permissionDenied
        }
        return status
    }

    /// Loads the writable calendars (no-op without sufficient access).
    func loadCalendars() async {
        guard authorizationStatus.isSufficient else { return }
        do {
            availableCalendars = try service.writableCalendars()
            // Drop a stored default that no longer resolves (§20).
            if let id = preferences.defaultCalendarIdentifier,
               !availableCalendars.contains(where: { $0.id == id }) {
                preferences.defaultCalendarIdentifier = nil
            }
            if preferences.isEnabled { syncStatus = .idle }
        } catch {
            recordFailure(error)
        }
    }

    /// Opens the macOS Calendar privacy pane so the user can grant access after a
    /// denial. Uses the system-settings scheme (§80).
    func openSystemSettings() {
        #if canImport(AppKit)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: Manual plan → calendar

    /// The stored association for a plan, if it has already been added.
    func record(for plan: SessionPlan) -> CalendarEventRecord? {
        records.record(for: plan.id)
    }

    /// Builds the drafts a plan would create, for the preview (pure; no I/O).
    func previewDrafts(
        for plan: SessionPlan,
        startDate: Date,
        style: CalendarEventStyle,
        calendarIdentifier: String?,
        titleOverride: String?
    ) -> [CalendarEventDraft] {
        let context = CalendarPlanContext(
            snapshot: plan.executionSnapshot,
            planName: plan.name,
            startDate: startDate
        )
        return CalendarEventGenerator.drafts(
            for: context,
            style: style,
            calendarIdentifier: calendarIdentifier,
            titleOverride: titleOverride
        )
    }

    /// Adds a plan to the calendar (or re-adds it, replacing any prior events for
    /// the same plan so no duplicates accumulate — §24). Returns true on success.
    @discardableResult
    func addPlan(
        _ plan: SessionPlan,
        startDate: Date,
        style: CalendarEventStyle,
        calendarIdentifier: String?,
        titleOverride: String?
    ) async -> Bool {
        guard authorizationStatus.isSufficient else {
            syncStatus = .permissionDenied
            return false
        }
        syncStatus = .syncing
        // Replace any existing events for this plan first, so a re-add never leaves
        // orphaned duplicates.
        if let existing = records.record(for: plan.id) {
            for reference in existing.references { try? service.deleteEvent(reference) }
        }
        let drafts = previewDrafts(
            for: plan,
            startDate: startDate,
            style: style,
            calendarIdentifier: calendarIdentifier,
            titleOverride: titleOverride
        )
        do {
            var references: [CalendarEventReference] = []
            for draft in drafts { references.append(try service.createEvent(draft)) }
            records.upsert(CalendarEventRecord(
                ownerType: .plan,
                ownerID: plan.id,
                style: style,
                references: references
            ))
            syncStatus = .synced
            lastErrorMessage = nil
            AppLog.calendar.info("Added plan to calendar (\(references.count, privacy: .public) events).")
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    /// Explicitly removes the calendar events associated with an owner (a plan or a
    /// session) and forgets the association. Only ever called on an explicit user
    /// choice — deleting a plan never calls this (§39/§57).
    func removeEvents(forOwner ownerID: UUID) async {
        guard let record = records.record(for: ownerID) else { return }
        for reference in record.references { try? service.deleteEvent(reference) }
        records.remove(ownerID: ownerID)
        AppLog.calendar.info("Removed calendar events for owner.")
    }

    // MARK: Session lifecycle subscription

    /// Reflects a live session transition on the calendar, honouring the user's
    /// settings. Reads the model on the main actor, then defers all calendar work
    /// so the timer path is never blocked and never affected by a failure.
    func handle(_ event: SessionLifecycleEvent) {
        guard preferences.isEnabled else { return }
        let context = event.context
        let payload = LivePayload(from: context)

        switch event {
        case .started:
            guard preferences.creationTrigger.createsOnSessionStart else { return }
            deferCalendarWork { await $0.createLiveEvent(payload) }
        case .paused, .resumed, .skipped:
            deferCalendarWork { await $0.adjustLiveEventEnd(payload, to: payload.projectedEnd) }
        case .stopped, .completed:
            // Keep the event (never delete the user's history — §35); reflect the
            // actual end time.
            deferCalendarWork { await $0.adjustLiveEventEnd(payload, to: payload.now) }
        }
    }

    // MARK: Live-event helpers

    /// The pure values extracted from a live session, so no SwiftData model crosses
    /// the deferred-task boundary.
    private struct LivePayload {
        let ownerID: UUID
        let taskName: String
        let now: Date
        let projectedEnd: Date
        let intervals: [CalendarPlanContext.Interval]

        init(from context: SessionLifecycleContext) {
            let session = context.session
            self.ownerID = session.id
            self.taskName = session.taskName
            self.now = context.now
            self.intervals = session.orderedIntervals.map {
                CalendarPlanContext.Interval(
                    phase: $0.phase,
                    duration: $0.plannedDuration,
                    configurationName: $0.configurationName
                )
            }
            // Projected end falls back to start + total when the engine gave none
            // (terminal transitions), and is clamped so it never precedes the start.
            let total = self.intervals.reduce(0) { $0 + $1.duration }
            self.projectedEnd = context.projectedEnd ?? context.now.addingTimeInterval(total)
        }

        /// The whole-session context used to build the single live event.
        var planContext: CalendarPlanContext {
            CalendarPlanContext(taskName: taskName, planName: "", startDate: now, intervals: intervals)
        }
    }

    /// Runs calendar work on a fresh main-actor task so the timer path has already
    /// returned, and never lets a failure escape. This is the isolation guarantee.
    private func deferCalendarWork(_ work: @escaping (CalendarCoordinator) async -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await work(self)
        }
    }

    /// Creates the single whole-session event for a freshly started session (§30 —
    /// actual start time, never a fabricated one). A live session always uses one
    /// event so pause/resume/stop stay correct; the per-interval style is offered
    /// for manual plan adds (ADR-036).
    private func createLiveEvent(_ payload: LivePayload) async {
        guard authorizationStatus.isSufficient else {
            syncStatus = .permissionDenied
            return
        }
        // A record already existing for this session id means the event is already
        // there (e.g. a repeated emit) — update its end rather than duplicate (§24).
        if let existing = records.record(for: payload.ownerID) {
            await adjustLiveEventEnd(payload, to: payload.projectedEnd, existing: existing)
            return
        }
        syncStatus = .syncing
        let context = CalendarPlanContext(
            taskName: payload.taskName, planName: "",
            startDate: payload.now, intervals: payload.intervals
        )
        let drafts = CalendarEventGenerator.drafts(
            for: context, style: .singlePlan,
            calendarIdentifier: preferences.defaultCalendarIdentifier, titleOverride: nil
        )
        guard let draft = drafts.first else { return }
        do {
            let reference = try service.createEvent(draft)
            records.upsert(CalendarEventRecord(
                ownerType: .session,
                ownerID: payload.ownerID,
                style: .singlePlan,
                references: [reference]
            ))
            syncStatus = .synced
            lastErrorMessage = nil
        } catch {
            recordFailure(error)
        }
    }

    /// Adjusts the live event's end to a new time (pause/resume/skip/stop/complete).
    /// Only the end date changes — user-owned title/notes are never touched (§37).
    private func adjustLiveEventEnd(
        _ payload: LivePayload,
        to endDate: Date,
        existing: CalendarEventRecord? = nil
    ) async {
        guard let record = existing ?? records.record(for: payload.ownerID) else { return }
        guard let reference = record.references.first else { return }
        do {
            try service.adjustEventEnd(reference, to: endDate)
            syncStatus = .synced
            lastErrorMessage = nil
        } catch let error as CalendarIntegrationError where error == .eventNotFound {
            // The user deleted the event externally — forget it; do not recreate
            // silently (§79).
            records.remove(ownerID: payload.ownerID)
            syncStatus = .unavailable(error.shortStatus)
            AppLog.calendar.info("Live event missing; association cleared.")
        } catch {
            recordFailure(error)
        }
    }

    // MARK: Failure handling

    /// Maps a failure to a friendly status/message. Never rethrows.
    private func recordFailure(_ error: Error) {
        let calendarError = (error as? CalendarIntegrationError) ?? .saveFailed
        lastErrorMessage = calendarError.errorDescription
        switch calendarError {
        case .notAuthorized, .accessRestricted:
            authorizationStatus = service.authorizationStatus()
            syncStatus = .permissionDenied
        case .calendarUnavailable, .invalidCalendar, .noWritableCalendars:
            syncStatus = .unavailable(calendarError.shortStatus)
        default:
            syncStatus = .error(calendarError.shortStatus)
        }
        AppLog.calendar.error("Calendar operation failed: \(calendarError.shortStatus, privacy: .public).")
    }
}
