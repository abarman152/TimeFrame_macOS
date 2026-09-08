# 32 — Configurable Control Center Quick-Start (Milestone 23)

Milestone 23 adds a **user-configurable** iOS Control Center control that starts a *chosen* saved
timer configuration. It builds directly on the Milestone-22 Control Center surface, adding the one
piece M22 deliberately deferred: `AppIntentControlConfiguration` and a user-selectable quick-start
target.

Like every other Time Frame surface, the configurable control is a **command / presentation adapter
over the one authoritative timer** — never a second timer, clock, store, coordinator, router, or
mutation seam. **No new app-extension target, no new App Group, no schema change (stays V6), no
CloudKit.**

See also: `docs/31-CONTROL-CENTER-CONTROLS.md` (M22 Control Center), `docs/24-INTERACTIVE-WIDGETS.md`
(the M15 mutation seam), `docs/21-APP-INTENTS.md` (App Intents), ADR-093/094/095.

---

## 1. Scope

**In scope**

- One new configurable `ControlWidget` — `TimeFrameQuickStartControl` — in the **existing**
  `TimeFrameiOSWidgets` extension, using `AppIntentControlConfiguration`.
- A user-selectable `QuickStartTimerEntity` (a saved `PomodoroConfiguration`), resolved from an App
  Group catalog snapshot the app publishes.
- A thin quick-start action intent that routes through the **existing** single mutation seam.
- Full failure handling (no selection / deleted / renamed / unavailable / running session / router
  unavailable) and deterministic tests on macOS + iPhone + iPad.

**Out of scope (unchanged)**

- The M22 controls (`TimeFramePrimaryControl`, `TimeFrameStartControl`, `TimeFrameStopControl`).
- macOS (stays ControlWidget-free), ActivityKit (stays confined to its three iOS files), CloudKit
  (stays honestly disabled), the SwiftData schema (stays V6), the App Group, and the `timeframe://`
  deep links.

---

## 2. `AppIntentControlConfiguration` (SDK verified against iPhoneOS 27.0)

The iOS 27 SDK's `WidgetKit.AppIntentControlConfiguration<Configuration, Content>`
(`@available(iOS 18.0, macOS 26.0, watchOS 26.0)`) offers two initializers:

- `init(kind:provider:content:)` — needs an `AppIntentControlValueProvider`; the content closure
  receives `Provider.Value`.
- `init(kind:intent:content:)` — the content closure receives the configured `Configuration`
  **instance** directly.

`Configuration` must conform to `AppIntents.ControlConfigurationIntent` (an `AppIntent` whose
`perform()` returns `Never` — a configuration holder, not a command). `ControlWidgetTemplateBuilder`
exposes only `buildBlock`/`buildExpression` (no `buildEither`/`buildOptional`), so a control body
cannot branch on intent types.

**M23 uses `init(kind:intent:content:)`**: the control shows no live countdown, so no value provider
is needed. The content closure reads the configured intent's selected `timer` (a frozen entity) and
builds one `ControlWidgetButton` — a single expression, so the template builder's lack of branching is
irrelevant.

---

## 3. The configuration entity

`QuickStartTimerEntity` (`Shared/WidgetControlIntents.swift`) is the App Intents representation of a
saved `PomodoroConfiguration`:

- **Stable id** — the configuration's `UUID` (survives rename/edit).
- **`DisplayRepresentation`** — title = the configuration name (e.g. "Deep Work"), subtitle = a short
  summary (e.g. "25 min focus · 4 sessions"). The picker shows meaningful names, never opaque ids.
- **`defaultQuery`** — `QuickStartTimerEntityQuery` (an `EntityStringQuery`).

The entity and its query import **only Foundation + AppIntents** — no SwiftData — so they compile into
the widget extension and resolve in **any** process.

### The App Group catalog (why not SwiftData)

To keep the widget extension SwiftData-free and to make the picker resolve in any process, the entity
query does **not** touch SwiftData. Instead the app publishes a Foundation-only snapshot:

- `QuickStartTimerDescriptor` — `id`, `name`, `focusDuration`, `defaultTotalSessions` (+ a computed
  `subtitle`).
- `QuickStartCatalog` — a versioned list of descriptors.
- `QuickStartCatalogStore` — reads/writes the catalog as JSON in the **same** App Group suite as the
  widget projection (`group.abirbarman.com.time-frame`), under a distinct key
  (`com.time-frame.quickStartCatalog.v1`). Mirrors `WidgetProjectionStore`: every failure isolated and
  non-fatal; a forward-incompatible schema version is ignored on read.
- `QuickStartCatalogWriter` (`Core/Widgets/`) maps the existing `ConfigurationRepository` → catalog and
  writes it. Called at launch on **both** platforms (`time_frameApp` / `TimeFrameiOSApp`), guarded by
  the test-host check. It is app-side only — never compiled into the widget extension, which only
  reads the catalog.

The query's pure cores (`resolve` / `suggested` / `matching`) take a `QuickStartCatalog` and are
unit-tested without any I/O.

---

## 4. The entity query

`QuickStartTimerEntityQuery: EntityStringQuery`:

- `suggestedEntities()` → every saved timer, in catalog order (populates the picker).
- `entities(for:)` → resolves ids, **preserving request order and dropping unknown (deleted) ids**.
- `entities(matching:)` → case-insensitive name filter (typing filters the picker).

Deterministic lookup keyed by the stable id; a deleted configuration simply resolves to nothing.

---

## 5. The quick-start intent

`TimeFrameQuickStartIntent` (`Shared/WidgetControlIntents.swift`) is the action the control's button
runs:

- `@Parameter var timer: QuickStartTimerEntity?` — carries the selected entity as **data** so
  WidgetKit can serialize it against the button.
- `isDiscoverable == false`, `openAppWhenRun == false` — it drives the control only; it never clutters
  Shortcuts.
- `perform()` resolves the app-registered `WidgetControlActions` router (`@AppDependency`) and calls
  `performQuickStart(configurationID: timer?.id)`.

It constructs no `FocusSession`, writes no `ModelContext`, and introduces no timer primitive. When the
router is unregistered (an unexpected process), it fails **safely** with
`WidgetControlError.unavailable`.

---

## 6. Routing architecture — one mutation seam

```
Control Center configured control
  → ControlWidgetButton(action: TimeFrameQuickStartIntent(timer:))
    → (WidgetKit runs the intent in the APP process)
      → WidgetControlActions.performQuickStart(configurationID:)     ← app-registered router
        → AppIntentSessionActions.startSession(configurationID:)     ← the ONE mutation seam (M12)
          → SessionCoordinator.startSession(configuration:)
            → TimerEngine
```

- `WidgetControlActions` (Shared) gains **one** capability, `performQuickStart(configurationID:)`,
  alongside the M15 `handler` and the M22 `primaryHandler`. It remains the **one** router.
- `WidgetControlRouting.makeActions` (Core, app-side) wires that capability to
  `AppIntentSessionActions.startSession(configurationID:)` and refreshes the widget projection after a
  successful start — the same helper the explicit `.start` action uses.
- The selected configuration is resolved by the **authoritative app layer** (the repository behind
  `startSession`), never by the widget extension.

There is **no** `QuickStartCoordinator`, `QuickStartEngine`, or any parallel authority.

---

## 7. Template rename / delete behaviour (ADR-094)

The control stores the **stable id**, never a cached name or duration:

- **Rename** — the id is unchanged; the next tap starts with the **authoritative** new name/duration.
  (Proven: `renameUsesAuthoritativeName` / `renameIsAuthoritative`.)
- **Duration change** — same; nothing is cached, so the latest configuration is always used.
- **Delete** — the id no longer resolves. The picker drops it (query returns nothing); a tap on a
  stale configuration throws `TimeFrameIntentError.configurationUnavailable` and starts **no** phantom
  session. (Proven: `deletedConfigurationFailsSafely`.)
- **No selection** — starts the user's **default** configuration (a safe, documented fallback the app
  validates).

The catalog is refreshed at launch, so a newly created/renamed configuration appears in the picker on
the next launch (see §16, known limitations). The **start action** is always authoritative regardless
of catalog freshness.

---

## 8. Failure handling (Phase 8 matrix)

| Situation | Behaviour |
|---|---|
| No configuration selected | Starts the user's default configuration |
| Selected configuration exists | Starts exactly that configuration |
| Selected configuration deleted | `configurationUnavailable`; timer untouched; no phantom session |
| Selected configuration renamed | Starts with the authoritative new name (id is stable) |
| Selected configuration temporarily unavailable | Query resolves nothing / start throws; fails safely |
| Session already running | `sessionAlreadyRunning`; the SAME session keeps running |
| Session paused / completed / cancelled | Governed by existing `SessionCoordinator` semantics |
| Router unavailable (wrong process) | `WidgetControlError.unavailable`; no crash |
| Action fails | Existing `TimeFrameIntentError`; state unchanged |

A widget or CloudKit failure can never stop or corrupt the timer.

---

## 9. Concurrency

`startSession`'s existing `requireNoActiveSession()` guard makes duplicate starts impossible:

- 2 rapid taps → exactly one session (`twoRapidTaps`).
- 10 rapid taps → exactly one `started` result; the rest throw `sessionAlreadyRunning`
  (`tenRapidTaps`, both macOS and iOS).

No duplicate timers, no duplicate coordinators, no corrupted state.

---

## 10. Accessibility

`QuickStartControlPresentation.content(timerName:)` (pure, Foundation-only) supplies:

- Selected "Deep Work" → title **"Deep Work"**, VoiceOver **"Start Deep Work Timer"**, glyph
  `play.fill`.
- No selection / blank → title **"Start Timer"**, VoiceOver **"Start Focus Timer"**.

Labels are complete spoken phrases — never glyph-only, colour-only, or an opaque id. Covered by
deterministic tests (`QuickStartPresentationTests`, `IOSQuickStartEntityTests/presentation`).

---

## 11. Configuration mutation safety (ADR-094)

The configured control never freezes timing parameters. The authoritative configuration remains the
app's SwiftData model; the control references the stable entity id, and the latest authoritative
configuration is used at tap time. No duration is cached as Control Center state.

---

## 12. Testing

**macOS (`time_frameTests`, +40 tests / +12 suites → 789 / 176):**

- `QuickStartControlTests.swift` — descriptor/entity, query resolution (order + deleted-drop +
  matching), catalog store (round-trip, inert, schema mismatch, distinct key), catalog writer
  (publishes + deleted-drops), presentation/accessibility, routing (selected / nil-default / rename /
  projection refresh), failure isolation (unavailable router / deleted / already-running), concurrency
  (2 & 10 rapid taps).
- `ProductionReadinessM23Tests.swift` — boundary audit (see §13).

**iOS (`TimeFrameiOSTests`, +11 tests):**

- `IOSQuickStartControlTests.swift` — the same shared entity/catalog/presentation and the mutation
  routing proven from the iOS module (iPhone + iPad).

All tests are deterministic (mock clock, in-memory store, no WidgetKit host, no real time).

---

## 13. Boundary audit (`ProductionReadinessM23Tests`)

- `AppIntentControlConfiguration` (and the whole ControlWidget API) is **iOS-only** — absent from
  macOS / `Core/` / `Shared/` / macOS widget; present in `QuickStartControlWidget.swift`.
- The shared quick-start layer imports only Foundation + AppIntents (no WidgetKit/SwiftUI/SwiftData/
  CloudKit/ActivityKit) and introduces no timer primitive.
- The catalog reuses the existing App Group (asserts the store references
  `WidgetProjectionStore.appGroupIdentifier`).
- The configurable control touches no persistence/CloudKit, constructs no engine, schedules no clock,
  and defines no second seam.
- `QuickStartCatalogWriter` lives in `Core/`, never in a widget extension.
- Unchanged invariants: one router (`WidgetControlActions` only in `WidgetControlIntents.swift`),
  ActivityKit confined to its three iOS files, schema V6, App Group + deep links unchanged, CloudKit
  disabled.

---

## 14. iPhone / iPad validation

| Target | Result |
|---|---|
| macOS Debug build | BUILD SUCCEEDED, 0 warnings |
| macOS tests | 789 / 176 passed |
| macOS Release build | BUILD SUCCEEDED, 0 warnings |
| iOS Debug build | BUILD SUCCEEDED, 0 warnings |
| iPhone tests | 101 passed (all 11 M23 tests) |
| iPad tests | 100 passed (all 11 M23 tests) |
| iOS Release build | BUILD SUCCEEDED, 0 warnings |
| App Intents metadata | Extracted + `--validate-assistant-intents` OK; the three M23 intents present in `Metadata.appintents`; the `.appex` embeds/validates |

(The single iPhone/iPad count delta — `IOSAccessoryCircularTests/settledStates()` — is a pre-existing
M21 accessory test unrelated to M23; all 11 M23 tests run and pass on both idioms.)

---

## 15. Manual Control Center verification status

**Not manually verified.** GUI automation of the Control Center configuration UI and on-device tap
behaviour is unavailable in this environment. What *is* verified:

- SDK/API verified against `iPhoneOS27.0.sdk`.
- Debug + Release builds verified (macOS + iOS).
- App Intents metadata extraction + validation verified; M23 intents present in the metadata.
- The configurable-control configuration intent, entity query, and routing verified by automated,
  deterministic tests.
- Simulator (iPhone + iPad) unit/integration tests verified.
- **Not** verified: actual Control Center placement, the configuration picker UI, and on-device tap
  behaviour; physical-device VoiceOver.

No screenshots or device behaviour are fabricated.

---

## 16. CloudKit status

**Unchanged and blocked, exactly as established in Milestone 19.** This is a personal (free) Apple
Developer team, so `CloudKitCapability.entitledInThisBuild == false`; no iCloud entitlement or CloudKit
container is added. M23 depends on nothing CloudKit-related: the configurable control works entirely
from the **local** authoritative configuration/session path and the **local** App Group catalog.

---

## 17. Known limitations

- **Catalog freshness:** the picker catalog is refreshed at app launch. A configuration created or
  renamed while the app is not relaunched appears in the picker only on the next launch. The **start
  action** is always authoritative (it re-resolves the live configuration by id), so a rename/duration
  change always takes effect on tap regardless of picker freshness.
- **Single selectable domain:** the entity represents a saved `PomodoroConfiguration` (a "timer").
  Selecting a `TaskTemplate` or `SessionPlan` from Control Center is deferred (see §18).
- **Manual GUI/device verification** is outstanding (see §15).

---

## 18. Deferred / recommended future work

- Refresh the catalog on configuration mutation (create/update/delete/setDefault) and on scene
  activation, so the picker is fresh without a relaunch.
- Additional selectable domains (start a `TaskTemplate` or `SessionPlan` from Control Center), reusing
  the existing `startTemplate(id:)` / `startPlan(id:)` seams.
- On-device Control Center GUI/VoiceOver validation once a device is available.

## Milestone 24 — event-driven catalog refresh (2026-08-17)

The quick-start picker catalog is no longer published only at launch. `ConfigurationRepository` fires a
neutral `onChange` hook after every configuration mutation; each app wires it to
`QuickStartCatalogWriter.refresh`, so a create/rename/delete is reflected without polling and without a
second store — the App Group catalog remains a projection over the authoritative model (ADR-097). The
tap path is unchanged: the app re-resolves the authoritative configuration by stable id. See
`docs/33-M24-ON-DEVICE-UX-VALIDATION.md` §7–8.
