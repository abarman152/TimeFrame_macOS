# 21 — App Intents, Shortcuts & Siri (Milestone 12)

> **Milestone 22 note.** The iOS **Control Center** controls route through the same
> `AppIntentSessionActions` seam described here. They reuse the Milestone-15 `WidgetStartIntent`/
> `WidgetStopIntent` and add one non-discoverable adapter intent (`TimeFramePrimaryControlIntent`) whose
> `perform()` calls `WidgetControlActions.performPrimary()` — no new mutation path. See
> `docs/31-CONTROL-CENTER-CONTROLS.md`.

Time Frame exposes its core actions to **Shortcuts** and **Siri** through **App Intents**.
This is an *integration surface*, exactly like the Menu Bar (M8) and WidgetKit (M11): it
reads and drives the **one** authoritative `TimerEngine` / `SessionCoordinator` and never
becomes a second timer, a second start path, or a second database.

> **Milestone 18 note.** The entire `Intents/` layer moved into the shared `Core/` group and now
> compiles into **both** the macOS app and the iOS companion — the same intents, entities, and
> `AppIntentSessionActions` seam, with no divergent semantics across platforms. The iOS **Live
> Activity** interactive buttons reuse the **shared** Milestone-15 control intents (`WidgetPauseIntent`
> etc.) → the one `AppIntentSessionActions` seam, run by the system in the app process — no second
> action architecture. See `docs/27-IOS-COMPANION-LIVE-ACTIVITIES.md` §9/§15.

```
App Shortcut / Siri phrase
        │
        ▼
   AppIntent.perform()          ← thin command/query (@MainActor)
        │  @AppDependency
        ▼
AppIntentSessionActions         ← the one place intents "act"
        │
        ├─► SessionCoordinator ──► TimerEngine        (pause/resume/skip/restart/stop/start)
        │        └──► Session/Template/Plan/Config repositories ──► SwiftData
        │
        └─► AppIntentSessionState (read-only projection) ──► AppIntentDialogText (spoken text)
```

Everything App-Intents-specific lives under `time_frame/Intents/`. No file under `Timer/`,
`Services/`, or `Models/` changed for App Intents except two additive, targeted repository
fetches (`template(with:)`, `configuration(with:)`, mirroring the existing `plan(with:)`).

## Architecture (ADR-056 … ADR-059)

- **Thin integration layer (ADR-056).** Each intent resolves its inputs, then calls an
  **existing** coordinator operation via `AppIntentSessionActions`. No intent constructs a
  `FocusSession`, writes to a `ModelContext`, or introduces any timer primitive
  (`Timer`, `Task.sleep`, `asyncAfter`, `scheduledTimer`, a countdown, a decrement).
- **Entities through repositories (ADR-057).** Selectable entities carry a **stable `UUID`**
  and frozen display strings, resolved through the existing repositories; deleted records
  drop out gracefully.
- **Immutable projection (ADR-058).** `AppIntentSessionState` is built from the engine with
  the *same* in-memory timestamp math as `MenuBarPresentationState` and
  `WidgetProjectionMapper` — one truth, three read-only projections. All phrasing lives in
  the pure `AppIntentDialogText`.
- **Dependency injection + existing navigation (ADR-059).** The app registers its one
  `SessionCoordinator` and an `IntentDataProvider` with `AppDependencyManager`; intents/queries
  receive them via `@AppDependency`. Navigation intents reuse the existing `timeframe://`
  deep link.

## Intents implemented (11)

| Intent | Purpose | Routes to |
| --- | --- | --- |
| `StartTimeFrameIntent` | Start a session (task, configuration, session count — all optional; falls back to the default configuration) | `SessionCoordinator.startSession` |
| `StartTemplateIntent` | Start from a `TaskTemplate` | `TaskTemplate → SessionSetupPrefill → startSession` |
| `StartPlanIntent` | Start from a `SessionPlan` | `SessionPlan.executionSnapshot → startPlan` |
| `PauseTimeFrameIntent` | Pause | `SessionCoordinator.pause` |
| `ResumeTimeFrameIntent` | Resume | `SessionCoordinator.resume` |
| `SkipTimeFrameIntervalIntent` | Skip current interval | `SessionCoordinator.skip` |
| `RestartTimeFrameIntervalIntent` | Restart current interval | `SessionCoordinator.restart` |
| `StopTimeFrameIntent` | Stop (preserves history — never a delete) | `SessionCoordinator.stop` |
| `OpenTimeFrameIntent` | Bring the app forward on Timer | `OpenURLIntent(timeframe://timer)` |
| `ShowTimeFrameStatisticsIntent` | Open the Statistics screen | `OpenURLIntent(timeframe://statistics)` |
| `GetCurrentTimeFrameStatusIntent` | Speak the current status | `AppIntentSessionState` → `AppIntentDialogText` |

## Entities (4)

- `TaskTemplateEntity` — id = template UUID; `EntityStringQuery` over `TaskTemplateRepository`.
- `SessionPlanEntity` — id = plan UUID; `EntityStringQuery` over `SessionPlanRepository`.
- `ConfigurationEntity` — id = configuration UUID; `EntityStringQuery` over `ConfigurationRepository`.
- `CurrentSessionEntity` — read-only projection of the live session (fixed `"current"` id),
  `@Property`-exposed fields (task, phase, state, remaining, session number/total,
  configuration, next phase). Exposes **no** control.

Each query has a `@MainActor` static resolution core (`resolve`/`suggested`/`matching`) that
takes the repository explicitly; the `@AppDependency` methods forward to it. This keeps all
query logic unit-testable without the process-global dependency manager (whose values are
only accessible inside a real intent perform flow).

## App Shortcuts (9, curated)

`TimeFrameShortcuts: AppShortcutsProvider` exposes: **Start Time Frame**, **Start Template**
(parameterized), **Start Plan** (parameterized), **Pause**, **Resume**, **Skip Interval**,
**Stop**, **Check Status**, **Open Time Frame**. Every phrase includes the `\(.applicationName)`
token. The list is intentionally small (a guardrail test fails if it grows beyond 12).

## Dialogs & errors

- **Confirmations** come from `AppIntentDialogText` — e.g. *"Started Research Paper using
  Deep Work. Session 1 of 4."*, *"Time Frame is paused."*, *"Skipped the current interval."*
- **Status** — e.g. *"You're focusing on Research Paper. Session 2 of 4. You have 18 minutes
  remaining."*
- **Errors** are the closed `TimeFrameIntentError` set (`CustomLocalizedStringResourceConvertible`),
  which never leak a Swift/SwiftData error, UUID, or stack trace: *"No Time Frame session is
  currently running."*, *"A Time Frame session is already running."*, *"That template is no
  longer available."*, *"The configuration used by this template is no longer available."*, etc.

## Concurrency

Intents and entity construction are `@MainActor` (the coordinator, engine, and SwiftData main
context are main-actor isolated); a `@MainActor async perform()` legally witnesses the
nonisolated `AppIntent.perform()` requirement (async witness). Entity queries stay nonisolated
(so their `init()` satisfies `EntityQuery`) and hop to `MainActor.run` for their work.
`SessionCoordinator` is `@MainActor` (hence `Sendable`) and is injected as an `@AppDependency`.
No `@unchecked Sendable`, detached tasks, or data races are introduced.

## Privacy & safety

- Intents expose only what an action needs; no historical sessions, no cross-session
  aggregation, no configuration internals beyond a name/durations for the picker.
- **Stop** routes through the existing stop operation: it records the in-progress interval as
  cancelled and preserves all completed intervals — it is **not** a delete of history.
- The dependency registration is skipped under the unit-test host, so the live store is never
  advertised to the runner.

## Siri / Shortcuts support & limitations

- **App Intents / Shortcuts:** all 11 intents and 4 entities are discovered by the build's
  App Intents metadata extractor (`Metadata.appintents`, `--validate-assistant-intents`
  passes), so they appear as Shortcuts actions with entity parameter pickers, and the 9 App
  Shortcuts are available with zero user setup.
- **Siri:** the App Shortcut phrases are invokable by voice on a device where Siri is enabled;
  exactly which phrasings Siri matches, and any on-device model behavior, are **runtime/OS**
  concerns not verifiable from a build. Rich conversational/assistant-schema intents are **not**
  adopted this milestone.
- **User configuration:** building custom multi-step Shortcuts (e.g. "Start my Research
  template, then set Do Not Disturb") is done by the user in the Shortcuts app; Time Frame only
  provides the actions and parameters.

## Testing

Deterministic, no Siri/Shortcuts dependency — the intents' logic is driven through
`AppIntentSessionActions` and the query resolution cores against in-memory containers with a
mock clock (heartbeat off). Suites: state projection, dialog text, entities, entity queries,
Start Template / Start Plan / Start Time Frame, timer controls, current status, App Shortcuts,
failure isolation, and a regression pass proving the menu bar and widget projections still read
the one coordinator after an intent acts.

## Persistence / schema

**No schema change — stays V5.** No new persistence store, cache, or UserDefaults suite is
introduced for App Intents.

> **Follow-up (Milestone 13):** iCloud/CloudKit sync is added below the repositories, but App
> Intents are **unchanged**: every intent still resolves its inputs and calls the existing
> `SessionCoordinator` via the one `AppIntentSessionActions` — no intent touches CloudKit or the
> store directly (ADR-060). Regression covered by `CloudPersistenceRegressionTests`. See
> `docs/22-ICLOUD-CLOUDKIT.md`.

> **Follow-up (Milestone 14):** the `ConfigurableWidget` extension point below is now **implemented**.
> A separate `WidgetConfigurationIntent` (`TimeFrameWidgetConfigurationIntent`, in `Shared/`) backs
> the widget's `AppIntentConfiguration`; it is a **configuration** intent with no `perform` side
> effects and is independent of the 11 command/query intents here — it never touches the timer,
> coordinator, or store, and maps its three `AppEnum` choices to a pure `TimeFrameWidgetConfiguration`
> (ADR-064/065). The M12 intents are unchanged. See `docs/23-CONFIGURABLE-WIDGETS.md`.

## Future extension points

- Adopt App Intents assistant schemas / conversational refinement if the OS surface warrants it.
- Expose statistics figures as read-only entities/queries for "how much did I focus today?".
- ~~A `ConfigurableWidget` (App Intents-driven widget configuration) building on M11.~~ **Done in
  Milestone 14** — see `docs/23-CONFIGURABLE-WIDGETS.md`.
- ~~Interactive widget controls (`Button(intent:)`) reusing this action seam.~~ **Done in Milestone
  15** — thin shared `Widget{Pause,Resume,Skip,Restart,Stop,Start}Intent`s delegate through the one
  `AppIntentSessionActions` (they never re-implement its logic); WidgetKit runs them in the app
  process. They are **not** discoverable (`isDiscoverable == false`), so they don't duplicate the M12
  command intents in Shortcuts. See `docs/24-INTERACTIVE-WIDGETS.md`.
- ~~A configurable Control Center control (`AppIntentControlConfiguration`) that starts a chosen saved
  timer.~~ **Done in Milestone 23** — `QuickStartControlConfigurationIntent` (a `ControlConfigurationIntent`)
  carries a selectable `QuickStartTimerEntity` (resolved from an App Group catalog, not SwiftData); the
  thin `TimeFrameQuickStartIntent` routes through `WidgetControlActions.performQuickStart(configurationID:)`
  → **this** seam's `startSession(configurationID:)`. The app re-resolves the authoritative configuration
  by id, so no timer value is cached in the control. Both new intents are `isDiscoverable == false`. See
  `docs/32-CONFIGURABLE-CONTROL-CENTER.md`.

> **Follow-up (Milestone 15):** the interactive widget's controls reuse **this** action layer. The
> Milestone-12 intents here are unchanged; the widget's `Button(intent:)` controls are separate thin
> intents in `Shared/WidgetControlIntents.swift` that route through the same one
> `AppIntentSessionActions` seam via an app-registered `WidgetControlActions` `@AppDependency` (ADR-069).
> No timer logic is duplicated. See `docs/24-INTERACTIVE-WIDGETS.md`.

> **Milestone 16 note.** A Live Activity control surface (on a future iOS/iPadOS target) reuses the
> **exact same** shared `WidgetControlAction`/`WidgetControlActions → AppIntentSessionActions` seam — no
> `LiveActivitySessionActions` is introduced (ADR-074). ActivityKit is unavailable on native macOS, so
> nothing new is added to this layer now. See `docs/25-LIVE-ACTIVITIES.md`.

## Milestone 24 validation (2026-08-17)

M24 added no intents. App Intents metadata for the app and widget targets is generated
(`ExtractAppIntentsMetadata`) and validated (`--validate-assistant-intents`); the M12/M15/M22/M23
intents — including `QuickStartTimerEntity`, `QuickStartControlConfigurationIntent`, and
`TimeFrameQuickStartIntent` — remain discoverable/valid. See `docs/33-M24-ON-DEVICE-UX-VALIDATION.md` §19.
