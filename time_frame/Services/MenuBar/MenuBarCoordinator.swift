//
//  MenuBarCoordinator.swift
//  time_frame
//
//  The menu bar's presentation/control adapter. It is NOT a second coordinator and owns
//  NO timer: it holds a reference to the one shared `SessionCoordinator`, projects its
//  authoritative state into a `MenuBarPresentationState`, and routes every control back
//  through that same coordinator (ADR-045/046/047, §30). There is exactly one
//  `SessionCoordinator` and one `TimerEngine` in the app; this observes them.
//
//  Failure isolation (§60): every control is a guarded no-op when it doesn't apply
//  (the underlying engine already ignores out-of-state messages), so "pause with no
//  session" or "resume when completed" can never crash or corrupt the timer. The menu
//  bar can only ever *ask* the coordinator to do something; it never mutates the engine.
//

import Foundation
import Observation
import os

/// Bridges the menu bar to the shared session coordinator.
///
/// `@Observable`, so a SwiftUI menu-bar view that reads `presentation` re-renders as the
/// engine changes. It is a thin adapter: the projection is recomputed on demand from the
/// authoritative engine, and the controls delegate straight to `SessionCoordinator`.
@MainActor
@Observable
final class MenuBarCoordinator {

    /// The one shared coordinator. Observed for presentation; the sole control target.
    @ObservationIgnored let session: SessionCoordinator

    /// Whether the menu-bar item should be shown, and label preferences (§26/§65).
    let preferences: MenuBarPreferencesStore

    init(session: SessionCoordinator, preferences: MenuBarPreferencesStore) {
        self.session = session
        self.preferences = preferences
    }

    /// The current projection of authoritative state. Rebuilt on every access — cheap,
    /// in-memory, and always consistent with the engine (never a cached second truth).
    var presentation: MenuBarPresentationState {
        MenuBarPresentationState(coordinator: session)
    }

    /// Whether the `MenuBarExtra` should be inserted into the menu bar.
    var isVisible: Bool { preferences.showInMenuBar }

    /// The coordinator's display-only repaint signal. The status item observes this so
    /// its countdown ticks ~1 Hz without a `TimelineView` — which loops unboundedly
    /// inside a `MenuBarExtra` label (M26, ADR-101). It is a repaint trigger only; the
    /// value shown still comes from `presentation`, derived from the engine.
    var displaySecond: Date { session.displaySecond }

    // MARK: Controls — every one routes through SessionCoordinator (§20/§47)

    func pause() { route("pause") { try session.pause() } }
    func resume() { route("resume") { try session.resume() } }
    func skip() { route("skip") { try session.skip() } }
    func stop() { route("stop") { try session.stop() } }
    func restart() { route("restart") { try session.restart() } }

    /// Clears a finished/idle run so the setup screen is shown for a fresh session.
    /// Safe: `prepareForNewSession` itself refuses to discard an active run (§60).
    func prepareForNewSession() {
        session.prepareForNewSession()
    }

    /// Runs a control and swallows any failure — a menu-bar action must never propagate
    /// an error toward the engine or crash the surface (§60).
    private func route(_ name: String, _ action: () throws -> Void) {
        do {
            try action()
        } catch {
            AppLog.session.error("Menu-bar \(name, privacy: .public) failed: \(String(describing: error), privacy: .public).")
        }
    }
}
