//
//  LiveActivityService.swift
//  time_frame (Milestone 16)
//
//  The isolation boundary for ActivityKit. The `LiveActivityCoordinator` and the rest of the
//  app talk to this protocol in terms of PURE value types (`LiveActivitySnapshot` /
//  `TimeFrameLiveActivityContent`); only the concrete `ActivityKitLiveActivityService` adapter
//  imports ActivityKit and drives real `Activity` objects (ADR-074). This means:
//
//    • `TimerEngine`, `SessionCoordinator`, and the whole domain never see ActivityKit.
//    • Every unit test injects a fake conforming to this protocol — no ActivityKit runtime is
//      ever required to test lifecycle, recovery, duplicate prevention, or failure isolation.
//    • A Live Activity failure (unsupported, unauthorized, throw on start/update/end, system
//      termination) is contained here and can never reach — let alone stop — the timer.
//
//  Foundation-only: this file imports no ActivityKit. The protocol is `@MainActor` because the
//  coordinator that calls it, and the authoritative state it projects, are main-actor isolated.
//

import Foundation

/// How a finished Live Activity should be dismissed. A neutral projection of ActivityKit's
/// `ActivityUIDismissalPolicy`, so the coordinator can express intent without importing the
/// framework; the adapter maps it to the real policy.
enum LiveActivityDismissal: Equatable, Sendable {
    /// Let the system decide when to remove it (a short grace period after a final update).
    case systemDefault
    /// Remove it immediately (e.g. the user stopped the session).
    case immediate
    /// Keep it visible until a specific instant, then remove it.
    case after(Date)
}

/// The app's view of the Live Activity surface. Implemented by the ActivityKit adapter in the
/// app and by a fake in tests. Every method is best-effort and MUST NOT throw toward the caller:
/// a Live Activity is a presentation surface and its failures are swallowed by the adapter.
@MainActor
protocol LiveActivityService: AnyObject {
    /// Whether the platform/target can host Live Activities at all (compile + runtime support).
    var isSupported: Bool { get }

    /// Whether the user currently has Live Activities enabled for this app (authorization).
    /// Cheap and synchronous; the adapter reads ActivityKit's `areActivitiesEnabled`.
    func areActivitiesEnabled() -> Bool

    /// The session ids of every Live Activity this app currently has running. Used for
    /// reconciliation and duplicate prevention (ADR-073) — never to drive the timer.
    func activeSessionIDs() -> [UUID]

    /// Starts a Live Activity for the snapshot's session, unless one already exists for that
    /// session id (idempotent — never creates a duplicate). Returns `true` if an activity is
    /// running for the session afterwards (started now or already present).
    @discardableResult
    func start(_ snapshot: LiveActivitySnapshot) -> Bool

    /// Updates the running activity for the snapshot's session id, if any. A no-op when none
    /// exists (it does NOT implicitly start one — starting is a deliberate lifecycle decision).
    func update(_ snapshot: LiveActivitySnapshot)

    /// Ends the activity for `sessionID`, applying an optional final content and a dismissal
    /// policy. A no-op when no activity exists for that id.
    func end(sessionID: UUID, finalContent: TimeFrameLiveActivityContent?, dismissal: LiveActivityDismissal)

    /// Ends every running Time Frame activity (used to clear stale activities on reconciliation).
    func endAll(dismissal: LiveActivityDismissal)
}

/// The inert service used where Live Activities must never run — the unit-test host (hermeticity,
/// §M9 guard) and any environment without ActivityKit support. It records nothing and does
/// nothing, so wiring it in keeps the fan-out shape identical while guaranteeing no real activity
/// is ever created.
@MainActor
final class NoopLiveActivityService: LiveActivityService {
    var isSupported: Bool { false }
    func areActivitiesEnabled() -> Bool { false }
    func activeSessionIDs() -> [UUID] { [] }
    @discardableResult func start(_ snapshot: LiveActivitySnapshot) -> Bool { false }
    func update(_ snapshot: LiveActivitySnapshot) {}
    func end(sessionID: UUID, finalContent: TimeFrameLiveActivityContent?, dismissal: LiveActivityDismissal) {}
    func endAll(dismissal: LiveActivityDismissal) {}
}
