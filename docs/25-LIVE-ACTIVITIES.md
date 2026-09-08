# 25 — Live Activities / Live Session Surface (Milestone 16)

> **Status: platform-neutral core implemented (M16); real Live Activities shipped on iOS/iPadOS in
> Milestone 18. Live Activities remain NOT available on macOS.**
> Time Frame is a **native macOS 27** app. ActivityKit / Live Activities are
> `@available(macOS, unavailable)` — the framework ships in the macOS SDK **only for Mac
> Catalyst**. A native (AppKit/SwiftUI-on-macOS) target therefore **cannot** create or host a
> Live Activity, and the macOS app stays **ActivityKit-free**. Milestone 16 was delivered honestly as a
> **platform-feasibility milestone**: the reusable, platform-neutral *live-session core* built and
> tested here. **Milestone 18 completed the feature on iOS/iPadOS** — the `TimeFrameiOS` companion and
> `TimeFrameiOSWidgets` extension add the real `ActivityKit` layer (adapter + `ActivityConfiguration` +
> Dynamic Island), reusing this core unchanged (`TimeFrameLiveActivityContent` is the `ContentState`).
>
> **Milestone 19 note.** The Live Activity remains a **device-local, read-only presentation** keyed to
> `FocusSession.id` — never a cross-device timer, even under CloudKit sync. macOS stays ActivityKit-free
> (enforced by `ProductionReadinessPlatformTests`). M19 changes nothing here; on-device Live Activity /
> Dynamic Island / VoiceOver visuals remain **unverified** (no physical device in this environment). See
> `docs/28-CLOUDKIT-DEVICE-VALIDATION.md` §10–11.
> See `docs/27-IOS-COMPANION-LIVE-ACTIVITIES.md` and ADR-079. **No fabricated macOS ActivityKit
> implementation exists.**

---

## 1. Platform support (proven, not assumed)

The installed toolchain is **Xcode 27.0 (27A5194q)**; the app builds against the **macOS 27.0**
SDK with `MACOSX_DEPLOYMENT_TARGET = 27.0`, `SDKROOT = macosx` for **all** targets (app, widget,
tests). There is no iOS/iPadOS/watchOS target.

`ActivityKit.framework` *is* present in the macOS SDK, but its Swift interface makes availability
explicit. From
`MacOSX27.0.sdk/…/ActivityKit.framework/…/arm64e-apple-macos.swiftinterface`:

```swift
@available(iOS 16.1, *)
@available(macOS, unavailable)      // ← native macOS cannot use it
@available(macCatalyst, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public protocol ActivityAttributes : Decodable, Encodable { … }
```

Every core symbol (`Activity`, `Activity.request`, `ActivityContent`, `ActivityAuthorizationInfo`,
`ActivityConfiguration`, `DynamicIsland`, `ActivityFamily`) carries `@available(macOS, unavailable)`
— **73** such annotations across the module. The compiler confirms it: attempting to declare a
`struct … : ActivityAttributes` in a macOS target fails with **`'ActivityAttributes' is unavailable
in macOS`**. The framework exists in the SDK to support **Mac Catalyst** apps (iOS apps running on
the Mac), not native macOS apps.

**Conclusion.** Live Activities cannot be implemented for the existing native-macOS target. Forcing
one would require fabricating unavailable APIs — explicitly out of bounds for this milestone.

## 2. Why we did not add a companion target now

A supported Live Activity would require an **iOS/iPadOS app target** (a new product, its own scenes,
`WindowGroup`s, lifecycle, entitlements, app icon, and — for a shared timer — a strategy for where
the authoritative `TimerEngine`/`SessionCoordinator` runs on iOS). That is a **product-scope
decision**, not a mechanical addition, and it would touch the project structure well beyond a
presentation surface. Per the milestone's rule ("if adding a companion target would require major
product restructuring, STOP … and produce a feasibility report rather than inventing unsupported
functionality"), we did **not** add an iOS target. Instead we built the part that carries genuine,
platform-independent value now, so a future iOS target is a small, well-scoped addition (§10).

## 3. Target architecture (what a supported build looks like)

```
TimerEngine                 (the one authoritative timer — unchanged)
    ↓
SessionCoordinator          (the one control authority — unchanged)
    ↓
SessionLifecycleEvent       (the existing fan-out seam)
    ↓
LiveActivityCoordinator     (observer/adapter — BUILT, platform-neutral)
    ↓
LiveActivityService         (protocol — BUILT, Foundation-only)
    ↓
[ActivityKit adapter]       (iOS/iPadOS-only — NOT built; the one file that imports ActivityKit)
    ↓
Live Activity UI            (iOS/iPadOS-only — NOT built; ActivityConfiguration + Dynamic Island)
```

The Live Activity is a **presentation surface**. It never owns timing state, never becomes a second
timer, never reconstructs Pomodoro rules, never mutates SwiftData, and never constructs a
`SessionCoordinator`/`TimerEngine`. It observes the **same** `SessionLifecycleEvent` seam as
Calendar/Notifications/Widgets and is independent of every other integration.

## 4. Attributes (static) — `LiveActivityIdentity`

Frozen for the life of one activity; a future `ActivityAttributes` wraps these verbatim:

| Field | Meaning |
|---|---|
| `sessionID: UUID` | the authoritative `FocusSession.id` — **the only** activity-identity key |
| `taskName: String` | task label at start (may be empty / redacted) |
| `configurationName: String` | frozen configuration/plan name (may be redacted) |
| `sessionStartedAt: Date` | when the session started (frozen) |

## 5. Content state (dynamic) — `TimeFrameLiveActivityContent`

The immutable per-update projection; intended to be used directly as
`ActivityAttributes.ContentState`:

| Field | Meaning |
|---|---|
| `runState` | running / paused / completed / interrupted |
| `phase` | focus / shortBreak / longBreak / none (shared `WidgetPhase`) |
| `phaseStartedAt`, `phaseTargetEndAt` | **frozen** anchors for a `Text(timerInterval:)` countdown |
| `pausedRemainingSeconds` | frozen remaining while paused (no fake advance) |
| `sessionIndex`, `totalFocusSessions`, `completedFocusCount` | progress |
| `nextPhase`, `nextPhaseTargetEndAt` | the phase that follows (derived from the engine plan) |

Both are pure, `Codable`, `Sendable`, Foundation-only value types in
`Shared/LiveSessionProjection.swift`. The app maps authoritative state into them via
`LiveActivityContentMapper` (mirroring `WidgetProjectionMapper` exactly — same math, no persistence,
no clock). Nothing derived is persisted; snapshots are recomputed from live state and reproducible.

## 6. Lifecycle

`LiveActivityCoordinator.handle(_:)` reacts to the shared lifecycle fan-out:

| Event | Action |
|---|---|
| `.started` | end any stale activity for a different session, then start (idempotent) |
| `.paused` / `.resumed` / `.skipped` | update the content in place |
| auto boundary (focus→break→focus) | `update()` via `onMeaningfulTransition` (never per tick) |
| `.stopped` | end immediately |
| `.completed` | final content update, then end (system-default dismissal) |
| launch / recovery | `reconcileOnLaunch()` converges to exactly one activity (§7) |

Updates occur **only** on meaningful transitions — never on a timer tick. The running countdown is a
timestamp-driven **repaint** (`Text(timerInterval:)`); no `Timer`/`Timer.publish`/`scheduledTimer`/
`DispatchSourceTimer`/`Task.sleep`/`asyncAfter`/decrement is ever introduced (ADR-072).

## 7. Duplicate prevention & recovery (ADR-073)

Activity identity is the **`FocusSession.id`** — never the task or configuration name. The service's
`activeSessionIDs()` reads the system's live set of activities (in a real adapter, ActivityKit's own
`Activity.activities`), so it stays correct across relaunch. `reconcileOnLaunch()`:

1. If disabled/unsupported → end all.
2. If there is no **local** active session (idle / completed / interrupted) → end all stale
   activities, start none.
3. Otherwise → end every activity whose id ≠ the current session, then **update** the current one if
   present or **start** it if missing.

This yields **exactly one** activity for a recovered running/paused session and **none** otherwise,
after relaunch, crash, sleep/wake, or repeated callbacks. Because recovery only ever surfaces **this
device's** session (Milestone 13 device-origin policy: `fetchRecoverableSession` recovers only
sessions started on this device), a session owned by another device never gains a controllable
activity here.

## 8. Failure isolation

Every ActivityKit operation is (would be) confined to the `LiveActivityService` adapter and is
best-effort: unsupported, unauthorized, throwing start/update/end, or a system-terminated activity
all resolve to *no activity* — never a rethrow toward the timer. The `LiveActivityCoordinator` only
**reads** the coordinator and **calls** the service; it can never affect `TimerEngine`,
`SessionCoordinator`, SwiftData, history, Calendar, Notifications, Widgets, or App Intents. Pinned by
`LiveActivityFailureIsolationTests` (a rejecting/unsupported service leaves the timer fully
functional; engine behaviour is byte-for-byte identical with and without the observer).

## 9. App Intent routing (no new seam)

A Live Activity control is just another command surface. A supported build reuses the **exact**
Milestone-15 seam — the shared `WidgetControlAction` vocabulary and `WidgetControlSet` projection, and
`WidgetControlActions → AppIntentSessionActions → SessionCoordinator → TimerEngine` — never a bespoke
`LiveActivitySessionActions`/`LiveActivityCoordinator`-owned timer. Pinned by
`LiveActivityAppIntentRoutingTests`.

## 10. CloudKit independence

The live-session layer imports no CloudKit and persists nothing. Its content is **ephemeral** and is
never synchronized through SwiftData. It runs fully against the local store; a CloudKit failure can
never affect it or the timer (ADR-072). Pinned by `LiveActivityCloudKitIndependenceTests`.

## 11. Exact remaining work for a future iOS/iPadOS companion target

The platform-neutral core (this milestone) is reused **unchanged**. Only these small, platform-gated
pieces are added in the iOS/iPadOS target:

1. **Attributes conformance** (one file, iOS target):
   ```swift
   import ActivityKit
   struct TimeFrameLiveActivityAttributes: ActivityAttributes {
       typealias ContentState = TimeFrameLiveActivityContent   // ← reused as-is
       let sessionID: UUID; let taskName: String
       let configurationName: String; let sessionStartedAt: Date
   }
   ```
2. **ActivityKit adapter** conforming to `LiveActivityService` (the one file importing ActivityKit in
   the app process): `Activity.request`/`update`/`end`, `ActivityAuthorizationInfo`, mapping
   `LiveActivityDismissal` → `ActivityUIDismissalPolicy`, and `activeSessionIDs()` from
   `Activity.activities`.
3. **Live Activity UI** in the widget extension: `ActivityConfiguration(for:)` with a Lock Screen
   view (reusing the shared `LiveActivityPresentation`) and `DynamicIsland` regions; interactive
   controls via the shared Milestone-15 `Button(intent:)` intents.
4. **Wiring**: add the coordinator to the app's lifecycle fan-out and `onMeaningfulTransition`, call
   `reconcileOnLaunch()` after recovery, and add a Settings → Live Activity section (the neutral
   `LiveActivityPreferencesStore` and `LiveActivityCoordinator.preferencesDidChange()` already exist).
5. **Info.plist**: `NSSupportsLiveActivities = YES` in the iOS app target.

No change to `TimerEngine`, `SessionCoordinator`, the schema (**V6**), the widget projection format,
or the App Intents seam is required.

## 12. Testing

Deterministic, no-ActivityKit-runtime suites (all via a `FakeLiveActivityService`):

`LiveActivityPresentationTests`, `LiveActivityAttributesTests`, `LiveActivityStateTests`,
`LiveActivityMappingTests`, `LiveActivityLifecycleTests`, `LiveActivityStartTests`,
`LiveActivityUpdateTests`, `LiveActivityPauseResumeTests`, `LiveActivitySkipTests`,
`LiveActivityStopTests`, `LiveActivityCompletionTests`, `LiveActivityRecoveryTests`,
`LiveActivityDuplicatePreventionTests`, `LiveActivityFailureIsolationTests`,
`LiveActivityCloudKitIndependenceTests`, `LiveActivityBoundaryInvariantTests`,
`LiveActivityAppIntentRoutingTests`.

Boundary audits confirm the neutral layer imports only Foundation/Observation — no ActivityKit,
WidgetKit, SwiftUI, SwiftData, or CloudKit — and introduces no timer primitive and no engine/
coordinator construction. `import ActivityKit` appears **nowhere** in the codebase (the honest state
on macOS).

## 13. Manual acceptance

**Not applicable / not possible on macOS.** There is no Live Activity to display on a native macOS
target, so a live start/countdown/transition/pause/resume/stop/recovery walkthrough cannot be
performed and is **not** claimed. When an iOS/iPadOS companion target exists (§11), manual acceptance
should verify: activity appears on start; countdown advances; phase transitions; pause/resume/skip/
stop; completion winds it down; relaunch leaves exactly one activity for the recovered session.

## 14. Known limitations

- **Live Activities are unavailable on native macOS** (Apple platform limitation, proven in §1).
- The core is compiled and tested but **inert in the shipping macOS app** — it is not wired into the
  running app (no fan-out, no Settings surface), so the macOS product is unchanged.
- Real ActivityKit runtime behaviour (system dismissal timing, push updates, Dynamic Island layout)
  is not exercisable here and remains for the companion target.
- The schema stays **V6**; Live Activity state is ephemeral and requires no migration.

> **Milestone 20 regression note.** No Live Activity code changed in M20. Re-verified: `import
> ActivityKit` appears in **exactly three** iOS files (`TimeFrameLiveActivity.swift`,
> `TimeFrameLiveActivityAttributes.swift`, `ActivityKitLiveActivityService.swift`) and nowhere on
> macOS/Core/Shared; the iOS-app coordinator wiring (`handle` fan-out, `onMeaningfulTransition`,
> `reconcileOnLaunch()`) is intact; interactive controls still route through the M15 seam; the M16
> `TimeFrameLiveActivityContent` remains the `ContentState`; duplicate prevention and stale-date
> behaviour are unchanged. Enforced by `ProductionReadinessTests` / `ProductionReadinessM20Tests`. The
> M20 iOS additions (Home Screen widget in the same extension, local notifications) are independent
> read-only/presentation surfaces and never call into the Live Activity. See
> `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.
