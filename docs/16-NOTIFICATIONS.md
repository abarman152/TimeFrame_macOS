# 16 — macOS Notifications (Milestone 7)

Time Frame delivers native macOS local notifications for interval transitions and
session completion. Like Calendar, the integration is **optional** and **isolated**:
notifications are a *representation* of the authoritative timer, never the source of
truth, and a notification failure can never stop or corrupt a timer.

```
                              TIME FRAME
                                  │
                          SessionCoordinator
                                  │
                          SessionLifecycleEvent
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
              TimerEngine  CalendarCoordinator  NotificationCoordinator
                    │             │             │
                    │         EventKit     UserNotifications
                    │             │             │
                    ▼             ▼             ▼
                 History   Apple Calendar  macOS Notifications
```

The timer, Calendar, and Notifications are three independent observers of one pure
seam. `SessionCoordinator` emits pure `SessionLifecycleEvent`s; `CalendarCoordinator`
and `NotificationCoordinator` each subscribe. Neither integration imports the timer's
frameworks, neither can affect the timer, and the two integrations never call each
other (§8/§63).

---

## 1. Architecture & isolation (ADR-038)

```
SwiftUI (NotificationSettingsSection)
   ↓
NotificationCoordinator          @MainActor @Observable — orchestration, never throws to the timer
   ↓
NotificationScheduling (protocol) pure value types only
   ├── UserNotificationService    the ONLY file importing UserNotifications
   └── FakeNotificationService    deterministic tests, no real notification center
   ↓
UNUserNotificationCenter → macOS
```

`import UserNotifications` appears in **exactly one file**: `UserNotificationService`.
Everything else — the coordinator, the content generator, the scheduler/builder, the
preferences, the value types, and every test — speaks only pure Swift value types. No
`UNNotificationRequest`, `UNMutableNotificationContent`, `UNNotificationResponse`,
`UNNotificationSettings`, or `UNNotificationCategory` ever escapes the adapter (§9).

### Source layout (`Services/Notifications/`)

**Pure domain (no UserNotifications):**
- `NotificationCategory` — semantic transition kinds (focus/short-break/long-break
  started, session completed).
- `NotificationAction` / `ReceivedNotificationAction` — controls and a parsed response.
- `NotificationSound`, `NotificationAuthorizationStatus`, `NotificationIntegrationError`.
- `NotificationPreferences` (+ `NotificationPreferencesStore`) — UserDefaults-backed
  preferences (ADR-044).
- `NotificationDescriptor` / `NotificationContent` / `NotificationIdentifier` — the pure
  event to schedule and its stable identity.
- `NotificationContentGenerator` — deterministic `Announcement → NotificationContent`.
- `NotificationSessionSnapshot` — a `Sendable` projection of a running `FocusSession`.
- `NotificationScheduleBuilder` — `snapshot + preferences → [NotificationDescriptor]`.
- `NotificationActionResolver` — the pure §40 safety rules.

**Service / orchestration:**
- `NotificationScheduling` (protocol) + `NotificationCategoryDescriptor`.
- `UserNotificationService` — the sole UserNotifications adapter and the notification
  center delegate.
- `NotificationCoordinator` — subscribes to lifecycle events; imports no
  UserNotifications and no SwiftData.

**UI:** `Views/Notifications/NotificationSettingsSection.swift`.

---

## 2. The authoritative timer is never displaced (ADR-039)

The `TimerEngine` owns the current phase, interval, target end, remaining time, and all
transitions (derived from timestamps — `docs/03-TIMER-ENGINE.md`). The
`NotificationCoordinator` merely *represents* those transitions as scheduled OS
notifications. It never reconstructs timer state from notifications and never runs a
parallel timer. Long breaks, for example, come straight from the engine's plan — the
coordinator never re-derives "every 4 sessions" itself (§73).

The engine required **no** change for this milestone. `SessionCoordinator` gained a
single read-only accessor, `currentLifecycleContext()`, used to reschedule after
relaunch recovery and when the user re-enables notifications mid-run (ADR-043); it
imports nothing from any integration.

---

## 3. Authorization (macOS 27)

Time Frame **never** requests notification permission on launch (§70). Permission is
requested contextually, only when the user turns notifications on (or taps *Enable
Notifications*) in Settings.

The adapter maps `UNAuthorizationStatus` to a pure `NotificationAuthorizationStatus`:

| Pure status | Meaning | Schedules? |
|---|---|---|
| `notDetermined` | Not asked yet | No (offers *Enable*) |
| `authorized` | Full alerting permission | Yes |
| `provisional` | Quiet delivery to the list | Yes |
| `denied` | Declined / unavailable | No (offers *Open System Settings*) |

`ephemeral` (an App Clip concept) does not apply to a Mac app and is not modelled (§19).
Requesting uses `requestAuthorization(options: [.alert, .sound, .badge])`; a request
after a decision does not re-prompt. After a denial the UI offers **Open System
Settings**, which opens the macOS notifications privacy pane.

---

## 4. Notification types & content

Content is generated purely by `NotificationContentGenerator` and is deliberately
concise (§13) — a title, the task as subtitle, and one body line. Titles are never
empty; a session with no task falls back to "Time Frame" (§14).

| Type | Title | Subtitle | Body |
|---|---|---|---|
| Focus started | `Time to focus` | task (or `Time Frame`) | `25 min · Classic Pomodoro` |
| Short break | `Short break` | task (if any) | `Focus session complete. Take 5 min to recharge.` |
| Long break | `Long break` | task (if any) | `You've completed 4 focus sessions. Take a longer break.` |
| Session complete | `Session complete` | task (or `Time Frame`) | `4 focus sessions completed.` |

The configuration name is appended to the focus body only when present (§15). Internal
state (UUIDs, `TimerState`, target dates) is never shown.

### Plan complete — deferred with rationale

A distinct "Plan complete" notification is **not** implemented. By design (ADR-028/029)
a running/historical session carries **no** identity of the `SessionPlan` it may have
been started from — that independence is what lets a plan be edited or deleted without
touching a live session. There is therefore no clean lifecycle signal that a completion
was "a plan," so plan completion is folded into the single **Session complete**
notification. Reviving a distinct message would require re-coupling the session to its
plan, which the architecture deliberately avoids.

---

## 5. Scheduling strategy (ADR-040)

Notifications are scheduled for **meaningful interval transitions only — never on a
timer tick** (§53/§71). Concretely, `NotificationScheduleBuilder` lays out **one
notification per upcoming interval-start boundary**, anchored to the engine's
authoritative timeline: the notification that fires when focus ends announces the break,
and the one that fires when a break ends announces the next focus (§12/§21).

### Why the whole remaining timeline, not just the next one

The existing lifecycle seam emits on start/pause/resume/skip/stop/complete but **not**
on an automatic focus→break advance. Notifications must still fire when the app is
backgrounded or fully closed (§22). So on each scheduling trigger the coordinator
schedules **every** upcoming interval-start boundary for the session at once, then
cancels and reschedules the whole set on the next trigger. This is:

- **Correct when closed** — the OS delivers each transition without the app running.
- **Never per-tick** — the set changes only on a real transition.
- **Bounded** — one notification per remaining interval (a handful), so the queue stays
  small and predictable (§72).

For a single-focus session (`[Focus, Short Break]`) this yields **exactly one** upcoming
transition request — the break — matching §55. For a full 4-session plan (8 intervals) it
yields 7.

Each request has a stable, namespaced identifier (§34):
`com.timeframe.notification.<sessionID>.<intervalIndex>.transition`. Identity is
session + interval + type, never the title — so requests can be replaced, cancelled, and
de-duplicated.

### Per-transition behaviour

| Lifecycle event | Notification action |
|---|---|
| **started** | cancel the session's pending, schedule all upcoming transitions |
| **paused** | cancel the session's pending (none should fire while frozen — §25) |
| **resumed** | cancel + reschedule from the authoritative new remaining time (§26) |
| **skipped** | cancel + reschedule from the new current interval (§28) |
| **stopped** | cancel the session's pending (nothing should fire — §29) |
| **completed** | cancel the session's pending, deliver the completion notification |

All cancellation is **prefix-scoped to Time Frame** (and, for a transition, to the one
session). `removeAllPendingNotificationRequests()` is never called, so another app's
notifications are never touched (§35).

### Completion (ADR-041)

The completion notification is **not** pre-scheduled. It is delivered immediately from
the `.completed` lifecycle event, with the stable id
`com.timeframe.notification.<sessionID>.completion` and a coordinator guard so it can
never be duplicated (§30). A consequence: if the app is fully terminated at the exact
instant of natural completion, the completion banner is not delivered at that instant —
the final *transition* notification (e.g. the last break starting) still fires from its
schedule, and no stale "finished" banner is shown on next launch. This matches the §32
preference to recover state and avoid outdated catch-up notifications.

---

## 6. Pause / resume / skip / stop / restart

Every timer control routes through `SessionCoordinator`, whose emitted lifecycle event
drives the table above. Because a resume re-anchors the interval end, the rescheduled
notification uses the engine's **new** target (§26) — the old one is cancelled first, so
a stale transition can never fire.

---

## 7. Recovery, sleep/wake (§31/§32/§33)

The `TimerEngine` already reconstructs authoritative state on relaunch and on wake from
timestamps. The notification layer reconciles against that state:

1. On relaunch, after `coordinator.recover()`, the app calls
   `NotificationCoordinator.reconcileActiveSession(_:isRunning:)`.
2. That **cancels stale** Time Frame notifications, then **schedules the next future
   transitions** for a still-running session — using the recovered current index, so no
   already-elapsed boundary is ever scheduled and no outdated notification fires (§32).
3. A completed or non-running session schedules nothing and is never resurrected.

Sleep/wake needs no special handling: the engine's `synchronize()` reconciles the
timeline, and the pre-scheduled OS notifications fire at their absolute times regardless
of sleep. There is no second timer here.

---

## 8. Actions (§36–§40)

Registered categories carry a small set of buttons (§39):

| Category | Buttons | Default tap |
|---|---|---|
| Focus / Short break / Long break started | Pause · Skip | Open Time Frame |
| Session complete | — | Open Time Frame |

A response is parsed by the adapter into a pure `ReceivedNotificationAction`
(`{action, sessionID}`). `NotificationActionResolver` then applies the §40 safety rules
purely:

- **Open** always brings the app forward (`NSApplication.activate`).
- **Pause** only while running; **Resume** only while paused; **Skip/Stop** while active.
- An action for a **different**, **missing**, or **finished** session is ignored and
  logged — never a crash, never a resurrected session.

A resolved control is routed back through `SessionCoordinator` (`pause()`/`resume()`/
`skip()`/`stop()`) — the coordinator never mutates the engine directly (§37). Action
buttons are omitted entirely when the "Action buttons" preference is off.

---

## 9. Sound & interruption level (§41/§42)

Sound is a simple **Default / off** preference; no custom audio assets. Notifications use
the standard `.active` interruption level — ordinary productivity alerts, never
`.timeSensitive` or `.critical` (which would bypass Focus / Do Not Disturb).

---

## 10. Preferences (ADR-044)

`NotificationPreferences` is a pure `Codable`/`Sendable` value with only primitive
fields, persisted in `UserDefaults` via `NotificationPreferencesStore` — **no SwiftData
schema change** (schema stays V5; §78/§79). Fields: `isEnabled` (master), `focusStarted`,
`shortBreakStarted`, `longBreakStarted`, `sessionCompleted`, `soundEnabled`,
`actionsEnabled`. No UserNotifications object is ever persisted (§46). Turning the master
switch off cancels every pending Time Frame notification and schedules nothing further;
the timer is untouched (§17).

---

## 11. Failure isolation (ADR-042)

This is the milestone's central guarantee. Every scheduler call is deferred onto a fresh
main-actor task (so the timer path has fully returned) and wrapped so **no failure ever
escapes toward the engine** (§50). A scheduling failure, a denied permission, a
cancellation failure, or an action for a vanished session becomes a logged, non-blocking
status — the running session starts, runs, pauses, resumes, skips, stops, and completes
exactly as if notifications did not exist. Verified by
`NotificationTimerIndependenceTests`. Notification failure also never alters History,
`FocusSession`/`SessionInterval` status, or persisted timing (§77).

---

## 12. Logging (§51)

`AppLog.notifications` records authorization changes, scheduling, replacement,
cancellation counts, received actions, and failures — **identifiers, counts, and
statuses only**, never notification titles/bodies or task names.

---

## 13. Testing (§52–§64)

All tests use `FakeNotificationService` — no real notification center, no permission
prompt, fully deterministic. Coverage:

- **Content** (`NotificationContentTests`) — every type's title/subtitle/body, no empty
  titles, singular/plural.
- **Scheduling** (`NotificationScheduleBuilderTests`) — one request per boundary,
  cumulative fire dates, preference gating, stable identifiers, completion descriptor.
- **Actions** (`NotificationActionResolverTests`) — the full §40 safety matrix.
- **Coordinator** (`NotificationCoordinatorTests`) — authorization, start schedules the
  transition, no per-tick scheduling, pause cancels, resume/skip reschedule, stop cancels
  all, completion delivers exactly one (no duplicate), master toggle cancels, actions
  route through `SessionCoordinator`.
- **Independence / failure isolation** (`NotificationTimerIndependenceTests`) — the timer
  starts/runs/completes under scheduling failure and permission denial; Calendar and
  Notifications never affect each other (§63).
- **Recovery** (`NotificationRecoveryTests`) — reschedules the next transition after
  relaunch, cancels stale requests, never resurrects a completed session.

---

## 14. Manual acceptance

See the milestone's manual acceptance checklist. In an automated/headless environment the
system permission dialog and banner delivery cannot be exercised, so manual verification
is **PARTIAL**: the build, the full automated suite, and the isolation invariants pass;
live banner delivery must be confirmed on a real login session.

---

## 15. Future improvements (deferred)

- A distinct **Plan complete** message (requires re-associating a live session with its
  plan — see §4).
- A **Resume** button on a delivered notification while paused (the app does not deliver a
  "paused" notification, so the button has no surface today).
- Optional **catch-up** completion on relaunch, if product policy later wants it (§32).
- Additional sound choices, and a subtle notification-status indicator on the Timer (§68).
