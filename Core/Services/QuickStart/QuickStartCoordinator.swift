//
//  QuickStartCoordinator.swift
//  time_frame (Milestone 28)
//
//  The observable adapter behind the menu bar's Quick Start section (ADR-104/105).
//
//  Like `MenuBarCoordinator`, it is NOT a second coordinator and owns NO timer. It holds the
//  one shared `SessionCoordinator`, keeps a cached list of pinned items for the popover to
//  draw, and routes a start back through the SAME `AppIntentSessionActions` seam every other
//  integration uses:
//
//      Quick Start row → AppIntentSessionActions.startTemplate/startPlan
//                      → SessionCoordinator.startSession/startPlan → TimerEngine
//
//  Why a cached list rather than a `@Query`: the `MenuBarExtra` scene has no SwiftData
//  environment (only the `WindowGroup` carries the model container), so the popover cannot
//  query. The cache is refreshed **event-driven** — the template and plan repositories fire
//  their neutral `onChange` hook after every successful mutation, and the app wires that hook
//  to `refresh()`. There is no polling and no timer: pinning, renaming, editing an icon, or
//  deleting an item updates the menu bar on the next mutation, with no app restart (ADR-105).
//
//  The cache is a *display* cache only. Starting an item re-resolves the authoritative
//  template/plan by its stable id, so a stale row can never start something that no longer
//  exists — it fails safely through the existing closed `TimeFrameIntentError` set.
//

import Foundation
import Observation
import os

/// Supplies and starts the user's pinned Quick Start items.
@MainActor
@Observable
final class QuickStartCoordinator {

    /// The one shared coordinator: the read source for the repositories and the sole
    /// (indirect) control target. Never a second timer.
    @ObservationIgnored let session: SessionCoordinator

    /// The pinned items, in Quick Start order. Refreshed on demand and on every repository
    /// change; never mutated by the timer.
    private(set) var items: [QuickStartItem] = []

    /// The most recent start failure, in user-facing language, or `nil`. The popover shows it
    /// inline; it never blocks or alerts, because a failed Quick Start is a convenience
    /// failure, not a timer failure.
    var lastErrorMessage: String?

    init(session: SessionCoordinator) {
        self.session = session
    }

    /// Whether any pinned item exists (drives the empty-state copy).
    var isEmpty: Bool { items.isEmpty }

    /// Whether starting is currently possible at all — a session already running blocks every
    /// Quick Start row, matching `AppIntentSessionActions.requireNoActiveSession`.
    var canStart: Bool { !session.engine.state.isActive }

    /// Clears a stale failure message. Called when the popover shows Quick Start again, so a
    /// message from an earlier interaction ("a session is already running") does not linger after
    /// the situation that caused it has passed.
    func clearError() {
        lastErrorMessage = nil
    }

    // MARK: Refresh (event-driven; never polled)

    /// Rebuilds the list from the authoritative repositories. Cheap, defensive, and safe to
    /// call from a repository change hook: it reads pinned rows only and swallows any failure.
    func refresh() {
        items = QuickStartProvider.items(templates: session.templates, plans: session.plans)
    }

    // MARK: Start (routes through the one existing seam)

    /// Starts the given pinned item through `AppIntentSessionActions` — the same seam the
    /// widget controls, Control Center, and Siri use. This introduces no new start path: the
    /// template chain stays `TaskTemplate → SessionSetupPrefill → startSession`, and the plan
    /// chain stays `SessionPlan.executionSnapshot → startPlan`.
    ///
    /// Returns `true` when a session actually started. A failure is recorded in
    /// `lastErrorMessage` and never propagates toward the engine.
    @discardableResult
    func start(_ item: QuickStartItem) -> Bool {
        lastErrorMessage = nil
        let actions = AppIntentSessionActions(coordinator: session)
        do {
            switch item.kind {
            case .template:
                _ = try actions.startTemplate(id: item.id)
            case .plan:
                _ = try actions.startPlan(id: item.id)
            }
            return true
        } catch let error as TimeFrameIntentError {
            // Reuse the closed error set's own user-facing phrasing — no second vocabulary.
            lastErrorMessage = error.errorDescription
        } catch {
            lastErrorMessage = "Couldn't start \(item.displayName)."
        }
        AppLog.session.error(
            "Quick Start failed for \(item.kind.rawValue, privacy: .public): \(self.lastErrorMessage ?? "", privacy: .public)")
        // The list may be stale if the item was deleted elsewhere; re-read the truth.
        refresh()
        return false
    }
}
