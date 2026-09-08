# 24 — Interactive WidgetKit Controls (Milestone 15)

> **Milestone 22 note.** The iOS **Control Center** controls (Milestone 22) reuse this exact interactive
> seam: `ControlWidgetButton(action:) → App Intent → WidgetControlActions → AppIntentSessionActions →
> SessionCoordinator`. They add `WidgetControlActions.performPrimary()` and one adapter intent
> (`TimeFramePrimaryControlIntent`) but **no second router or mutation path**. See
> `docs/31-CONTROL-CENTER-CONTROLS.md` and ADR-090.

> **Milestone 21 note.** The iOS Lock Screen accessory widgets are **read-only** (ADR-089): their space
> is too small to present controls safely, so a tap opens the configured `timeframe://` destination and
> the M15 interactive seam (`Button(intent:) → WidgetControlActions → AppIntentSessionActions →
> SessionCoordinator`) stays on the Home Screen widget and the Live Activity — there is still exactly one
> mutation seam. See `docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md`.

Milestone 15 turns the Milestone-14 configurable widget into an **interactive control surface**.
Users press **Pause / Resume / Skip / Restart / Stop / Start** directly on the widget. It stays what
it has always been — a **read-only projection** of the one authoritative `TimerEngine`/
`SessionCoordinator` — and gains buttons that *command* that one timer through the existing App
Intents action seam. No second timer, no widget-local state, no widget persistence (ADR-069…071).

## 1. Principle — one timer, many surfaces, now interactive

```
Button(intent:) → WidgetPause/Resume/Skip/Restart/Stop/StartIntent.perform()
        │  (WidgetKit runs the intent in the APP process)
        ▼
   @AppDependency WidgetControlActions            ← app-registered router
        │
        ▼
   AppIntentSessionActions                        ← the ONE place an intent mutates the timer (M12)
        │
        ├─► SessionCoordinator → TimerEngine → SwiftData / history
        │
        └─► WidgetProjectionWriter → App Group store → WidgetKit reload → new projection rendered
```

The widget owns **no** timer state. Which buttons appear is a **pure** function of the read-only
projection; pressing one runs a thin App Intent that reaches the single coordinator and then lets the
existing writer re-mirror authoritative state back into the widget.

## 2. Why the intent reaches the real timer

The timer authority is an in-memory object in the running app — not a shared database a separate
process can mutate. WidgetKit runs a `Button(intent:)` App Intent in the **app's process** (launching
it in the background if needed), so the intent resolves the app-registered `WidgetControlActions`
router and drives the same coordinator the main window and menu bar use. This is the whole reason the
control intents can be *thin*: they never touch the engine directly.

## 3. Files

### Shared (`Shared/WidgetControlIntents.swift`, compiled into app + widget)

Foundation + AppIntents only — no SwiftUI/WidgetKit/SwiftData/CloudKit, and **no** `TimerEngine`/
`SessionCoordinator`:

- `WidgetControlAction` — the closed set `pause/resume/skip/restart/stop/start`.
- `WidgetControlSet` — the **pure** state→controls decision (ADR-070); the single source the view
  renders from.
- `WidgetControlResult` — a short confirmation string the app supplies.
- `WidgetControlError.unavailable` — the only error this layer raises itself (safe fallback).
- `WidgetControlActions` — the app-owned router (`@AppDependency` value) holding one main-actor
  closure; `.unavailable` is the inert default injected so an unregistered process never traps.
- `WidgetPauseIntent` / `WidgetResumeIntent` / `WidgetSkipIntent` / `WidgetRestartIntent` /
  `WidgetStopIntent` / `WidgetStartIntent` — thin `AppIntent`s (`openAppWhenRun == false`,
  `isDiscoverable == false`) that resolve the router, perform the action, and surface the
  confirmation dialog. This is the **second** shared file that imports `AppIntents` (the first is the
  M14 configuration intent).

### App target

- `time_frame/Intents/WidgetControlRouting.swift` — builds the router's closure, delegating every
  action to the existing **`AppIntentSessionActions`** (the one mutation seam) and calling the widget
  writer's `update()` afterward (ADR-071). Constructs no `FocusSession`, writes no `ModelContext`,
  introduces no timer primitive.
- `time_frame/Intents/IntentDependencies.swift` — `registerWidgetControl(_:)` advertises the router
  to `AppDependencyManager` (skipped under the unit-test host, like the M12 registration).
- `time_frameApp.swift` — on a normal launch, builds the router (wired to the one coordinator + the
  widget writer) and registers it.

### Widget extension (`TimeFrameWidgets/TimeFrameWidgetView.swift`)

- `SessionControlBar` — renders the running/paused control row from `WidgetControlSet`.
- `WidgetControlButton` — one compact `Button(intent:)` (SF Symbol **and** short label — never
  icon-only, never colour-only) with an explicit accessibility label.
- Idle / Completed / Interrupted carry an inline **Start** primary ("Start Timer" / "Start New
  Session"). Today and Statistics modes stay **read-only**.

## 4. Controls per state (ADR-070)

| State | Small | Medium |
|-------|-------|--------|
| Running · focus | Pause, Skip | Pause, Skip, Stop |
| Running · break | Skip, Stop | Skip, Stop |
| Paused | Resume, Stop | Resume, Restart, Stop |
| Idle | Start Timer | Start Timer |
| Completed / Interrupted | Start New Session | Start New Session |
| Unavailable | — | — |

Derived solely from `WidgetSessionState` + `WidgetPhase` (+ family width). Interactive controls appear
in **Timer** display mode only; Today/Statistics remain informational.

## 5. Countdown & timeline (unchanged from M11/M14)

The live countdown is still `Text(timerInterval:)` between the projection's frozen anchors — a
**repaint**, never a widget-owned clock. No `Timer`/`Timer.publish`/`DispatchSourceTimer`/`Task.sleep`/
`asyncAfter`/`scheduledTimer`/decrement is introduced. `showsCountdown == false` still hides the live
text (controls remain). The timeline entries and reload policy come **only** from
`WidgetTimelinePolicy` via `WidgetTimelineBuilder` — the configuration and the new controls never
affect timing.

## 6. Reload strategy (ADR-071)

The projection is produced **only** by the app-side `WidgetProjectionWriter`; the widget never writes
it. Each control action refreshes the projection and reloads **once** on that meaningful transition —
never per second, never a global poll, never on a countdown repaint. Most actions already refresh via
the lifecycle fan-out; the router additionally calls `writer.update()` so `restart` (which emits no
lifecycle event) still yields fresh anchors.

## 7. Failure, concurrency & recovery

- **Unavailable router** → `WidgetControlError.unavailable`, a calm message (never a trap/crash).
- **No active session** → the existing `TimeFrameIntentError.noActiveSession`. **Start while running**
  → `sessionAlreadyRunning`. Raw Swift/SwiftData errors never surface.
- **Invalid transition** (e.g. Resume while running) → a coordinator-guarded no-op.
- **Stale action** against a session that is gone → fails safely and **never resurrects** a session.
- **Repeated/rapid taps** stay safe because the coordinator is the sole authority (second Pause/Resume
  is a no-op; second Stop reports `noActiveSession`). No widget-local lock is added.
- **Recovery**: after relaunch/wake the widget renders the latest valid projection; a stale action
  fails safely; `Start` after completion/stop begins a genuinely new session.

## 8. Accessibility

Every control shows an SF Symbol **and** a short text label (never icon-only) and carries an explicit
accessibility label ("Pause the Time Frame session", "Skip the current interval", "Stop the Time Frame
session", "Resume the Time Frame session", "Restart the current interval", "Start a Time Frame
session"). Destructive intent (Stop) is unambiguous by label and never an icon-only control. Status is
never conveyed by colour alone. The informational block is one combined VoiceOver element; each button
stays individually focusable and actionable.

## 9. Interaction safety (Stop)

Stop is destructive relative to the current run but preserves history (it routes through the existing
stop operation — never a delete). WidgetKit's button model has no standard in-widget confirmation
step, so rather than an awkward custom flow the button is made **unambiguous by label** ("Stop") with
an explicit "Stop the Time Frame session" accessibility label. The action is recoverable in spirit —
a new session is one tap away — and history is retained.

## 10. App Group & CloudKit independence

- **App Group** `group.abirbarman.com.time-frame` — **unchanged**; still the only channel. No second
  App Group, no CloudKit in the widget.
- The full action path works **offline / without iCloud / with CloudKit unavailable / local /
  fallback** persistence: the coordinator is device-local and the widget reads only the local
  projection. A CloudKit problem can never disable widget interaction.

## 11. Compatibility

- Widget `kind` (`"TimeFrameTimerWidget"`), families (`.systemSmall`/`.systemMedium`),
  `AppIntentConfiguration`, all M14 configuration values, and the deep-link behaviour are unchanged —
  existing installed widgets keep working; they simply gain buttons.
- Projection format is unchanged (schema version 1, same key); the SwiftData schema stays **V6**.
- The M12 command intents and M13 CloudKit architecture are untouched; Calendar, Notifications, Menu
  Bar, and Statistics are unaffected.

## 12. Testing

Deterministic, no WidgetKit host / Siri / iCloud (`time_frameTests/Widgets/`):

- `InteractiveWidgetActionTests` — Start/Pause/Resume/Skip/Restart/Stop drive the coordinator and the
  store reflects the new state; reloads happen on meaningful actions.
- `InteractiveWidgetStateTests` — the exact controls per state/phase on small and medium.
- `InteractiveWidgetConfigurationTests` — control availability ignores configuration; timing stays
  config-invariant.
- `InteractiveWidgetFailureTests` — unavailable router, no-active-session, double start, stale action,
  invalid transition all fail safely.
- `InteractiveWidgetConcurrencyTests` — repeated Pause/Resume/Stop and mixed sequences keep the
  coordinator authoritative.
- `InteractiveWidgetRecoveryTests` — start-after-completion/stop, running/paused projection coherence.
- `InteractiveWidgetCloudKitIndependenceTests` — the full flow over a local store, no CloudKit.
- `InteractiveWidgetProjectionTests` — store equals the mapper's authoritative view; restart refreshes
  anchors; no per-tick reload.
- `InteractiveWidgetBoundaryTests` — static audit: the shared control file and widget own no
  timer/persistence/CloudKit/domain, and the router delegates through the one `AppIntentSessionActions`
  seam.

Plus the existing M11/M14 widget suites still pass unchanged.

## 13. App Intents metadata

The widget extension's `ExtractAppIntentsMetadata` step (`--validate-assistant-intents`) discovers all
six widget-control intents (`WidgetPauseIntent`, `WidgetResumeIntent`, `WidgetSkipIntent`,
`WidgetRestartIntent`, `WidgetStopIntent`, `WidgetStartIntent`) with `isDiscoverable == false`,
alongside the unchanged `TimeFrameWidgetConfigurationIntent`. The app target's M12 intents remain
discovered. No `.pbxproj` build-phase change was needed for metadata; the one new `Shared/` file was
added to both targets' Sources phases (explicit membership, as `Shared/` is not a synchronized group).

## 14. Manual verification limitations

**Manual interactive-widget verification was not performed.** No GUI/widget-gallery automation is
available in this environment, and the widget surface is a macOS system surface. The action routing,
state→controls mapping, failure/concurrency/recovery behaviour, boundary, projection flow, and CloudKit
independence are covered by deterministic tests and a built-metadata check instead. On-device
placement, tapping the buttons in the gallery, and Siri/Shortcuts voice behaviour remain runtime/OS
concerns not verifiable from a build.

## 15. Deliberately out of scope

No Lock Screen accessories, no Control Center controls, no `Toggle(isOn:intent:)` (the controls are
momentary commands, not bistable toggles), and no confirmation dialogs from widget actions.
`.systemSmall`/`.systemMedium` only (unchanged). CloudKit production sync remains unverified
(M13 constraint).

**Live Activities** were investigated in **Milestone 16** and found **unavailable on native macOS**
(ActivityKit is `@available(macOS, unavailable)` — Mac Catalyst-only in the macOS SDK). The reusable
platform-neutral live-session core is built and tested, and a Live Activity control surface would reuse
this milestone's shared `WidgetControlAction`/`WidgetControlActions` seam verbatim — but no Live
Activity is shipped on macOS. See `docs/25-LIVE-ACTIVITIES.md`.

> **Follow-up (Milestone 20):** the **iOS Home Screen widget** reuses this milestone's interactive
> seam **verbatim** — the same shared `WidgetControlSet` (state → controls), the same
> `Widget{Pause,Resume,Skip,Restart,Stop,Start}Intent`s, and the same
> `Button(intent:) → WidgetControlActions → AppIntentSessionActions → SessionCoordinator` chain (the
> iOS app registers the router exactly as macOS does). Timer-mode controls only; Today/Statistics stay
> read-only. No new action path, no second coordinator. See `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.

## Milestone 24 validation (2026-08-17)

The interactive widget controls were validated (not rewritten): the countdown stays a
`Text(timerInterval:)` repaint and every control still routes through the one M15 seam. Covered by the
existing macOS + iOS suites. See `docs/33-M24-ON-DEVICE-UX-VALIDATION.md` §9.
