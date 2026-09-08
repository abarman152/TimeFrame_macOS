# 15 — Apple Calendar / EventKit Integration (Milestone 6)

Time Frame can turn focus plans and live sessions into Apple Calendar events. The
integration is **optional** and **isolated**: Apple Calendar is a *representation*
of Time Frame activity, never the source of truth, and a Calendar failure can never
stop or corrupt a timer.

```
                       TIME FRAME
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
       EXECUTION CORE              CALENDAR INTEGRATION
             │                           │
       SessionCoordinator         CalendarCoordinator
             │                           │
        TimerEngine             CalendarEventGenerator
             │                           │
        FocusSession             EventKitCalendarService
             │                           │
          History                  Apple Calendar
```

The two systems meet at exactly one seam: `SessionCoordinator` emits pure
`SessionLifecycleEvent`s; `CalendarCoordinator` subscribes. The coordinator imports
no EventKit, and the engine depends on neither.

> **Milestone 7:** the **Notification** integration (`docs/16-NOTIFICATIONS.md`) follows
> the identical pattern and subscribes to the **same** seam. The app fans one lifecycle
> event out to both coordinators; Calendar and Notifications are fully independent and
> never call each other (§63). Everything below about isolation and failure handling
> applies equally to both.

---

## 1. Architecture & isolation (ADR-032)

```
SwiftUI (Calendar views)
   ↓
CalendarCoordinator            @MainActor @Observable — orchestration, never throws to the timer
   ↓
CalendarService (protocol)     pure value types only
   ├── EventKitCalendarService the ONLY file importing EventKit
   └── FakeCalendarService     deterministic tests, no real Calendar
   ↓
CalendarEventGenerator (pure)  CalendarPlanContext → [CalendarEventDraft]
```

- **`EventKitCalendarService` is the only place that imports EventKit.** No
  `EKEvent`, `EKCalendar`, or `EKEventStore` ever escapes it. Everything else trades
  in pure values: `CalendarEventDraft`, `CalendarEventReference`,
  `CalendarDescriptor`, `CalendarAuthorizationStatus`, `CalendarIntegrationError`.
- **`TimerEngine`, `PomodoroConfiguration`, `TaskTemplate`, `SessionPlan`, and the
  timer domain types import no EventKit** and know nothing about Calendar.
- **`CalendarEventDraft` is framework-independent** (ADR-033) — the generator and all
  tests run without EventKit.

## 2. The seam: session lifecycle events (ADR-035)

`SessionCoordinator` exposes one optional closure:

```swift
var onLifecycleEvent: ((SessionLifecycleEvent) -> Void)?
```

It emits `.started / .paused / .resumed / .skipped / .stopped / .completed` at
*meaningful transitions only* — never on a heartbeat tick (§53). Each event carries
a `SessionLifecycleContext` (the `FocusSession`, the actual transition time, and the
engine's projected completion time). The coordinator emits *after* the store is
already reconciled, so the observer runs on values that are already durable and can
never affect the timer.

`CalendarCoordinator.handle(_:)` reads the model on the main actor, extracts a pure
payload, and **defers** all calendar work onto a fresh main-actor `Task`. So the
timer control method has fully returned before any EventKit call runs, and every
failure is caught, logged, and turned into a non-blocking status.

**A Calendar failure never throws toward the engine.** This is the central rule of
Milestone 6, and it is tested directly (`CalendarTimerIndependenceTests`).

## 3. Authorization (macOS 27 EventKit)

EventKit (macOS 14+/macOS 27) splits access into *full* and *write-only*. Time Frame
requests **full access** (`requestFullAccessToEvents()`) because updating and
deleting an event requires reading it back by identifier; write-only is therefore
treated as *insufficient*.

`CalendarAuthorizationStatus` mirrors the states the app reasons about:

| Status | Meaning | Remedy |
|---|---|---|
| `notDetermined` | never asked | request in context |
| `restricted` | blocked by policy | none (cannot self-grant) |
| `denied` | user declined | Open System Settings |
| `writeOnly` | can create but not read back — insufficient | Open System Settings |
| `fullAccess` | read + write — the state Time Frame needs | — |

- Permission is **only requested in context** (enabling the toggle, or Add to
  Calendar) — never on first launch (§47).
- A denial is not re-prompted; the UI routes to System Settings via
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars` (§80).

## 4. Privacy configuration

The app is sandboxed. Two things are required and are configured in the project:

- **Entitlement** `com.apple.security.personal-information.calendars` (in
  `time_frame/time_frame.entitlements`, alongside `com.apple.security.app-sandbox`).
- **Usage description** `NSCalendarsFullAccessUsageDescription`, supplied via the
  build setting `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription` (the target
  uses `GENERATE_INFOPLIST_FILE = YES`, so there is no hand-written Info.plist).

Both are verified present in the signed `.app` (Info.plist key + codesign
entitlements).

## 5. Calendar selection (§19/§20)

- Only **writable** calendars are offered (`allowsContentModifications`).
- The chosen default is stored by **stable `calendarIdentifier`**, never by title
  (two calendars can share a name).
- If a stored identifier no longer resolves, it is cleared and the user re-chooses;
  a create against a missing calendar reports `.calendarUnavailable` rather than
  silently picking another (§20/§55).

## 6. Event generation, styles, and notes

`CalendarEventGenerator` (pure, deterministic) turns a `CalendarPlanContext` into
`[CalendarEventDraft]` at one of two styles (§12):

- **`singlePlan`** — one event spanning the whole plan/session (e.g. 10:00–11:55
  "Research Quantum IDS").
- **`perInterval`** — one back-to-back event per interval ("Focus — …", "Short
  Break", "Long Break").

`start + total planned duration = end` holds exactly (tested). Notes carry useful,
non-sensitive metadata (plan, task, focus count, total, configuration name(s), and a
"Created by Time Frame" footer). Multiple configurations are represented (§26/§67).

## 7. Two flows

### A. Manual: plan → Calendar (§29/§50)
`Plan Detail → Add to Calendar` opens a **preview sheet** showing exactly what will
be created, with a start-time picker, calendar picker, style picker, and (for a
single event) an editable title. It honours the user's chosen **event style** (single
or per-interval). The association is stored keyed by the plan id.

### B. Live: session start → Calendar (§30, ADR-036)
When integration is enabled and the trigger includes session start, starting a timer
creates **one whole-session event** anchored to the **actual** start time — never a
fabricated timestamp (§31). A live session always uses a *single* event so that
pause/resume/stop stay correct and cheap to keep in sync; the per-interval style
applies to the manual plan flow. This is a deliberate, documented simplification
(ADR-036).

## 8. Live-session lifecycle behaviour

| Transition | Calendar effect |
|---|---|
| **Start** | create one event `[actualStart, projectedEnd]` (if enabled & trigger allows) |
| **Pause / Resume / Skip** | adjust the event's **end** to the new projected completion |
| **Stop** | adjust the event's end to the **actual stop time**; the event is **kept**, never deleted (§35) |
| **Completion** | adjust the event's end to the actual completion time (once) |
| **Tick** (no transition) | **nothing** — the calendar is never written on a tick (§53) |
| **Recovery (relaunch)** | the persisted association survives; recovery proceeds normally and never depends on the event existing (§73) |

The timer remains authoritative for time; the calendar event is only ever a
representation derived from the engine's own timestamps (ADR-035).

## 9. Event ownership & external edits (ADR-036, §37/§38)

A clear, minimal ownership model:

- **Time Frame owns:** the association, and — for a live session — the event's
  **end time** as the timer progresses.
- **The user owns:** the calendar, the title, the notes (after creation), and the
  location. Live sync **only ever changes the end date** (`adjustEventEnd`), so a
  user's manual edits to a Time Frame event are never overwritten.

If the user deletes the event in Calendar, the next transition detects
`.eventNotFound`, forgets the association, and does **not** silently recreate a
duplicate (§55/§79).

## 10. Event identity & duplicate prevention (ADR-034, §24/§25)

Identity is a stable **Time Frame id**, never the title:

- A live session's events are keyed by the `FocusSession` id.
- A manually added plan's events are keyed by the `SessionPlan` id.

Because a new run is a new `FocusSession`, Start → Stop → Start yields distinct
events for distinct runs (each with its own actual time) — but a single run never
produces duplicates. Re-adding a plan **replaces** its prior events rather than
accumulating them.

## 11. Persistence (ADR-037)

Calendar **settings** and **event associations** live in `UserDefaults`, not
SwiftData — they are lightweight, non-relational preferences/metadata, so no schema
change and no migration were needed (the schema stays V5). This keeps the core timer
models pristine (no EventKit/calendar fields) and avoids the store-rebuild risk of a
schema bump.

- `CalendarPreferencesStore` → `CalendarSettings` (enabled, default calendar id,
  event style, creation trigger). Defaults: **off**, single-event, both triggers.
- `CalendarEventRecordStore` → `[CalendarEventRecord]` keyed by owner id
  (`ownerType` plan/session, `ownerID`, `style`, `references`, timestamps).

No `EKEvent`/`EKCalendar` is ever persisted — only identifiers
(`CalendarEventReference`).

## 12. Plan operations & Calendar (§39/§56/§57)

- **Deleting a plan never deletes its calendar events** (Calendar data belongs to the
  user). The orphaned association is harmless UserDefaults metadata.
- **Duplicating a plan does not copy the association** — the duplicate has a new id,
  so it simply has no record until the user adds it.
- **History is independent** of Calendar entirely; deleting a calendar event never
  touches a `FocusSession`, `SessionInterval`, or History (§58/§74).

## 13. Errors (§40)

`CalendarIntegrationError` (a `LocalizedError`) maps every failure to a friendly,
non-technical message: `notAuthorized`, `accessRestricted`, `eventStoreUnavailable`,
`calendarUnavailable`, `noWritableCalendars`, `eventNotFound`, `saveFailed`,
`updateFailed`, `deleteFailed`, `invalidCalendar`. Raw EventKit errors never reach
the UI. Failures surface as a quiet `CalendarSyncStatusView` and, for explicit user
actions, an alert — the running timer is never interrupted.

## 14. Logging (§41)

`AppLog.calendar` logs authorization changes, event create/update/delete, and
failures — **identifiers, counts, and statuses only**, never event notes or task
names.

## 15. Testing (no real Calendar — §43/§75)

All calendar tests use `FakeCalendarService` (configurable authorization, calendars,
and per-operation failures) and scratch `UserDefaults`:

- `CalendarEventGeneratorTests` — single vs per-interval, durations, titles, notes,
  multiple configurations, trailing-break handling, `start + total = end`.
- `CalendarPersistenceTests` — settings and record round-trips.
- `CalendarCoordinatorTests` — authorization branches, calendar selection, create,
  per-interval count, duplicate prevention, explicit deletion, failure isolation.
- `CalendarTimerIndependenceTests` — the timer starts/runs/pauses/stops when create
  or update fails or permission is denied; event created on start with the actual
  time; no per-tick writes; stop keeps the event; completion adjusts once; external
  deletion is forgotten, not recreated.

## 16. Future improvements (deferred)

- Per-interval events for a *live* session (with mid-interval pause/skip
  reconciliation).
- A user-chosen scheduled start time persisted on a plan.
- Reminders/alerts on calendar events (Notifications milestone owns user-facing
  alerts).
- Two-way awareness of external edits beyond "event missing".

Notifications, Menu Bar, Liquid Glass, Widgets, App Intents, Siri, iCloud/CloudKit,
and advanced Statistics remain out of scope for Milestone 6.
