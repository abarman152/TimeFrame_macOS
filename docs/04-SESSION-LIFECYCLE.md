# 04 — Session Lifecycle & Persistence

> **Milestone 18 note.** The lifecycle is **unchanged** by M18. Recovery remains **device-local**
> (ADR-063): `fetchRecoverableSession` only restores a session started on *this* device, so the iOS
> companion never takes over a session running on the Mac (or vice versa) and never starts a second
> timer — verified by `TimeFrameiOSTests` on the simulator. `SessionCoordinator` (now in `Core/`) is
> the one control seam shared by both platforms. See ADR-078/079.

> **Milestone 19 note.** The lifecycle is **unchanged** by M19. The device-local running-session policy
> is now also proven under a *merged, synced store*: `CrossDeviceSyncValidationTests` shows a running
> session written by Device A is visible to Device B but never recovered, mutated, or duplicated there,
> and that completing it on A eventually surfaces as history on B. A CloudKit `.fallback` never blocks
> any control. See ADR-081 and `docs/28-CLOUDKIT-DEVICE-VALIDATION.md` §7–9.

How a Time Frame session is persisted from creation to a terminal state, how it
is recovered after the app is unavailable, and how the timer engine, the
coordinator, and SwiftData divide the work. Milestone 2. Matches the
implementation in `Timer/SessionCoordinator.swift` and
`Services/Persistence/`.

---

## 1. The shape of the system

```
                 SwiftUI (ContentView)
                        │  intents
                        ▼
                 SessionCoordinator ──────────────┐
                 (@MainActor)                      │ reads pure state,
                  /            \                    │ hands plain values
                 ▼              ▼                   ▼
          TimerEngine       ConfigurationRepository / SessionRepository
             │  (no SwiftData)             │  (@MainActor)
             ▼                             ▼
          Clock (TimeProviding)         SwiftData ModelContext → store
```

The engine stays persistence-agnostic (ADR-012). The coordinator is the only
component that reads the engine and writes the store, and it does so through the
repositories (ADR-011).

## 2. Session states (`SessionStatus`)

Distinct from the engine's `TimerState` (ADR-012), the persisted lifecycle is:

| Status | Meaning |
|---|---|
| `planned` | Created but not started (engine `idle`). |
| `running` | Active, current interval counting down. |
| `paused` | Active, current interval frozen. |
| `completed` | Every interval finished normally. Terminal. |
| `cancelled` | User stopped it before the plan finished. Terminal. |
| `interrupted` | Could not be safely recovered (crash / inconsistent data). Terminal. |

```
Created ──► planned ──► running ⇄ paused
                          │  │        │
                          │  └────────┴──► completed
                          │  (all intervals done)
                          ├──────────────► cancelled     (user stop)
                          └──────────────► interrupted    (unsafe recovery)
```

Only these transitions occur; invalid ones are impossible because the engine
gates its own transitions and the coordinator mirrors the result.

## 3. Interval states (`IntervalStatus`)

Each `SessionInterval` carries its own status, richer than a bare `isCompleted`:

| Status | Meaning |
|---|---|
| `pending` | Planned, not yet started. |
| `running` | Currently counting down. |
| `paused` | Started, currently frozen. |
| `completed` | Ran to its planned end. |
| `skipped` | Ended early by the user. |
| `cancelled` | In progress when the whole session stopped. |

`skipped`/`cancelled` intervals are **never deleted** — they are history for
future statistics.

## 4. Timestamp authority (ADR-013)

The engine is authoritative for *time*; persistence records the *timeline*:

- A **running** interval stores `startedAt` and `targetEndAt`. Remaining is
  always `targetEnd − now`, never a stored countdown.
- A **paused** interval stores `remainingAtPause` — the single legitimate stored
  "remaining", because a frozen interval has no running target end to derive
  from. `targetEndAt` is `nil` while paused.
- The session stores `startedAt`, `pausedAt`, `endedAt`.

`targetEndAt` is persisted rather than recomputed from `startedAt +
plannedDuration` because a pause/resume re-anchors the end.

## 5. Persistence lifecycle (what is written, and when)

Every meaningful transition is mirrored in **one save** via
`SessionRepository.applySync` (interval rows matched by `order`, updated in
place):

| Action | Engine effect | Persisted |
|---|---|---|
| **Start** | load plan, `start()` | session `running` + full interval plan (all `pending`), interval 0 → `running` with `startedAt`/`targetEndAt` |
| **Pause** | `pause()` | session `paused` + `pausedAt`; current interval `paused` + `remainingAtPause` |
| **Resume** | `resume()` | session `running`, `pausedAt` cleared; current interval `running` + new `targetEndAt` |
| **Auto transition** (tick) | `synchronize()` | finished interval `completed` (+`endedAt`); next interval `running`; session `currentIntervalIndex` advanced |
| **Skip** | `skip()` | skipped interval `skipped` (+`endedAt`); next interval `running` |
| **Restart** | `restart()` | current interval re-anchored **in place** (no new row — ADR-011) |
| **Stop** | `stop()` | session `cancelled` + `endedAt`; in-progress interval `cancelled`; completed intervals preserved |
| **Complete** | plan elapses | session `completed` + `endedAt`; all intervals `completed` |

The sub-second heartbeat only writes when the `(currentIndex, state)` signature
changes, so a running countdown does not thrash the store.

### 5a. Lifecycle-event seam (Milestone 6)

`SessionCoordinator` also exposes an optional `onLifecycleEvent` closure and emits a
pure `SessionLifecycleEvent` (`started`/`paused`/`resumed`/`skipped`/`stopped`/
`completed`) at each **meaningful transition only** — never on a heartbeat tick. Each
event carries the actual transition time and the engine's projected completion time.
This is the integration-agnostic seam the Calendar (ADR-035) **and** Notification
(ADR-038) integrations subscribe to: the coordinator emits *after* the store is
reconciled and imports neither EventKit nor UserNotifications, so an observer runs on
already-durable values and can never affect the timer. The app fans one event out to
both coordinators; they observe independently and never call each other (§63). For
integrations that must also (re)synchronize outside of an event — e.g. the Notification
layer after relaunch recovery or when re-enabled mid-run — `SessionCoordinator` exposes a
read-only `currentLifecycleContext()` (ADR-043). See `docs/15-CALENDAR-INTEGRATION.md`
and `docs/16-NOTIFICATIONS.md`.

The Milestone 8 **menu bar** is a third observer of the same authoritative state, but it
observes the coordinator/engine **directly via Swift Observation** (its
`MenuBarPresentationState` projection reads engine properties) rather than the event seam —
so it repaints immediately on any change without adding per-tick lifecycle events. It still
routes every control back through `SessionCoordinator` (ADR-045/047). See
`docs/17-MENU-BAR.md`.

The Milestone 10 **statistics** layer is **not** a lifecycle participant at all: it neither
observes the event seam nor the live engine. It reads the **persisted** `FocusSession`/
`SessionInterval` history *after the fact* and derives read-only aggregates, so it can never
influence a transition, and it interprets terminal statuses (`completed`/`cancelled`/
`interrupted`) exactly as this lifecycle defines them. See `docs/19-STATISTICS.md` (ADR-054).

## 6. App-termination behaviour

Time Frame does not need an explicit "on quit" save: because every transition is
persisted as it happens, the store already reflects the latest running/paused
state (with authoritative timestamps) at any instant the app might be killed.

## 7. App-relaunch recovery (ADR-014)

On launch (`time_frameApp.init` → `coordinator.recover()`):

1. Fetch the single recoverable session (`running`/`paused`). If several exist,
   keep the newest and mark the rest `interrupted`.
2. Rebuild the `IntervalPlan` **from the persisted intervals** (not the
   configuration, which may have changed or been deleted).
3. Reconstruct completed-interval history from terminal interval rows.
4. Build a `TimerEngineSnapshot`:
   - **running** → `startedAt` + `targetEndAt` anchors;
   - **paused** → `remainingAtPause`.
5. `engine.load(plan)` then `engine.restore(from: snapshot)`.
6. For a running session, `engine.synchronize()` fast-forwards through every
   interval whose planned end passed while away.
7. Reconcile the store with the resulting engine state, and resume the heartbeat
   if still running.

**Outcomes:** a running session still within its plan **resumes running**; a
session whose whole plan elapsed becomes **completed**; a paused session is
restored **paused** with its remaining intact; an inconsistent session becomes
**interrupted**. Intervals are updated in place, so recovery never creates
duplicate sessions or intervals.

## 8. Sleep / wake

```
running → Mac sleeps → time passes → Mac wakes → synchronize() → reconcile
```

Handled by the same timestamp-authoritative path as recovery. A single
`synchronize()` advances through *all* intervals that elapsed during sleep (it
anchors each interval to the previous one's planned end, so no drift and no
per-second subtraction). An `NSWorkspace.didWakeNotification` observer makes the
catch-up immediate; correctness does not depend on the notification.

## 9. Configuration persistence

`ConfigurationRepository` provides create / read / update / delete / duplicate /
set-default plus idempotent first-launch seeding. Validation
(`ConfigurationDraft.validate()`) returns structured errors and never silently
modifies input; limits and the default-flag invariant are described in ADR-015.

## 10. Error handling

The layer never swallows failures. `PersistenceError` (`saveFailed`,
`fetchFailed`, `deleteFailed`, `invalidConfiguration`, `missingConfiguration`,
`corruptedSession`, `recoveryFailed`) is thrown so callers and tests can observe
exactly what happened; the UI can map these to friendly messages later.
Diagnostics use Apple's unified logging (`os.Logger`, `AppLog`) with identifiers
and counts only — **never** user content such as task names.

## 11. Concurrency & lifetime

Everything here is `@MainActor` and operates on the main `ModelContext`; SwiftData
model instances and contexts never cross an actor boundary. Tests keep the
`ModelContainer` alive for the whole test (a `ModelContext` does not retain its
container).

**App Intents (Milestone 12).** Shortcuts/Siri commands are a control surface like the menu bar
and notification actions: they call the *same* `SessionCoordinator` lifecycle operations
(`startSession`/`startPlan`/`pause`/`resume`/`skip`/`restart`/`stop`) via the one
`AppIntentSessionActions` helper, so a session started, paused, or stopped by voice follows the
identical persistence/recovery path and preserves history (Stop is never a delete). See
`docs/21-APP-INTENTS.md` (ADR-056).

**Interactive widget controls (Milestone 15).** The widget's `Button(intent:)` controls are another
control surface over the *same* lifecycle operations: WidgetKit runs each thin control intent in the
**app process**, where an app-registered `WidgetControlActions` router delegates to the **same**
`AppIntentSessionActions` seam — so a Pause/Resume/Skip/Restart/Stop/Start pressed on the widget
follows the identical persistence/recovery path (Stop preserves history). A stale widget action against
a session that is no longer active fails safely (`noActiveSession`) and **never resurrects** it, and
`Start` after a completed/stopped run begins a genuinely new session. See
`docs/24-INTERACTIVE-WIDGETS.md` (ADR-069/071).

**Milestone 13 — device-local recovery under sync.** With CloudKit, a running/paused
`FocusSession` may sync to another device. Timer execution stays **device-local**:
`fetchRecoverableSession` only returns sessions started on *this* device (via the additive
optional `FocusSession.originatingDeviceID`; a `nil` origin counts as local for back-compat), so
Device B's launch-time `recover()` never restores — or even mutates — a session that Device A is
running. All other recovery rules are unchanged (ADR-014/063). See `docs/22-ICLOUD-CLOUDKIT.md`.

**Milestone 16 — Live Activity observation (platform-neutral; inert on macOS).** The
`LiveActivityCoordinator` observes the same lifecycle fan-out (start→activity, transitions→update,
stop/complete→end) and, on launch, `reconcileOnLaunch()` converges to **exactly one** activity for a
recovered running/paused session and **none** when idle/terminal — keyed by `FocusSession.id`, so
relaunch/crash/sleep-wake/repeated callbacks never leave duplicates (ADR-073). It honours the
device-origin policy: only this device's recovered `activeSession` is ever surfaced. This is built and
tested, but ActivityKit is unavailable on native macOS, so the observer is not wired into the running
macOS app (ADR-076). See `docs/25-LIVE-ACTIVITIES.md`.

**Milestone 17 — test-host hermeticity + consolidated isolation.** The lifecycle is unchanged. M17
proves two guarantees: (1) under the XCTest host, launch skips `recover()`/`seedDefaultIfNeeded()`,
CloudKit, App-Group writes, and intent registration (detection extracted to the pure
`TestHostEnvironment`), so the suite can never recover or mutate the developer's real running session —
the regression that previously caused a real-store hang; and (2) with Calendar, Notifications, and the
Widget projection **all failing at once** (plus a throwing lifecycle observer), a full session still runs
start → completion and Stop still preserves history — the coordinator emits after the store is reconciled
and depends on no observer's success (ADR-035/042/055/077). See `docs/26-PRODUCTION-READINESS.md`.

> **Milestone 20 note.** iOS **local notifications** subscribe to this **same** `SessionLifecycleEvent`
> seam (start/pause/resume/skip/stop/completion) via the neutral `NotificationCoordinator` — now in
> `Core/Services/Notifications/`, shared by macOS and iOS. They schedule from the engine's frozen
> interval-end anchors (never a second clock), reconcile idempotently on launch, route actions back
> through `SessionCoordinator`, and are fully failure-isolated: a notification failure can never stop
> or corrupt the timer (ADR-083/086). See `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.
