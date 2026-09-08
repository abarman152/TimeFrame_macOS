# 30 — iOS Lock Screen, StandBy & Accessory Widgets (Milestone 21)

> **Milestone 22 note.** iOS **Control Center** controls (`ControlWidget`, iOS 18+) were added in the
> same `TimeFrameiOSWidgets` extension as a command surface over the one timer — no new appex, no schema
> change, still one mutation seam. See `docs/31-CONTROL-CENTER-CONTROLS.md`.

Time Frame's WidgetKit experience expands from the Home Screen to Apple's other
system surfaces: **Lock Screen accessory widgets** (circular, rectangular, inline)
and **StandBy**. Like every other widget surface, these are **read-only
projections** of the one authoritative timer — they can never become a second
clock (ADR-087). See also `docs/20-WIDGETKIT.md`, `docs/23-CONFIGURABLE-WIDGETS.md`,
`docs/24-INTERACTIVE-WIDGETS.md`, and `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.

## 1. Principle — one timer, more surfaces

There is still exactly **one** source of truth and **one** projection pipeline:

```
TimerEngine → SessionCoordinator → WidgetProjectionWriter → App Group store
   → HomeScreenWidgetProvider → WidgetTimelineBuilder → { Home Screen · Lock Screen } widgets
```

The Lock Screen widget reuses **all** of it. It adds no writer, no store, no
configuration system, no schema, and no widget extension. The live countdown
"ticks" only because SwiftUI's `Text(timerInterval:)` / `ProgressView(timerInterval:)`
animate between the projection's **frozen** `intervalStartedAt` / `intervalPlannedEndAt`
anchors; the paused reading is the frozen `pausedRemainingSeconds`. Nothing here
runs a `Timer`, a publisher, `Task.sleep`, `asyncAfter`, or a decrement.

## 2. Supported families

Declared by `TimeFrameLockScreenWidget` (`kind = "TimeFrameLockScreenWidget"`) in
the **existing** `TimeFrameiOSWidgets` extension:

| Family | Content |
| --- | --- |
| `.accessoryCircular` | Running: a live countdown ring (`ProgressView(timerInterval:)`) with the phase glyph. Paused: pause glyph + frozen `mm:ss`. Idle/complete/interrupted: a glyph + tiny word. |
| `.accessoryRectangular` | Header (phase + interval badge `2/4`), a prominent live/frozen countdown or status line, and a detail line (task or today summary). |
| `.accessoryInline` | One line: `Focus · 24:31`, `Break · 4:52`, `Paused · 18:21`, or `Ready to focus`. |

The Home Screen widget (`TimeFrameHomeScreenWidget`, small/medium/large) is
**unchanged** and lives in the same extension alongside the Live Activity.

## 3. Architecture — files

### Shared, pure (`Shared/`, compiled into all app + widget targets)

- `AccessoryWidgetPresentation.swift` — the **pure** mapper (ADR-088). Given
  `(WidgetProjection, TimeFrameWidgetConfiguration, now)` it returns per-family
  presentation values: SF Symbol, short/long text, whether a live/frozen/no
  countdown applies (and between which frozen anchors), and a single spoken
  accessibility sentence. **Foundation-only** — it imports no WidgetKit, SwiftUI,
  AppIntents, ActivityKit, or SwiftData, and uses its own neutral
  `AccessoryWidgetFamily` / `AccessoryCountdown` vocabulary so the view maps
  WidgetKit's `WidgetFamily` at the boundary. Trivially unit-testable without a
  WidgetKit host.

### iOS widget extension (`TimeFrameiOSWidgets/`)

- `LockScreenWidget.swift` — the `TimeFrameLockScreenWidget` (`AppIntentConfiguration`,
  the accessory families) + deterministic previews. Reuses `HomeScreenWidgetProvider`,
  `HomeScreenWidgetEntry`, and the shared `TimeFrameWidgetConfigurationIntent`.
- `LockScreenWidgetViews.swift` — the SwiftUI accessory views (circular /
  rectangular / inline). Renders from the mapper + WidgetKit date-relative text.

## 4. StandBy

**StandBy is not a separate WidgetKit API.** On iOS, StandBy re-presents the
existing **`.systemSmall` / `.systemMedium`** Home Screen widgets full-screen (and,
at night, in a dimmed/tinted mode). Time Frame therefore serves StandBy with the
**existing** system-family Timer widget, which is already glanceable — phase word,
countdown, and interval progress — and already background-agnostic
(`.containerBackground(for: .widget) { Color.clear }`), so it reads well when
dimmed. No new surface, view, or projection is introduced for StandBy; the content
priority (1: phase, 2: remaining time, 3: task/configuration, 4: progress) is what
the systemSmall/medium Timer mode already presents.

## 5. Configuration

The Lock Screen widget reuses the **same** `TimeFrameWidgetConfigurationIntent`
(`AppIntentConfiguration`) as the Home Screen and macOS widgets — one configuration
system across every surface. `displayMode` (Timer / Today / Statistics),
`destination` (Timer / Today / Statistics / History), and `showsCountdown` all
apply and are **presentation-only** (ADR-064/087):

- Timer mode shows the session; Today/Statistics show a compact daily glance built
  from the same additive projection fields (`completedFocusIntervalsToday`,
  `focusTrendToday`) the Home Screen widget uses.
- Where a parameter is unsuitable for a tiny family (e.g. a task name in circular),
  the **presentation** degrades information density — it never forks the projection
  or persistence.
- A configuration change can never mutate `FocusSession`, `SessionInterval`,
  `TimerEngine`, `SessionCoordinator`, SwiftData, notifications, or the Live Activity.
  `WidgetTimelineBuilder` proves the entry instants and reload policy come from the
  projection alone, never the configuration.

## 6. Interactive controls

Accessory families are **read-only** (ADR-089). A tap opens the configured
`timeframe://` destination via `.widgetURL`. WidgetKit permits `Button(intent:)` on
Lock Screen widgets, but accessory space is too small to present and label controls
safely, and adding one would risk the single-mutation-seam invariant. The
Milestone-15 interactive seam
(`Button(intent:) → WidgetControlActions → AppIntentSessionActions → SessionCoordinator`)
stays on the **Home Screen widget** and the **Live Activity**, where controls fit —
so there remains exactly one mutation seam. A source audit fails the build if an
accessory view ever imports AppIntents or references a widget control intent.

## 7. Live Activity coexistence

The Live Activity (Lock Screen banner + Dynamic Island) is a **separate** surface
in the same extension. The accessory widget does not replace it, does not own its
state, and does not import ActivityKit. Both surfaces read the same authoritative
session (the Live Activity via the M16 `TimeFrameLiveActivityContent`, the widgets
via `WidgetProjection`); there is no duplicate timer. ActivityKit stays confined to
exactly three iOS files (attributes, adapter, Live Activity UI); macOS / `Core/` /
`Shared/` remain ActivityKit-free.

## 8. Accessibility

Every accessory family combines into a **single** VoiceOver element whose spoken
label is produced by the mapper — state is never conveyed by symbol or colour alone
(accessory families render in the system's vibrant/monochrome mode regardless):

- Focus: *"Focus, Project Alpha, 24 minutes 31 seconds remaining, focus 2 of 4"*
- Paused: *"Paused, Project Alpha, 18 minutes remaining"*
- Break: *"Short Break, 4 minutes 52 seconds remaining"*
- Idle: *"Time Frame, ready to focus"*

The live countdown carries `.accessibilityAddTraits(.updatesFrequently)`;
decorative glyphs are folded into the combined element (no duplicate labels); the
circular ring's progress is labelled by the same combined sentence, not by a bare
percentage.

## 9. Dynamic Type

Accessory families have strict space budgets, so text uses **system styles**
(`.caption`, `.title3`, `.caption2`) with `minimumScaleFactor` and intentional
`lineLimit`, and the layouts carry no hard-coded frames that would clip at
accessibility sizes. It is acceptable for a tiny family to drop **secondary**
information at the largest sizes (e.g. the rectangular detail line, or the circular
short word) as long as the **primary** state — phase and remaining time — stays
legible.

## 10. Malformed / stale projections

The mapper degrades every bad input to a safe, non-negative presentation and never
fabricates an active session:

- missing / corrupt payload, or App Group unavailable → the provider substitutes
  `.unavailable`, which maps to a neutral "Time Frame" glyph/line;
- unknown enum raw values → decoded defensively (`.unavailable` / `.none`);
- running without a valid `intervalPlannedEndAt`, or an already-past end → **no**
  live countdown (a calm word instead), never a negative duration;
- paused without / with a negative `pausedRemainingSeconds` → clamped to `0`.

## 11. Projection freshness

Widget surfaces refresh on **meaningful transitions only** — start, pause, resume,
skip, restart, stop, completion, recovery, and auto interval-advance — never on a
per-second tick. `WidgetProjectionWriter` observes the lifecycle fan-out plus
`SessionCoordinator.onMeaningfulTransition` (fired only where `reconcileIfChanged()`
already writes). `WidgetProjectionFreshnessTests` proves sub-second ticks inside an
interval cause **no** projection write/reload, while the auto boundary and each
lifecycle event do — and that repeated writes never mutate the engine.

## 12. Performance

Accessory presentation mapping and timeline construction are O(1) per render and
carry generous, machine-dependent test ceilings (`IOSAccessoryPerformanceTests`,
`IOSPerformanceTests`, `WidgetProjectionPerformanceTests`): mapping 10k accessory
presentations and aggregating 5k history intervals both stay comfortably
sub-second. Thresholds guard against pathological (quadratic) regressions, not a
specific wall-clock budget.

## 13. Testing

- **iOS** (`IOSLockScreenWidgetTests`): circular / rectangular / inline for focus,
  break, paused, idle, completed, interrupted; config isolation (display modes,
  destination, countdown visibility); frozen-anchor / no-second-clock; malformed &
  stale handling (missing end, past end, negative/nil paused, unavailable);
  accessibility sentences; and a bulk-mapping performance test.
- **macOS** (`AccessoryWidgetPresentationTests`): the same mapper guarded from the
  macOS suite (frozen anchors, config-is-presentation-only, every state safe,
  malformed degrades).
- **Freshness** (`WidgetProjectionFreshnessTests`): meaningful-transition-only
  writes.
- **Boundary audit** (`ProductionReadinessM21Tests`): the accessory additions keep
  every M17/M19/M20 invariant (no SwiftData / CloudKit / notifications / engine
  construction / scheduling primitive in the widget extension; the mapper is
  Foundation-only; accessory views are read-only; ActivityKit iOS-only; App Group +
  deep-link scheme unchanged; schema V6).

## 14. Manual / simulator verification

Automated build/test verification (macOS + iPhone + iPad, Debug + Release, 0
warnings) is complete. **Widget-gallery visual verification (adding a Lock Screen
accessory widget, StandBy) was NOT performed** — the simulator's system
widget-gallery / Lock Screen editor / StandBy UI is not scriptable from this
environment — and **physical-device verification was NOT performed**. The widget
previews (`#Preview` in `LockScreenWidget.swift`) render each family/state
deterministically for Xcode-canvas inspection.

## 15. CloudKit — intentionally excluded

M21 adds **no** CloudKit dependency and requires **no** paid Apple Developer
account. `CloudKitCapability.entitledInThisBuild` stays `false`; no entitlement or
container is added; the store still degrades safely to local. The widget reads only
the **local** App Group projection. See `docs/28-CLOUDKIT-DEVICE-VALIDATION.md`.

## 16. What did NOT change

- The SwiftData schema stays **V6** (no widget/accessory/StandBy models).
- The App Group (`group.abirbarman.com.time-frame`), the `WidgetProjection` format
  (still `v1`), the `timeframe://` deep-link scheme, and the
  `TimeFrameWidgetConfigurationIntent` are all unchanged.
- The Home Screen widget, the Live Activity, notifications, App Intents, and
  `TimerEngine` / `SessionCoordinator` are behaviourally unchanged.

## Milestone 24 validation (2026-08-17)

The Lock Screen accessory widgets and StandBy (served by the unchanged systemSmall/medium families)
were validated against the existing suites — read-only projections over the one timer, no change. See
`docs/33-M24-ON-DEVICE-UX-VALIDATION.md` §10–11.
