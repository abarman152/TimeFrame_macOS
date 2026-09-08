# 02 — Data Model

> **Current schema: V7** (Milestone 28) — the same six `@Model` types, with three added
> attributes on each of `TaskTemplate` and `SessionPlan` for the Quick Start icon and pin. See the
> Milestone 28 section at the end of this document.

> **Milestone 18 note.** The data model was **unchanged** at that time — schema V6, same six `@Model`
> types. The `Models/` and `Services/Persistence/` sources moved into the shared **`Core/`** group so
> the identical models compile into both the macOS app and the iOS companion (one store, one schema).
> Cross-device history/statistics sync through the same SwiftData-native CloudKit mirroring once a paid
> team enables it; recovery stays device-local (ADR-063). See ADR-078/079.

The SwiftData domain model for Time Frame. Four `@Model` types plus the domain
enums they store. Implemented in `Models/` and `Services/Persistence/` (relocated to
`Core/Models/` and `Core/Services/Persistence/` in Milestone 18).

---

## 1. Entity overview

```
                       TaskTemplate
                            │ (to-one, optional; nullify)
                            ▼
PomodoroConfiguration 1 ──< (nullify)   FocusSession 1 ──< (cascade)  SessionInterval
        ▲                                     │
        └─────────── referenced by ───────────┘  (to-one, optional)
```

- A **`FocusSession` references a `PomodoroConfiguration`** (it does not copy its
  values).
- A **`FocusSession` owns its `SessionInterval`s** (cascade delete).
- A **`TaskTemplate` references a `PomodoroConfiguration`** (a reusable
  starting-point definition; Milestone 4). It is **not** a session and holds no
  timeline data.
- Deleting a configuration **nullifies** the reference on its sessions *and its
  templates* but keeps both.

## 2. `PomodoroConfiguration`

Persisted, reusable definition of a Pomodoro rhythm — the single source of truth
for durations and counts.

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | `#Unique`, stable identity |
| `name` | `String` | e.g. "Classic Pomodoro" |
| `focusDuration` | `TimeInterval` | seconds |
| `shortBreakDuration` | `TimeInterval` | seconds |
| `longBreakDuration` | `TimeInterval` | seconds |
| `sessionsBeforeLongBreak` | `Int` | long-break interval |
| `defaultTotalSessions` | `Int` | default number of focus blocks |
| `isDefault` | `Bool` | at most one configuration is the default (ADR-015) |
| `createdAt` | `Date` | |
| `modifiedAt` | `Date` | |
| `focusSessions` | `[FocusSession]` | inverse of `FocusSession.configuration`, delete rule **nullify** |
| `taskTemplates` | `[TaskTemplate]` | inverse of `TaskTemplate.configuration`, delete rule **nullify** (ADR-024) |

- `snapshot: PomodoroConfigurationSnapshot` — produces the immutable value the
  timer engine runs from.
- `static func classic()` — the seeded default (25 / 5 / 15, four sessions,
  long break every fourth).

No Calendar-specific properties are added yet.

## 3. `FocusSession`

A running or completed run of a plan.

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | `#Unique` |
| `taskName` | `String` | may be empty for an ad-hoc run |
| `configuration` | `PomodoroConfiguration?` | to-one reference, optional (survives config deletion) |
| `startedAt` | `Date?` | |
| `pausedAt` | `Date?` | most recent pause (informational) |
| `endedAt` | `Date?` | |
| `currentIntervalIndex` | `Int` | position within `intervals` |
| `status` | `SessionStatus` | persisted lifecycle: planned/running/paused/completed/cancelled/interrupted (Codable enum) |
| `intervals` | `[SessionInterval]` | inverse of `SessionInterval.session`, delete rule **cascade** |

- `orderedIntervals` — `intervals` sorted by `order`.
- `currentInterval` — the interval whose `order == currentIntervalIndex`.
- `isCompleted` — `status == .completed`.

> `status` is a dedicated `SessionStatus`, **not** the engine's `TimerState`
> (ADR-012): it adds `planned` (created, not started) and `interrupted` (could
> not be safely recovered).

## 4. `SessionInterval`

One concrete interval within a session.

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | `#Unique` |
| `phase` | `TimerPhase` | focus / shortBreak / longBreak (Codable enum) |
| `plannedDuration` | `TimeInterval` | seconds |
| `startedAt` | `Date?` | when this interval began running |
| `endedAt` | `Date?` | when it ended |
| `targetEndAt` | `Date?` | authoritative running end (nil unless running) — ADR-013 |
| `remainingAtPause` | `TimeInterval?` | frozen remaining (nil unless paused) — ADR-013 |
| `status` | `IntervalStatus` | pending/running/paused/completed/skipped/cancelled (Codable enum) |
| `order` | `Int` | 0-based position in the plan |
| `configurationName` | `String` | frozen name of the configuration this interval was generated from (empty for breaks; Milestone 5). Lets a multi-configuration plan record which configuration each focus used, keeping History accurate without a live reference (ADR-028). Defaulted so older stores migrate cleanly. |
| `session` | `FocusSession?` | inverse side (no macro here) |

- `init(planned: PlannedInterval)` — builds a persisted interval from an engine
  `PlannedInterval`.
- `isCompleted` / `isTerminal` — convenience over `status`.

> `status` replaces Milestone 1's bare `isCompleted`/`outcome` pair, so history
> distinguishes completed / skipped / cancelled and the in-progress states.
> `skipped`/`cancelled` intervals are kept, never deleted.

## 4a. `TaskTemplate` (Milestone 4)

A reusable, persisted task definition — a *starting point* for future sessions,
not a session and not history. See `docs/13-TASK-TEMPLATES.md`.

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | `#Unique` |
| `name` | `String` | the template's own name (e.g. "Research") |
| `taskName` | `String` | copied into the started `FocusSession` (distinct from `name`) |
| `configuration` | `PomodoroConfiguration?` | to-one reference, optional (survives config deletion) — ADR-022/024 |
| `defaultTotalSessions` | `Int` | per-run seed count (1…24) |
| `isDefault` | `Bool` | at most one default template (ADR-025) |
| `createdAt` / `updatedAt` | `Date` | `updatedAt` bumped on Save |

- `hasConfiguration` / `displayConfigurationName` — convenience over the optional
  reference (the latter yields "Configuration unavailable" when nullified).
- A template never references or is referenced by a `FocusSession`; starting a
  session **copies** the template's values into a `SessionSetupDraft` (ADR-023).

## 4b. `SessionPlan` / `SessionPlanItem` (Milestone 5)

A designed, editable multi-session plan and its ordered intervals — a *planning*
layer, not an execution one. A plan is frozen into a value snapshot at start and run
through the existing engine (ADR-026/028). See `docs/14-SESSION-PLANNER.md`.

**`SessionPlan`**

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | `#Unique` |
| `name` | `String` | the plan's own name (e.g. "Research Deep Work") |
| `taskName` | `String` | copied into the started `FocusSession` |
| `createdAt` / `updatedAt` | `Date` | `updatedAt` bumped on save |
| `items` | `[SessionPlanItem]` | inverse of `SessionPlanItem.plan`, delete rule **cascade** |

Derived: `orderedItems`, `focusCount`, `totalDuration`, `isStartable`, `draft`,
`executionSnapshot`.

**`SessionPlanItem`**

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | `#Unique` |
| `order` | `Int` | explicit 0-based position, normalized on save (ADR-027) |
| `phase` | `TimerPhase` | focus / shortBreak / longBreak — the shared engine enum (ADR-027) |
| `duration` | `TimeInterval` | the item's **own** frozen length (seeded from, independent of, the configuration) |
| `configuration` | `PomodoroConfiguration?` | focus items only; **nullify** inverse on the configuration |
| `configurationName` | `String` | frozen name; shown after a configuration is deleted (empty for breaks) |
| `plan` | `SessionPlan?` | inverse side (no macro here) |

- Configuration lives **per focus item**, not per plan, so a plan may mix
  configurations (ADR-030). There is no `plan.configuration`.
- `TimerPhase` is reused as the item type rather than a parallel enum, so an item
  maps to a `PlannedInterval`/`SessionInterval` with no translation (ADR-027).

## 5. Relationship & delete-rule decisions

- The `@Relationship` macro is placed on **one side only** of each relationship
  (SwiftData creates circular references otherwise):
  - `PomodoroConfiguration.focusSessions` declares `.nullify` +
    `inverse: \FocusSession.configuration`.
  - `PomodoroConfiguration.taskTemplates` declares `.nullify` +
    `inverse: \TaskTemplate.configuration` (ADR-024).
  - `PomodoroConfiguration.planItems` declares `.nullify` +
    `inverse: \SessionPlanItem.configuration` (ADR-029): deleting a configuration
    leaves plans intact but clears the reference, so a plan is shown as incomplete
    rather than deleted.
  - `FocusSession.intervals` declares `.cascade` +
    `inverse: \SessionInterval.session`.
  - `SessionPlan.items` declares `.cascade` +
    `inverse: \SessionPlanItem.plan`: a plan owns its items. A plan has **no**
    relationship to `FocusSession`, so deleting a plan never touches a running or
    historical session (ADR-029).
- **Cascade** on `intervals`: a session owns its intervals, so deleting a
  session removes them. Verified by `PersistenceTests.deleteCascades`.
- **Nullify** on `focusSessions`: history should survive editing/removing a
  configuration, so the reference is nulled rather than deleting sessions.
  Verified by `PersistenceTests.deleteNullifies`.
- All relationship endpoints that may be absent are **optional**, so a nullify
  cannot leave a non-optional property dangling.

## 6. Enums stored in the model

`String`-backed `Codable` enums (a SwiftData requirement for stored enums):

- `TimerPhase` — focus / shortBreak / longBreak (shared with the engine).
- `SessionStatus` — the persisted **session** lifecycle. Distinct from the
  engine's `TimerState` (ADR-012).
- `IntervalStatus` — the persisted **interval** lifecycle. Distinct from the
  engine's `IntervalOutcome`, which it maps from for terminal intervals.

The engine's `TimerState`/`IntervalOutcome` remain pure in-memory domain
vocabulary; the persisted models use the dedicated `SessionStatus`/`IntervalStatus`
so persistence concerns (planned/interrupted, pending/paused) never leak into the
engine.

## 7. Schema & migration

- `TimeFrameSchemaV5: VersionedSchema` (version `5.0.0`) is the **current** schema
  (adds `SessionPlan`, `SessionPlanItem`, and `SessionInterval.configurationName`;
  Milestone 5). `V1`–`V4` are retained as historical anchors. A
  `TimeFrameSchemaLatest` typealias points at the current version.
- `TimeFrameMigrationPlan: SchemaMigrationPlan` targets V5 with **no field-level
  stage**. Consistent with **ADR-016/019/021**, an incompatible older on-disk
  store is **rebuilt** by `PersistenceController` rather than field-migrated
  (losing only the re-seedable default configuration and dev-only prior
  sessions/templates); future data-bearing versions append a concrete
  `MigrationStage` instead.
- `PersistenceController.makeContainer(inMemory:)` builds the container from the
  versioned schema and migration plan, rebuilding an incompatible on-disk store
  once so relaunch persistence keeps working. In-memory test stores are created
  fresh at V4 and never migrate.

## 8. Value snapshot (engine boundary)

`PomodoroConfigurationSnapshot` is **not** a SwiftData type. It is an immutable,
validated `Sendable` value (`Timer/PomodoroConfigurationSnapshot.swift`) that the
engine runs from. Construction clamps durations to a minimum of 1 s and counts to
at least 1, so the engine can assume sane inputs.

## 9. Future direction (do not build yet, do not block)

`TaskTemplate` now exists (Milestone 4), holding a to-one reference to
`PomodoroConfiguration` (mirroring `FocusSession`), so configuration values are
never duplicated. The realised chain is:

```
TaskTemplate  →  PomodoroConfiguration  →  SessionSetupDraft  →  FocusSession  →  SessionInterval
```

The **Session Planner now exists** (Milestone 5): `SessionPlan`/`SessionPlanItem`
are persisted planning entities that freeze into a value snapshot and run through
the same chain (see §4b and `docs/14-SESSION-PLANNER.md`):

```
TaskTemplate / PomodoroConfiguration
        →  SessionPlan  →  SessionPlanExecutionSnapshot
        →  SessionCoordinator  →  FocusSession  →  SessionInterval  →  History
        →  (future) CalendarEventGenerator  →  Calendar Event
```

Notifications and menu bar remain deferred; the planner exposes enough (start/end,
duration, task, per-interval phase and configuration) to generate calendar events
without a redesign.

**Statistics (Milestone 10)** read this same chain end-to-end with **no schema change**.
Every metric derives from existing `FocusSession`/`SessionInterval` fields — `status`,
`phase`, `plannedDuration`, `startedAt`/`endedAt`, and the frozen `configurationName`s
(session-level and per focus interval). Because the names are frozen, statistics survive a
configuration rename/delete exactly as History does (ADR-019/028). Note the schema does **not**
persist a durable `TaskTemplate`/`SessionPlan` reference on a completed session (templates/plans
are copied-from starting points, ADR-021/025/028), so statistics attribute by configuration name
and task only; durable template/plan attribution would be a future data-model change (ADR-054;
see `docs/19-STATISTICS.md` §9).

## 10. Calendar associations (Milestone 6 — not SwiftData)

The Calendar/EventKit integration (Milestone 6) **adds no `@Model` type and does not
change the schema** (it stays V5). Calendar **settings** (`CalendarSettings`) and the
plan/session ↔ event **associations** (`CalendarEventRecord`, keyed by owner id) are
lightweight, non-relational metadata and persist in `UserDefaults` via small
observable stores (ADR-037). No `EKEvent`/`EKCalendar` is ever persisted — only
identifiers (`CalendarEventReference`). The core timer models
(`FocusSession`/`SessionInterval`/`SessionPlan`/…) carry **no** Calendar or EventKit
fields. See `docs/15-CALENDAR-INTEGRATION.md`.

## Milestone 13 — CloudKit compatibility (schema V6)

`TimeFrameSchemaV6` makes the store CloudKit-mirrorable. Two changes:

1. **`#Unique` removed from all six models.** CloudKit does not support uniqueness constraints,
   and keeping one breaks the *local* store too once a CloudKit-backed configuration is used
   (ADR-061). `id` remains a freshly-minted `UUID`; the repositories never reuse ids, so
   identity is still effectively unique. Every other CloudKit rule (all attributes
   optional-or-defaulted, to-one relationships optional, cascade/nullify delete rules,
   `String`-backed `Codable` enums) was **already** satisfied by V5.
2. **`FocusSession.originatingDeviceID`** — an additive **optional** `String` (a random
   per-install id, no PII) so timer recovery stays device-local across synced devices (ADR-063).
   `nil` means "local" for back-compat.

The model *set* is unchanged from V5. The store's rebuild-on-incompatibility policy
(ADR-016/019/021) carries an older local store forward. See `docs/22-ICLOUD-CLOUDKIT.md`.

## Milestone 17 — schema unchanged; migration policy now tested

M17 makes **no schema change** (stays **V6**). It adds hermetic tests of the *actual* upgrade policy —
**rebuild-on-incompatibility** — via a new testable seam
`PersistenceController.openOnDiskContainer(schema:configuration:)`: an incompatible legacy store and a
corrupt store file are both rebuilt into a usable V6 store; every model round-trips a real close/reopen
with no data loss; and the additive optional `FocusSession.originatingDeviceID` defaults to `nil` with
legacy nil-origin rows staying device-local (ADR-063). See `docs/26-PRODUCTION-READINESS.md`.

## Milestone 28 — schema V7 (Quick Start identity on Templates and Plans)

`TimeFrameSchemaV7` adds three attributes to each of `TaskTemplate` and `SessionPlan`. The
model **set** is unchanged — the same six `@Model` types as V5/V6.

| Attribute | Type | Purpose |
|---|---|---|
| `iconIdentifier` | `String`, defaulted | the stable catalog identifier of the user's chosen icon — never an SF Symbol name and never free text (ADR-103). Read it through the model's `icon`, which resolves an unrecognised value to the type's default. |
| `isPinned` | `Bool`, defaulted `false` | whether the item is pinned to Quick Start (ADR-104). |
| `pinnedAt` | `Date?`, optional | when it was pinned; drives the oldest-pin-first Quick Start order. `nil` whenever unpinned. |

Pin state deliberately lives **on the item**, keyed by its existing stable `UUID`, rather than
in a side table or a preference key. That is what makes a rename keep the pin, a delete remove
it from Quick Start, and an edit never change it — with nothing to reconcile.

Every added attribute is defaulted or optional, so V7 satisfies the same CloudKit rules V6
established (ADR-061) and is lightweight-migratable: SwiftData opens an existing V6 store in
place. The rebuild-on-incompatibility policy (ADR-016/019/021) still applies as the safety net.
See `docs/37-M28-MENU-BAR-QUICK-START-ICONS.md`.
