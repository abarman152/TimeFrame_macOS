# 10 — Testing Plan

> **Milestone 22 note.** Control Center coverage is deterministic and host-free: macOS
> `ControlCenterPresentationTests` / `ControlCenterRoutingTests` (state, control set, primary action,
> projection freshness incl. `restart`, failure isolation, concurrency, performance),
> `ProductionReadinessM22Tests` (source-boundary audit), and iOS `IOSControlCenterTests`. macOS now
> **749 tests / 164 suites**; iOS **90 tests** (iPhone & iPad). See `docs/31-CONTROL-CENTER-CONTROLS.md`.

Time Frame uses **Swift Testing** (`@Test`, `@Suite`, `#expect`). The timer
engine is verified **deterministically** through an injected clock, so the entire
suite runs in ~0.1 s without ever waiting real time.

> **Milestone 18 — two test targets.** The macOS suite (`time_frameTests`, hosted by the macOS app)
> remains the primary gate and is unchanged in intent; its `ProductionReadinessTests` were updated for
> the new shared `Core/` roots and now assert ActivityKit is imported **only** in the iOS targets. A
> second suite, **`TimeFrameiOSTests`** (hosted by the `TimeFrameiOS` app, run on an iOS Simulator),
> covers the iOS-only value layer deterministically without needing a live Live Activity: attribute ↔
> identity binding and the neutral `ContentState` round-trip, the shared presentation mapping, the
> **device-local cross-device running-session policy** (a remote session is never taken over), and the
> shared statistics aggregator + deep-link navigation. ActivityKit lifecycle stays covered by the M16
> fake-service suite — no test depends on a real Dynamic Island. See `docs/27-IOS-COMPANION-LIVE-ACTIVITIES.md`.

> **Milestone 19 — CloudKit validation suites.** New deterministic suites, no real iCloud account:
> `CloudKitCapabilityTests` (macOS) + `IOSCloudKitCapabilityTests` (iOS) cover the full entitled ×
> preference × account matrix and pin the honest "this build is not entitled" fact;
> `CrossDeviceSyncValidationTests` (macOS) models a merged synced store with two device-scoped
> coordinators (frozen-field integrity across rename/delete, both-device history visibility, device-local
> running-session safety, statistics from merged history, timer usable under CloudKit fallback);
> `ProductionReadinessM19Tests` adds App-Group-consistency, no-fabricated-entitlement, CloudKit-wiring,
> deep-link-scheme, and no-committed-secrets audits to the release gate. Totals: **macOS 679 tests / 144
> suites**, **iOS 13 tests**. See `docs/28-CLOUDKIT-DEVICE-VALIDATION.md`.

---

## 1. Principles

- **Deterministic time.** Tests inject a `MockTimeSource` and advance it by hand
  (`clock.advance(by:)`). A 25-minute interval is exercised instantly. No test
  sleeps or waits for wall-clock time.
- **Engine tested in isolation.** `TimerEngine` is driven directly with a mock
  clock.
- **Coordinator persistence tested deterministically.** The `SessionCoordinator`
  is built with the mock clock, an in-memory store, and `autoTick: false`, so the
  background heartbeat never runs and `tick()` is called by hand. Every lifecycle
  and recovery assertion is therefore fully deterministic.
- **Persistence tested against an in-memory store.** Each persistence test builds
  its own in-memory `ModelContainer` and **keeps it alive for the whole test**
  (a `ModelContext` does not retain its container). One test additionally uses a
  real on-disk store (close/reopen) to verify relaunch persistence.

## 2. Test target

- Target: `time_frameTests` (unit-test bundle), hosted by the `time_frame` app so
  `@testable import time_frame` works.
- Runs via the shared `time_frame` scheme:
  `xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame -destination 'platform=macOS' test`.

## 3. Support files

- `MockTimeSource.swift` — a lock-guarded, hand-advanced `TimeProviding`.
- `TestSupport.swift` — `makeConfig(...)` (short test durations), `makeEngine(...)`,
  and `expectClose(...)` (tolerant time comparison).
- `PersistenceTestSupport.swift` — in-memory container, repository, and
  coordinator factories; `insertConfiguration(...)`.

## 4. Coverage map (as implemented — 290 tests, 46 suites)

### Milestone 1 suites (46) — unchanged and still green
`PomodoroConfigurationSnapshotTests` (3), `IntervalPlanTests` (7),
`TimerEngineStateTests` (7), `TimerEngineControlTests` (9),
`TimerEngineSequenceTests` (5), `TimerEngineEdgeCaseTests` (10),
`PersistenceTests` (5). Detailed below.

### Milestone 2 — engine restoration — `TimerEngineRestoreTests` (5)
- Restore a running snapshot (remaining derived from anchors).
- Restore a paused snapshot (remaining frozen through clock advance).
- Restore ignored unless the engine is idle.
- Restore + `synchronize()` fast-forwards through elapsed intervals.
- Restore preserves completed-interval history.

### Milestone 2 — configuration validation — `ConfigurationValidationTests` (7)
- Valid draft; empty/whitespace name; focus `> 0`; breaks `≥ 0`; counts `≥ 1`;
  over-maxima rejected; invalid input reported, never mutated.

### Milestone 2 — configuration repository — `ConfigurationRepositoryTests` (11)
- Create (+ reject invalid, storing nothing), read-all, update (+ reject
  invalid), delete, duplicate (independent, non-default), set-default (exactly
  one), seed once, seed idempotent (no duplicate default), seed respects existing.

### Milestone 2 — session lifecycle persistence — `SessionLifecycleTests` (8)
- Start persists session + full interval plan (ordering, anchors).
- Pause persists paused + frozen remaining; resume clears the pause anchor.
- Automatic transition persists on tick (no duplicate intervals).
- Skip persists `skipped`; restart resets in place (no new row); stop persists
  `cancelled` and preserves completed intervals; completion persists `completed`.

### Milestone 2 — recovery — `SessionRecoveryTests` (7)
- Running session restored across relaunch (no duplicate session).
- Fully-elapsed session reconciled to completed.
- Many intervals elapsed while away all transition (no duplicates).
- Paused session restored paused, remaining intact.
- Inconsistent running session marked interrupted.
- No-op when nothing recoverable; multiple stale actives collapse to one.

### Milestone 2 — on-disk relaunch — `OnDiskRelaunchTests` (1)
- A running session survives a real store close/reopen (two independent
  containers over the same file).

### Milestone 3 — setup draft & snapshot override — `SessionSetupDraftTests` (6)
- Task name required (empty/whitespace invalid, non-empty valid); trimmed name.
- Plan preview honours the session-count override and uses the configuration's
  durations.
- `overriding(totalSessions:)` replaces only the count; a nil override is identity.

### Milestone 3 — application logic — `Milestone3ApplicationTests` (12)
- **Session count override** (2): sets this run's focus count without mutating the
  configuration; omitting it uses the configuration default.
- **Configuration-name snapshot** (3): frozen at start; unchanged by a later
  rename; survives configuration deletion (`displayConfigurationName`).
- **History-derived values** (2): completed focus count/duration come from
  persisted intervals; a stopped session counts only completed focus intervals.
- **Edit-while-running isolation** (1): editing the active configuration leaves the
  running plan and the persisted intervals unchanged.
- **Start-new-session reset** (2): `prepareForNewSession` clears a completed run;
  it is ignored while a session is still active.
- **Recovery outcomes** (2): a restorable running session yields `.restored`; an
  inconsistent one yields `.interrupted` (and is marked interrupted in the store).

### Milestone 4 — template validation — `TaskTemplateValidationTests` (9)
- Valid draft passes; empty name / empty task / missing configuration rejected;
  session count below 1 and above the max rejected; boundary counts (1, max) valid;
  names trimmed; `validated()` throws on an invalid draft.

### Milestone 4 — template repository — `TaskTemplateRepositoryTests` (14)
- Create (fresh timestamps, trimming, invalid-draft rejection, unknown-configuration
  rejection), read newest-first, update (changes + `updatedAt` bump, re-point
  configuration, invalid-draft rejection), delete (keeps configuration), duplicate
  (independent, non-default, "… Copy"; editing the copy leaves the original),
  set/clear default (exactly one), and configuration-deletion **nullify** (template
  survives, reference cleared, shown unavailable).

### Milestone 4 — application logic — `Milestone4ApplicationTests` (12)
- **Model** (2): template name distinct from task name; a configured template is
  complete.
- **Template → setup** (3): a `SessionSetupPrefill` copies task/configuration/count;
  starting from a template creates a normal `FocusSession`; a per-run count override
  does not mutate `TaskTemplate.defaultTotalSessions`.
- **Independence** (4): editing the template, editing the configuration, and
  deleting the template each leave an already-started session unchanged; a template
  whose configuration was deleted cannot start (no-op).
- **Lifecycle** (3): a template-started session can pause/resume, skip, and run to
  completion through the existing coordinator/engine.

### Milestone 5 — plan generation — `SessionPlanGeneratorTests` (12)
- Session counts (1/2/4), long-break placement, the **optional trailing break**
  (off by default, on when asked), custom durations, determinism, per-focus
  configuration identity, contiguous 0-based orders, focus count matches request.

### Milestone 5 — plan validation — `SessionPlanValidationTests` (14)
- Valid plan; empty name/task; no focus; focus missing configuration; zero/over-long
  interval; too many items; total > 24 h; total-duration arithmetic; empty plan
  reports all rules; order normalization preserves identity; focus count.

### Milestone 5 — plan repository — `SessionPlanRepositoryTests` (12)
- Create (ordered items, timestamps), reject invalid, fetch newest-first, update
  (reorder/add/remove preserving identity, no duplicate rows), delete keeps
  configuration, duplicate is independent, configuration deletion nullifies (plan
  kept, name frozen, `isStartable` false), configuration reports plan usage, ordering
  persists on refetch, a plan mixes multiple configurations.

### Milestone 5 — plan execution — `SessionPlanExecutionTests` (11)
- Start builds a running `FocusSession` with correct order/phase/duration/frozen
  names; no duplicate session or intervals; multi-configuration execution;
  **independence** — editing the plan, deleting the plan, editing the configuration,
  and deleting the configuration each leave the running session unchanged/valid;
  runs to completion; pause/resume; no second active session; **recovery** of a
  plan-started session after a simulated relaunch.

---

### Milestone 6 — Calendar / EventKit — 34 tests, 4 suites

All calendar tests are deterministic and use a `FakeCalendarService` + scratch
`UserDefaults` — **no real Calendar, no permissions prompt** (§43/§75).

- **`CalendarEventGeneratorTests` (11)** — single vs per-interval events; `start +
  total = end`; per-interval titles/notes; long-break titling; multiple
  configurations in notes; trailing-break included/excluded; title override; empty
  plan; blank-override fallback.
- **`CalendarPersistenceTests` (4)** — settings defaults and round-trip; event-record
  CRUD across store instances; upsert replaces (no duplicate owner).
- **`CalendarCoordinatorTests` (10)** — authorization branches (grant/deny,
  insufficient statuses); stale-default-calendar clearing; add plan single &
  per-interval; duplicate prevention (re-add replaces); create failure isolation; add
  without access; explicit event removal.
- **`CalendarTimerIndependenceTests` (9)** — the timer starts/runs/pauses/stops when
  create/update fail or permission is denied; event created on start with the actual
  time; no per-tick calendar writes; stop keeps the event; completion adjusts once;
  externally deleted event is forgotten, not recreated.

---

### Milestone 7 — Notifications — 42 tests, 6 suites

All notification tests are deterministic and use a `FakeNotificationService` + scratch
`UserDefaults` — **no real notification center, no permissions prompt** (§52). Suite total
at Milestone 7: **260 tests**, 0 warnings.

- **`NotificationContentTests` (6)** — every type's title/subtitle/body; never-empty
  titles (app-name fallback); duration/configuration/progress wording; singular vs plural.
- **`NotificationScheduleBuilderTests` (9)** — one request per upcoming boundary (exactly
  one for a single-focus session, seven for a full plan); cumulative fire dates along the
  authoritative timeline; per-category preference gating; long-break count; stable
  session+interval identifiers; immediate completion descriptor; no scheduling for
  already-past intervals from a mid-plan index.
- **`NotificationActionResolverTests` (7)** — the §40 safety matrix: open always
  activates; pause only while running; resume only while paused; skip/stop while active;
  mismatched / missing / finished session ignored (never a crash).
- **`NotificationCoordinatorTests` (11)** — authorization grant/deny; start schedules the
  transition; no per-tick scheduling; disabled schedules nothing; pause cancels & resume
  reschedules; skip reschedules; stop cancels all; completion delivers exactly one (no
  duplicate); master toggle-off cancels; Pause/Resume actions route through
  `SessionCoordinator`; stale action ignored.
- **`NotificationTimerIndependenceTests` (6)** — the timer starts/runs/pauses/resumes/
  skips/stops/completes when scheduling fails or permission is denied; Calendar and
  Notifications never affect each other (a notification failure still lets Calendar record,
  and vice versa).
- **`NotificationRecoveryTests` (3)** — relaunch reschedules the next transition; stale
  Time Frame notifications are cancelled before rescheduling; a completed session is never
  resurrected.

---

### Milestone 8 — Menu Bar — 30 tests, 5 suites

All menu-bar tests are deterministic and drive the **real** `SessionCoordinator`/engine via
the mock clock, with a `MenuBarCoordinator` observing it (`MenuBarRig`) — proving the menu
bar is a projection of the one timer, not a second one. No menu-bar rendering is tested
(§55). Suite total at Milestone 8: **290 tests**, 0 warnings.

- **`MenuBarPresentationTests` (8)** — the `MenuBarPresentationState` projection for every
  situation: idle/empty, focus running (task/phase/remaining/progress/next), short break,
  long break, paused (frozen), completed (not a stale countdown), interrupted; plus that it
  shows the session's **frozen** configuration name, not the live one (§53/§57).
- **`MenuBarControlTests` (10)** — Pause/Resume/Skip/Stop/Restart each route through
  `SessionCoordinator`; "start new session" resets; the countdown derives from the
  authoritative clock without a tick (§58); and inapplicable actions (pause with no session,
  resume when completed, stop with no session) are safe no-ops (§60).
- **`MenuBarPreferencesTests` (5)** — default on; visibility and countdown flags persist;
  countdown-off title; disabling the menu bar never disturbs a running timer (§26/§65).
- **`MenuBarRecoveryTests` (3)** — a recovered running session projects running with
  fast-forwarded time; a recovered paused session stays frozen; a session completed while
  away projects completed, never stale running (§35/§76).
- **`MenuBarIndependenceTests` (4)** — a failing Notification **and** Calendar integration
  never break the menu bar; a menu-bar control still drives the timer while both fail;
  robustness for an empty task name and a deleted configuration (§60/§61/§62/§93).

---

### Milestone 9 — Liquid Glass Visual Identity — 0 new automated tests (still **290**)

Milestone 9 is a **presentation-only** milestone. Per the milestone's own testing strategy,
it does **not** add fragile pixel-perfect snapshot tests, and it does not introduce a new UI
testing framework (there is no XCUITest target). The regression guarantee is instead:

- **Timer/domain regression** — the full **290-test** suite passes **unchanged**, because no
  file under `Timer/`, `Services/`, or `Models/` was modified (verified by file-modification
  and `Timer.publish`/`Task.sleep`/`asyncAfter`/decrement audits). Same clock + configuration →
  same engine behaviour before and after (§95).
- **Test-host hermeticity** — the app target is also the unit-test *host*, so `time_frameApp`
  now skips live store seeding/recovery under XCTest (`XCTestConfigurationFilePath`/
  `XCTestBundlePath`/`XCTestSessionIdentifier`). Tests build their own in-memory containers, so
  this makes the suite immune to any real persisted state (a running session left in the
  developer's store previously hung the runner at launch). Normal launches are unaffected.
- **Accessibility identifiers** — the added `timeFrame.timer.*` identifiers and all
  pre-existing identifiers are present in source; they support future UI automation without
  changing behaviour.
- **Manual GUI acceptance (macOS 27, Dark mode)** — Setup, Running, and the glass transport
  cluster were verified by launching the built app and inspecting screenshots (correct
  hierarchy, phase-tinted timeline, prominent-vs-secondary glass buttons, "Session X of N").
  Paused, Completion, Light mode, the menu-bar popover, and the Templates/Plans/Configurations/
  History/Settings screens were verified by **code review + build + tests**, not live GUI —
  interactive driving of the running app was not reliable under screen automation. Manual
  acceptance is therefore **PARTIAL** and honestly reported as such.
- **Reduce Motion / Light-Dark / Dynamic Type** — handled structurally (`tfAnimation` reads
  `accessibilityReduceMotion`; all colours are system/accent/`TFPalette`; layout uses a
  bounded content column), not asserted by automated tests.

---

### Milestone 1 detail — 46 tests, 7 suites

### Configuration — `PomodoroConfigurationSnapshotTests` (3)
- Custom durations and counts preserved.
- Zero / negative / NaN durations clamped to the minimum.
- Session count and long-break interval clamped to ≥ 1.

### Session plan generation — `IntervalPlanTests` (7)
- Four-session sequence alternates focus/break and ends on a long break.
- Durations map to the correct phase.
- Indices contiguous and 0-based.
- Custom long-break interval (every 2nd).
- Single-session plan.
- One-in-one interval makes every break long.
- Focus count equals configured session count.

### State machine — `TimerEngineStateTests` (7)
- Starts idle.
- Idle → Running (start).
- Running → Paused (pause).
- Paused → Running (resume).
- Running → Completed (whole plan elapses).
- Running → Cancelled (stop).
- Invalid transitions are ignored (no-ops).

### Controls — `TimerEngineControlTests` (9)
- Start anchors the first interval (remaining / elapsed correct).
- Pause preserves remaining regardless of clock advance.
- Resume continues from preserved remaining; time-while-paused doesn't count.
- Stop records the in-progress interval as `.cancelled`.
- Skip during focus advances to the break, records `.skipped`.
- Skip during a break advances to the next focus.
- Restart resets the current interval to full duration.
- Restart while paused stays paused with full remaining.
- Skip past the final interval completes the session.

### Session sequence & authoritative clock — `TimerEngineSequenceTests` (5)
- Full four-session run completes every interval in order, all `.completed`.
- Long break lands after the configured number of sessions.
- A single `synchronize()` fast-forwards through intervals missed during sleep.
- A delayed tick completes multiple intervals at once **without drift**.
- Remaining never goes negative even when the tick is very late.

### Edge cases — `TimerEngineEdgeCaseTests` (10)
- Very short (1 s) durations still transition.
- Zero durations clamped and still runnable.
- Single-session configuration completes after focus + break.
- Multiple sessions produce the expected interval count.
- Completing the final interval → `completed` (no phantom interval, remaining 0).
- Pause immediately before completion, then resume, finishes the interval.
- Resuming an interval paused exactly at zero completes it.
- Restart after partial progress restores full duration, plan intact.
- `reset()` returns a finished engine to idle with the same plan.
- `load()` replaces the plan while idle and is ignored while running.

### Persistence — `PersistenceTests` (5)
- Container initializes from the versioned schema.
- A configuration can be inserted and fetched.
- A session references its configuration and owns its intervals.
- Deleting a session **cascades** to its intervals.
- Deleting a configuration **nullifies** its sessions but keeps them.

## 5. Requirement → test traceability (highlights)

| Requirement | Test(s) |
|---|---|
| Custom focus / break / long-break durations | `IntervalPlanTests.durationsMapCorrectly`, `PomodoroConfigurationSnapshotTests.customValues` |
| Custom session count & long-break interval | `IntervalPlanTests.customLongBreakInterval`, `focusCountMatchesConfig` |
| Idle→Running→Paused→Running→Completed / Cancelled | `TimerEngineStateTests` |
| Start / Pause / Resume / Stop / Skip / Restart | `TimerEngineControlTests` |
| Focus/break sequence incl. long break | `TimerEngineSequenceTests.fullRunOrder`, `longBreakPlacement` |
| Authoritative clock (sleep / delayed ticks / no drift) | `TimerEngineSequenceTests.fastForwardThroughSleep`, `delayedTickChainsIntervals`, `remainingNeverNegative` |
| Skip preserves history | `TimerEngineControlTests.skipDuringFocus`, `stopRecordsCancelled` |
| Deterministic testing | entire suite via `MockTimeSource` |
| SwiftData init & delete rules | `PersistenceTests` |
| Configuration CRUD / duplicate / default | `ConfigurationRepositoryTests` |
| Configuration validation + limits | `ConfigurationValidationTests` |
| Idempotent default seeding (no duplicates) | `ConfigurationRepositoryTests.seed*` |
| Session start/pause/resume/skip/restart/stop/complete persisted | `SessionLifecycleTests` |
| Interval creation/order/status/skip/cancel persisted | `SessionLifecycleTests` |
| Timestamp-based recovery / reconcile & resume | `SessionRecoveryTests`, `TimerEngineRestoreTests` |
| Sleep/wake multi-interval fast-forward | `SessionRecoveryTests.multipleIntervalsElapsed` |
| Paused session stays paused across relaunch | `SessionRecoveryTests.restorePaused` |
| No duplicate sessions/intervals on recovery | `SessionRecoveryTests`, `SessionLifecycleTests` |
| Real on-disk relaunch persistence | `OnDiskRelaunchTests` |
| Engine stays SwiftData-free (value restore seam) | `TimerEngineRestoreTests` |
| Task required / count override / plan preview (setup) | `SessionSetupDraftTests` |
| Session count override doesn't mutate the configuration | `SessionCountOverrideTests` |
| History accurate through config rename/delete (name snapshot) | `ConfigurationNameSnapshotTests` |
| Editing a configuration doesn't affect the running session | `EditWhileRunningTests` |
| Completed focus count/duration from persisted intervals | `HistoryDerivedValuesTests` |
| Recovery outcome surfaced (restored / interrupted) | `RecoveryOutcomeTests` |
| Start New Session resets a finished run | `PrepareForNewSessionTests` |
| Template validation (name/task/config/count) | `TaskTemplateValidationTests` |
| Template CRUD / duplicate / default / config-nullify | `TaskTemplateRepositoryTests` |
| Template → session workflow & per-run override isolation | `TemplateSessionSetupTests` |
| Template independent of history (edit/delete template & config) | `TemplateIndependenceTests` |
| Template-started session pause/resume/skip/complete | `TemplateSessionLifecycleTests` |
| Statistics aggregation (focus/break/counts/rate/avg/longest/breakdowns) | `StatisticsAggregationTests` |
| Statistics date ranges (today/week/month/custom, midnight, time zone, DST) | `StatisticsDateRangeTests` |
| Statistics trends (current vs previous, zero-previous, identical) | `StatisticsTrendTests` |
| Statistics repository mapping (empty/one/many, rename/delete config, read-only) | `StatisticsRepositoryTests` |
| Statistics edge cases (empty, zero-duration, midnight cross, 1k-session dataset) | `StatisticsEdgeCaseTests` |
| Statistics in navigation, Today shares engine, period changes, timer/History unaffected | `StatisticsApplicationTests` |

### Milestone 11 — WidgetKit — 36 tests, 7 suites

| What | Where |
|------|-------|
| Projection mapping for every state (idle, focus, short/long break, paused, completed, interrupted) from the real coordinator/engine | `WidgetProjectionMappingTests` |
| Timeline policy (running reloads at planned end; paused schedules no tick; settled/corrupt states are conservative and never empty) | `WidgetTimelinePolicyTests` |
| Serialization: Codable round-trip, schema-compatibility flag, unknown enum/corrupt payload fallback | `WidgetProjectionSerializationTests` |
| App Group store: write/read round-trip, missing-suite no-op, corrupt/incompatible → nil, clear | `WidgetProjectionStoreTests` |
| Deep links: URL round-trip, section mapping, unknown URLs ignored | `WidgetDeepLinkTests` |
| Writer: writes matching projection + reloads; refresh on lifecycle event; never mutates coordinator/engine | `WidgetProjectionWriterTests` |
| Boundary invariants (static source scan): widget imports no SwiftData/app module, references no `TimerEngine`/`SessionCoordinator`, creates no timer loop; shared code imports only Foundation | `WidgetBoundaryInvariantTests` |

## 6. Current result

- **377 tests, 67 suites — all passing** (parallel and serial), no warnings.
  (Milestone 11 added **36** WidgetKit tests to the Milestone 10 baseline of 341;
  Milestone 10 added **51** statistics tests to the Milestone 9 baseline of 290.)
- Build: `** BUILD SUCCEEDED **`. Tests: `** TEST SUCCEEDED **`.
- The primary UI workflow was additionally verified by launching the built app
  and driving it manually (setup → start → running → pause → stop → history).

## 7. Not yet covered (later milestones)

- **XCUITest UI tests.** The project currently has only the `time_frameTests`
  unit-test bundle; there is no UI-test target, and adding one requires
  `project.pbxproj` *target* surgery (file-system-synchronized groups add source
  files automatically, but not targets). Rather than take that risk in this
  milestone, Milestone 3 covers the UI's **application logic** with deterministic
  unit tests (setup draft, count override, name snapshot, edit-while-running,
  recovery outcomes) and verifies the critical flow by manual launch. The
  Templates UI additionally carries **stable accessibility identifiers**
  (`template.new`, `template.save`, `template.detail.start`, …) so a dedicated
  XCUITest target — still planned — can drive it without further UI changes.
- `SessionCoordinator` heartbeat *timing* under real wall-clock (the async `Task`
  cadence) — deferred; its persistence/recovery *logic* is covered deterministically
  with `autoTick: false`, and correctness of time is covered by the engine tests.
- Statistics/analytics over persisted history — implemented (Milestone 10), covered by the
  statistics suites.

## App Intents (Milestone 12)

App Intent logic is tested **deterministically without Siri or the Shortcuts app**: the
intents' work lives in `AppIntentSessionActions` and the entity queries' `@MainActor` static
resolution cores, both driven against an in-memory `SessionCoordinator`/repositories with a
mock clock (heartbeat off). Suites (`time_frameTests/AppIntent*`, `StartIntentTests`,
`TimerControlIntentTests`): state projection (all lifecycle states), dialog text, entities +
entity queries (stable ids, display reps, deleted records, search), Start Template / Start Plan
/ Start Time Frame (valid/invalid/default/count/active-conflict/prefill), timer controls (+ idle
behavior), current status, App Shortcuts (curated count / stability), failure isolation (a
failing intent never corrupts the timer; a resolution failure creates no partial session), and a
regression pass proving the menu bar and widget projections still read the one coordinator after
an intent acts. The dependency manager is **not** used in tests (its values are only accessible
inside a real intent perform flow). The full suite is **434 tests / 79 suites**, 0 warnings.

## Milestone 13 — iCloud / CloudKit sync

All CloudKit tests are **deterministic and require no real iCloud account**: CloudKit init
failures are simulated by injecting a throwing container factory into
`PersistenceController.bootstrap`, and account availability is faked via a
`CloudAccountStatusProviding` stub. New suites: `CloudSyncConfigurationTests` (mode mapping +
fallback + device identity), `CloudSyncPresentationTests` / `CloudSyncCoordinatorTests` (every
presentation phase + reason enum), `CloudKitModelCompatibilityTests` (no uniqueness constraints;
full model round-trip), `OfflinePersistenceTests` (whole app works with CloudKit unavailable),
`RunningSessionSyncTests` (device-local recovery — no second timer, no cross-device mutation),
`HistoricalIntegrityTests` (rename/plan-delete/template-delete never rewrite frozen history),
`SyncFailureIsolationTests` (a CloudKit failure never blocks the timer), and
`CloudPersistenceRegressionTests` (WidgetKit + App Intents still work). The unit-test host forces
local persistence so the suite never touches CloudKit. The full suite is **475 tests / 88
suites**, 0 warnings. See `docs/22-ICLOUD-CLOUDKIT.md`.

## Milestone 14 — Configurable Widget — 42 tests, 8 suites

The configurable widget is tested **deterministically without a WidgetKit host, Shortcuts/Siri, or
an iCloud account**. The configuration model, intent, timeline, and boundary are pure/value work;
the isolation and CloudKit-independence suites wire the **real** coordinator + engine (mock clock,
heartbeat off) and prove the widget paths mutate nothing.

| What | Where |
|------|-------|
| Config model: defaults, value sets, destination→deep-link, Codable round-trip, Hashable, malformed/partial fallback | `WidgetConfigurationTests` |
| Config intent: parameter defaults, type/case display representations (plain wording), choice→configuration mapping | `WidgetConfigurationIntentTests` |
| Configured timeline: per-state entries + reload; **timing invariance** across Timer/Today/Statistics; config carried onto entries | `ConfiguredWidgetTimelineTests` |
| Projection M14 fields: new-field round-trip, M11 backward-compat decode, malformed trend → steady, incompatible-version rejection, unchanged schema constants | `WidgetProjectionConfigurationTests` |
| Isolation: configuring/building timelines mutates no coordinator/engine/session/interval and writes no `ModelContext` | `WidgetConfigurationIsolationTests` |
| CloudKit independence: local-only store path + App-Group-unavailable fallback both build a valid timeline | `WidgetCloudKitIndependenceTests` |
| Boundary (static scan): widget imports no CloudKit/SwiftData/`ModelContext`; the one `AppIntents` import in `Shared/` is isolated; expanded timer-token scan | `WidgetConfigurationBoundaryTests` |
| Performance: bounded, DB-free timeline-building and codec throughput | `WidgetProjectionPerformanceTests` |

The App Intents metadata for the widget was additionally verified by inspecting the built
`TimeFrameWidgets.appex/Contents/Resources/Metadata.appintents` (the configuration intent, its three
`AppEnum`s, and their user-facing strings are present). **Manual widget-gallery verification was not
performed** — no GUI/widget-gallery automation is available in this environment.

### Interactive widget (Milestone 15)

Deterministic, no WidgetKit host / Siri / iCloud. The action, projection, failure, concurrency, and
recovery suites wire the **real** coordinator + engine (mock clock, heartbeat off) plus the real
`WidgetProjectionWriter` over a volatile store and the app-side `WidgetControlActions` router, so they
drive the exact production path a widget button takes.

| What | Where |
|------|-------|
| Actions: Start/Pause/Resume/Skip/Restart/Stop drive the coordinator; store reflects new state; reloads on meaningful actions | `InteractiveWidgetActionTests` |
| State→controls: exact controls per state/phase on small & medium (pure `WidgetControlSet`) | `InteractiveWidgetStateTests` |
| Configuration: control availability ignores configuration; timing stays config-invariant | `InteractiveWidgetConfigurationTests` |
| Failure isolation: unavailable router, no-active-session, double start, stale action, invalid transition all fail safely | `InteractiveWidgetFailureTests` |
| Concurrency: repeated Pause/Resume/Stop + mixed sequences keep the coordinator authoritative | `InteractiveWidgetConcurrencyTests` |
| Recovery: start-after-completion/stop; running/paused projection coherence | `InteractiveWidgetRecoveryTests` |
| CloudKit independence: the full flow over a local store with no CloudKit | `InteractiveWidgetCloudKitIndependenceTests` |
| Projection flow: store equals the mapper's authoritative view; restart refreshes anchors; no per-tick reload | `InteractiveWidgetProjectionTests` |
| Boundary (static scan): shared control file + widget own no timer/persistence/CloudKit/domain; router delegates through the one `AppIntentSessionActions` seam | `InteractiveWidgetBoundaryTests` |

`WidgetConfigurationBoundaryTests` was extended to allow the second `Shared/` `AppIntents` importer
(`WidgetControlIntents.swift`). The widget App Intents metadata was verified by inspecting the built
`Metadata.appintents`: all six widget-control intents (`Widget{Pause,Resume,Skip,Restart,Stop,Start}Intent`,
`isDiscoverable == false`) are discovered alongside the unchanged configuration intent, and
`--validate-assistant-intents` passes. **Manual interactive-widget verification was not performed** —
no GUI/widget-gallery automation is available in this environment.

The full suite is **557 tests / 105 suites**, 0 warnings, `** BUILD SUCCEEDED **` /
`** TEST EXECUTE SUCCEEDED **`. See `docs/24-INTERACTIVE-WIDGETS.md`.

### Milestone 16 — Live Session Surface / ActivityKit

The platform-neutral live-session core is exercised deterministically with a `FakeLiveActivityService`
(no ActivityKit runtime, which is unavailable on macOS anyway). 17 suites: `LiveActivityPresentationTests`,
`LiveActivityAttributesTests`, `LiveActivityStateTests`, `LiveActivityMappingTests`,
`LiveActivityLifecycleTests`, `LiveActivityStartTests`, `LiveActivityUpdateTests`,
`LiveActivityPauseResumeTests`, `LiveActivitySkipTests`, `LiveActivityStopTests`,
`LiveActivityCompletionTests`, `LiveActivityRecoveryTests`, `LiveActivityDuplicatePreventionTests`,
`LiveActivityFailureIsolationTests`, `LiveActivityCloudKitIndependenceTests`,
`LiveActivityBoundaryInvariantTests`, `LiveActivityAppIntentRoutingTests`. They cover
content/identity/state mapping, the full lifecycle, launch reconciliation + duplicate prevention
(one activity per `FocusSession.id`), failure isolation (a rejecting/unsupported service never
disturbs the timer; engine behaviour is identical with and without the observer), CloudKit
independence, boundary invariants (no second timer, reuse of the M15 `WidgetControlSet`), and App
Intent routing through the existing `AppIntentSessionActions` seam.

The full suite is now **602 tests / 122 suites**, 0 warnings, clean build (app + widget) succeeds.
**Manual acceptance is not applicable on macOS** (Live Activities are unavailable there) and is not
claimed. See `docs/25-LIVE-ACTIVITIES.md`.

### Milestone 17 — production-readiness hardening

M17 adds a **release gate** and robustness coverage without changing any tested behaviour:

- **`ProductionReadinessTests` + `ProductionReadinessSupport`** — a whole-tree source-boundary audit
  (comments and string literals blanked; identifier-boundary aware so `openTimer(` ≠ `Timer(`):
  V6 schema; a single scheduling authority (`SessionCoordinator`); one `TimerEngine`/`SessionCoordinator`;
  persistence/widget/App-Intent boundaries; **no `import ActivityKit` anywhere**; no production CloudKit
  import; timer core free of `fatalError`/`try!`/`as!`; and a hermetic, detected test host.
- **`StoreMigrationRobustnessTests`** — the rebuild-on-incompatibility upgrade path, hermetically
  (temp stores only): incompatible/corrupt stores rebuilt into a usable V6 store, full-model round-trip
  with no data loss, and `originatingDeviceID` back-compat. Uses the new testable
  `PersistenceController.openOnDiskContainer(schema:configuration:)` seam.
- **`LargeHistoryStressTests`** — pure aggregation over 5,000 and 12,000 intervals with exact totals,
  and `StatisticsRepository` over 1,000 persisted sessions / 4,000 intervals (generous, machine-dependent
  ceilings).
- **`AccessibilityTextTests`** — spoken durations, status/phase labels, and the menu-bar VoiceOver
  description (state carried by text, never a bare `00:00`, no NaN/negative).
- **`KeyboardNavigationAuditTests`** — transport shortcuts + identifiers, setup Cmd+Return + focus, and
  editor default/cancel actions.
- **`AllIntegrationsFailureIsolationTests`** — Calendar + Notifications + Widget failing at once (plus a
  throwing lifecycle observer) while a session runs to completion and Stop preserves history.
- **`TimerBoundaryHardeningTests` / `EmptyStateRobustnessTests`** — remaining never negative, backwards-clock
  safety, boundary skip/stop, 24-hour interval, ten-year sleep gap, empty-history zeros/nil ratios, and a
  deleted-configuration safe label.

The full suite is now **653 tests / 137 suites**, **0 compiler warnings**; both the **Debug** and (validated
as an explicit gate) the **Release** build succeed (widget `.appex` embedded). Schema stays **V6**. The
XCTest host is proven unable to recover or mutate the developer's real session (test-host hermeticity;
ADR-077). See `docs/26-PRODUCTION-READINESS.md`.

## Milestone 20 — iOS Home Screen widgets & local notifications

New iOS suites (`TimeFrameiOSTests`), all deterministic and offline (no real notification center, no
network, no paid team):

- **`IOSHomeScreenWidgetTests`** — `WidgetProjection` JSON round-trip + backward-compatible decode
  (missing additive M14 fields → nil) + defensive unknown-enum decode; corrupt/absent App Group store
  reads nil; `WidgetTimelineBuilder` reloads at the frozen planned end, paused never ticks,
  configuration never affects timing (identical instants/reload across modes), countdown anchors are
  carried frozen; `WidgetControlSet` control routing per state/phase.
- **`IOSNotificationTests`** — UserDefaults preference persistence; deterministic session-namespaced
  identifiers; `NotificationScheduleBuilder` anchoring + per-category suppression + immediate
  completion; full lifecycle via a `FakeNotificationService` + real `SessionCoordinator` (start /
  no-per-tick / pause-resume / skip / stop / completion cleanup / idempotent reconcile / clear-stale /
  **failure isolation** / action routing / disabled).
- **`IOSCompanionUIStateTests`** — empty vs. active statistics snapshots (drive the empty states),
  duration formatting, coordinator active/paused state.
- **`IOSPerformanceTests`** — large history aggregation + long-plan schedule build (generous,
  machine-dependent thresholds).
- **`IOSTestSupport`** — a mock clock, an in-memory notification scheduler, and a wired rig mirroring
  the app.

macOS `ProductionReadinessM20Tests` adds the iOS-widget / notification / UserNotifications-confinement
/ ActivityKit-iOS-only / no-CloudKit / schema-V6 boundary audits; the M17 audit roots were updated for
the notification move into `Core/`. The full macOS suite stays green at 679/144. See
`docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.

## Milestone 21 — iOS Lock Screen, StandBy & accessory widgets

New and extended suites, all deterministic and offline:

- **`IOSLockScreenWidgetTests`** (iOS) — the pure `AccessoryWidgetPresentation` mapper for every family
  (circular / rectangular / inline) × every state (focus / break / paused / idle / completed /
  interrupted / unavailable); configuration isolation (display modes, destination, `showsCountdown`);
  **never a second clock** (the live-countdown anchors equal the projection's frozen anchors; a missing
  or past planned-end degrades to no countdown; paused is clamped, never negative); accessibility
  sentences per state; and a bulk-mapping performance test.
- **`AccessoryWidgetPresentationTests`** (macOS) — the same mapper guarded from the macOS suite (frozen
  anchors, configuration-is-presentation-only, every state safe, malformed degrades).
- **`WidgetProjectionFreshnessTests`** (macOS) — proves widget refreshes are **meaningful-transition-only**:
  sub-second ticks inside an interval perform no projection write, while the auto interval boundary and
  each lifecycle event do; repeated writes never mutate the engine.
- **`ProductionReadinessM21Tests`** (macOS) — boundary audit: the widget extension has no
  SwiftData/CloudKit/notifications/engine construction/scheduling primitive; the mapper is
  Foundation-only; accessory views are read-only (no interactive App Intents); ActivityKit stays iOS-only
  (exactly the three files); App Group + `timeframe://` + schema V6 unchanged.

The full macOS suite is green at **707/152**; the iOS suite is green at **75** tests on both iPhone and
iPad. See `docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md`.

## Milestone 22 — iOS Control Center controls

Deterministic, no WidgetKit host: `ControlCenterPresentationTests` / `ControlCenterRoutingTests` and
`ProductionReadinessM22Tests` (macOS), `IOSControlCenterTests` (iOS). See
`docs/31-CONTROL-CENTER-CONTROLS.md`. Suite green at macOS **749/164**, iOS **90** on both idioms.

## Milestone 23 — Configurable Control Center quick-start

New and extended suites, all deterministic and offline (mock clock, in-memory store, no WidgetKit host):

- **`QuickStartControlTests`** (macOS) — the descriptor/entity, the entity query (order preservation +
  deleted-drop + case-insensitive matching), the App Group catalog store (round-trip, inert suite,
  forward-incompatible schema ignored, distinct key), the app-side `QuickStartCatalogWriter` (publishes
  the repository, drops a deleted configuration), the pure presentation/accessibility, the mutation
  routing (selected configuration / `nil`-default / **rename uses the authoritative name** / projection
  refresh), failure isolation (unavailable router / deleted configuration / already-running), and
  concurrency (2 & 10 rapid taps → exactly one session).
- **`ProductionReadinessM23Tests`** (macOS) — boundary audit: `AppIntentControlConfiguration` (and the
  ControlWidget API) is iOS-only; the shared quick-start layer is Foundation/AppIntents-only and
  clock-free; the catalog reuses the existing App Group; the configurable control constructs no engine,
  schedules no clock, and defines no second seam; `QuickStartCatalogWriter` lives in `Core/`; one router,
  ActivityKit confined to three iOS files, schema **V6**, App Group + deep links unchanged, CloudKit
  disabled.
- **`IOSQuickStartControlTests`** (iOS) — the same shared entity/catalog/presentation and the mutation
  routing proven from the iOS module (iPhone + iPad).

The full macOS suite is green at **789/176**; the iOS suite is green at **101** (iPhone) / **100** (iPad)
tests — the single delta is a pre-existing M21 accessory test; all 11 M23 tests pass on both idioms. App
Intents metadata extraction + `--validate-assistant-intents` succeed. See
`docs/32-CONFIGURABLE-CONTROL-CENTER.md`.

## Milestone 24 additions (2026-08-17)

`ProductionReadinessM24Tests` extends the release-gate audit with product-identity checks (display name
"Time Frame"; macOS + iOS AppIcon assets present and referenced; one logo, no appearance split; bundle
id / App Group / URL scheme / V6 schema unchanged) plus functional coverage of the
`ConfigurationRepository.onChange` catalog-refresh hook and configuration-identity stability. macOS
suite: **808 tests / 181 suites** (was 789/176), 0 warnings. iOS iPhone + iPad suites remain green.
