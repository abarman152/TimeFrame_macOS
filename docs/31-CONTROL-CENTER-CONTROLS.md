# 31 — Control Center Controls (Milestone 22)

Time Frame's iOS **Control Center** controls: one-tap access to the timer from Control Center,
the Lock Screen control tray, and the Action button — built on WidgetKit's `ControlWidget`
(iOS 18+). They are a **command / presentation adapter over the one authoritative timer**, never a
second timer, clock, or store.

> Status: **implemented for iOS**. macOS stays `ControlWidget`-free (the API is iOS-only in this
> SDK). Control Center **GUI/manual verification was not performed** — see §17.
>
> **Milestone 23** adds a fourth, **user-configurable** control (`AppIntentControlConfiguration`) that
> lets the user pick *which* saved timer it starts, reusing this same mutation seam. The three M22
> controls documented here are unchanged. See `docs/32-CONFIGURABLE-CONTROL-CENTER.md`.

## 1. Objective

Give the user a native Control Center surface to start, pause, resume, skip, and stop a Time Frame
session, reusing the **existing Milestone-15 mutation seam** end to end:

```
ControlWidgetButton(action:) → Widget/App Intent → WidgetControlActions
    → AppIntentSessionActions → SessionCoordinator → TimerEngine
```

The Control Center surface **must never** create a `TimerEngine`/`SessionCoordinator`/`FocusSession`,
touch SwiftData/`ModelContext`/CloudKit, maintain its own timer/clock, poll, persist independent
timer state, or duplicate the mutation seam.

## 2. Platform availability

- **iOS/iPadOS 18+.** `ControlWidget`, `StaticControlConfiguration`, `AppIntentControlConfiguration`,
  `ControlWidgetButton`, `ControlWidgetToggle`, and `ControlValueProvider` are all annotated
  `@available(iOS 18.0, macOS 26.0, watchOS 26.0, *)`, `@available(tvOS/visionOS, unavailable)` in
  the iOS 27 SDK. Time Frame's iOS deployment target is **26.0**, so no availability fallback is
  needed.
- **macOS: not used.** Although `ControlWidgetButton` etc. are also marked available on macOS 26,
  Time Frame keeps its Control Center surface iOS-only. The macOS app and the macOS widget stay
  `ControlWidget`-free (enforced by `ProductionReadinessM22Tests.M22ControlWidgetPlatformTests`).
- CloudKit stays intentionally **disabled** on this personal-team build; Control Center works
  entirely independently of it (§14).

## 3. SDK / API verification

Verified directly against the installed **Xcode 27.0 (27A5194q)** / **iOS 27 SDK** module
interfaces before implementing:

| Type | Where | Signature used |
| --- | --- | --- |
| `ControlWidget` | SwiftUI | `protocol ControlWidget { associatedtype Body: ControlWidgetConfiguration; var body }` |
| `StaticControlConfiguration` | WidgetKit | `init(kind:content:)` and `init(kind:provider:content:)` |
| `ControlWidgetButton` | WidgetKit | `init(action: Action, label:)` where `Action: AppIntent` |
| `ControlValueProvider` | WidgetKit | `var previewValue`; `func currentValue() async throws -> Value` |
| `.displayName(_:)` / `.description(_:)` | WidgetKit | `LocalizedStringResource` |
| `.tint(_:)` / `.disabled(_:)` | WidgetKit | on `ControlWidgetTemplate` |

**Key SDK constraint discovered:** `ControlWidgetTemplateBuilder` exposes only `buildExpression` and a
single-content `buildBlock` — **no** `buildEither`/`buildOptional`. A control body therefore cannot
branch to return different `ControlWidgetButton` *intent types*. This shaped the design (§4): state
adaptation is done through the **value provider** (label / symbol / tint / disabled) and a single
adaptive **adapter intent**, not by branching intent types in the body.

## 4. Control architecture

Three `ControlWidget`s live in the **existing** `TimeFrameiOSWidgets` extension
(`ControlCenterWidgets.swift`) — no new app-extension target:

1. **`TimeFramePrimaryControl`** — the adaptive "Time Frame Timer" control. A `ControlValueProvider`
   reads the shared `WidgetProjection` from the App Group and maps it (pure
   `ControlCenterPresentation`) to the primary action's title, SF Symbol, VoiceOver label, and
   "active" tint. Its button performs `TimeFramePrimaryControlIntent`, which the app resolves against
   **live** state.
2. **`TimeFrameStartControl`** — a dedicated Start control. `StaticControlConfiguration` (no provider)
   → reuses the existing **M15** `WidgetStartIntent` directly.
3. **`TimeFrameStopControl`** — a dedicated Stop control. A `ControlValueProvider` reports whether a
   session is active so the control **disables itself** when idle → reuses the existing **M15**
   `WidgetStopIntent` directly.

Two of the three controls reuse Milestone-15 intents verbatim; the primary control adds **one** thin
adapter intent that delegates immediately to the same seam. There is **no second action router**.

## 5. Control list

| Control | Action(s) | Semantics |
| --- | --- | --- |
| Time Frame Timer (primary) | Start / Pause / Resume / Skip | Contextual: Start when idle, Pause a running focus interval, Resume when paused, Skip a running break |
| Start Focus Timer | Start | Always valid (starting while running fails safely) |
| Stop Timer | Stop | Enabled only while a session is active |

The five requested actions (Start, Pause, Resume, Skip, Stop) are all covered; **Restart** is
deliberately not exposed as a Control Center control (it is available on the widget/Live Activity,
where a labelled control row has room).

## 6. App Intent routing

The primary control's action, `TimeFramePrimaryControlIntent`, resolves the app-registered
`@AppDependency WidgetControlActions` router and calls its new `performPrimary()`. App-side
(`WidgetControlRouting`), `performPrimary()`:

1. maps **live** authoritative state with the SAME `WidgetProjectionMapper` the widget reads;
2. derives the situation (`ControlCenterSessionState`) and the action
   (`ControlCenterControlSet.primaryAction(for:)` — the pure, unit-tested decision);
3. performs it through the **same** `perform(_:)` helper the explicit-action handler uses — i.e. the
   one `AppIntentSessionActions` seam — and refreshes the widget projection.

So there is exactly one place a control action mutates the timer, and one decision path shared by the
explicit and adaptive controls.

## 7. State projection

`ControlCenterSessionState` (Foundation-only, `Shared/ControlCenterPresentation.swift`) is derived
purely from the read-only `WidgetProjection` (`state` × `phase`): `idle`, `focusRunning`,
`breakRunning`, `paused`, `completed`, `interrupted`, `unavailable`. It splits `running` into focus
vs break so the primary control offers **Skip** during a break (a break can't be paused — mirroring
the M15 `WidgetControlSet`).

The Control Center surface **computes no elapsed time**: the value provider reads the frozen
projection only. There is **no** `Timer`, `Timer.publish`, `DispatchSourceTimer`, `Task.sleep`,
`asyncAfter`, `CADisplayLink`, or countdown loop anywhere in the control code or the decision layer.

## 8. Error handling

Every control action fails **safely**:

- **Router unregistered** (e.g. an unexpected process): the shared intents resolve the inert
  `WidgetControlActions.unavailable` default and throw `WidgetControlError.unavailable` — a calm
  "Time Frame isn't available right now" message, never a trap.
- **No active session / invalid transition / stale action**: `AppIntentSessionActions` throws the
  closed `TimeFrameIntentError` set (`noActiveSession`, `sessionAlreadyRunning`, `actionFailed`, …),
  which propagates through the shared intent verbatim.
- A failed control action **never** corrupts or resurrects the timer (the engine's own guards make
  off-state pause/resume a no-op; stop/start guards reject invalid transitions). A widget or CloudKit
  failure can never stop the timer (M13/M17/M19/M20 isolation, unchanged).

## 9. Concurrency

All control routing is `@MainActor` and synchronous through the one coordinator, which already
serializes transitions. Rapid repeated commands are safe: `Pause → Pause` stays paused,
`Resume → Resume` stays running, `Start → Start` never creates a second session (the second throws
`sessionAlreadyRunning`), `Stop → Stop` ends once then throws `noActiveSession`. No second
actor/coordinator is introduced. Covered by `ControlCenterConcurrencyTests` /
`IOSControlCenterConcurrencyTests`.

## 10. Projection freshness

The projection path is unchanged and remains the **only** one:

```
SessionCoordinator mutation → WidgetProjectionWriter → App Group → widget/control surface
```

The router refreshes the projection after **every** control action — including `restart()`, which
emits no lifecycle event and relies on the router's explicit refresh (proven by
`ControlCenterProjectionTests.restartRefreshes`). There is **no** Control Center-specific persistence,
no second App Group, and no second projection store.

## 11. Accessibility

Each control renders a text `Label` (not a bare symbol) and carries an explicit `accessibilityLabel`
from `ControlCenterActionCatalog`: "Start Timer", "Pause Focus Timer", "Resume Focus Timer",
"Skip Interval", "Stop Timer". State is never conveyed by colour or glyph alone. The phrasing is
verified in deterministic tests (`ControlCenterAppearanceTests`, `IOSControlCenterAccessibilityTests`).
**No physical VoiceOver device verification was performed** (§17).

## 12. Widget compatibility

M22 adds only new `ControlWidget`s to the existing bundle. The macOS widget, the iOS Home Screen
widget (small/medium/large; Timer/Today/Statistics; interactive controls), the iOS Lock Screen
accessory widgets (circular/rectangular/inline), StandBy (served by the systemSmall/medium families),
and all configuration options (display mode, destination, show/hide countdown) are unchanged. Control
Center configuration is presentation-only and can **never** alter timer timing.

## 13. Live Activity compatibility

Unchanged. ActivityKit stays confined to exactly the three iOS files (`TimeFrameLiveActivityAttributes`,
`ActivityKitLiveActivityService`, `TimeFrameLiveActivity`); macOS/`Core/`/`Shared/` remain
ActivityKit-free. The M15 interactive seam the Live Activity uses is the same one Control Center uses.

## 14. CloudKit limitation

CloudKit remains **intentionally disabled** on the shipping personal-team build
(`CloudKitCapability.entitledInThisBuild == false`). M22 adds no entitlement, no container, and no
sync claim. Control Center reads the **local** App Group projection and mutates the **local** store
via the seam — fully independent of CloudKit. All M19 CloudKit-honesty tests stay green.

## 15. Testing

Deterministic, in-memory, no WidgetKit host, no real session:

- **macOS** (`time_frameTests/`): `ControlCenterPresentationTests` (situation / control set / primary
  action / appearance / accessibility / determinism), `ControlCenterRoutingTests` (mutation seam,
  projection freshness incl. `restart`, failure isolation, concurrency, performance),
  `ProductionReadinessM22Tests` (source-boundary audit).
- **iOS** (`TimeFrameiOSTests/`): `IOSControlCenterTests` (state, accessibility, routing, failure
  isolation, concurrency, configuration independence) — proving the SAME shared code behaves from the
  iOS module.

## 16. Performance

`ControlCenterControlSet` availability/primary derivation is pure enum/array work; a 20 000×
evaluation over every state completes well under the generous test ceiling
(`ControlCenterPerformanceTests`). App-Intent routing reuses the existing seam with no added cost.

## 17. Manual verification

Control Center **GUI/manual verification was not available** in this environment: adding a control to
Control Center and tapping Start/Pause/Resume/Skip/Stop, and observing the on-device result, was
**not** performed. What *was* completed: deterministic action/state/failure/concurrency tests,
clean Debug + Release builds (app + widget `.appex` embedded), App Intents metadata extraction, and
the architectural source-boundary audit. No screenshots or on-device behaviour are claimed.

## 18. Known limitations

- No on-device / GUI verification of the Control Center tiles (§17).
- No physical VoiceOver / Dynamic Type verification of the controls.
- Restart is not a Control Center control (available on the widget/Live Activity).
- Control Center controls are iOS-only; there is no macOS Control Center surface.
- Real CloudKit cross-device sync remains a documented paid-team blocker (unchanged).

## 19. Future extensions

- A `ControlWidgetToggle` (via a `SetValueIntent`) for a true two-state run/pause switch, once a
  toggle reads better than the adaptive button in practice.
- A per-configuration or per-template "quick start" control via `AppIntentControlConfiguration`
  (user-selectable), reusing the existing template/plan entities.
- A macOS Control Center surface, if/when the product decides to ship one (the pure decision layer is
  already platform-neutral).

## Related ADRs

- **ADR-090** — Control Center is a command adapter over the one mutation seam (no second router/timer).
- **ADR-091** — Control state is a projection-only, Foundation-only decision layer (no clock).
- **ADR-092** — Control Center is iOS-only and CloudKit-independent; macOS stays `ControlWidget`-free.

## Milestone 24 validation (2026-08-17)

The M22 Control Center controls were validated (metadata, `displayName`/`description`, routing through
the one `WidgetControlActions → AppIntentSessionActions → SessionCoordinator` seam) at the AUTOMATED /
SIMULATOR level; GUI placement/tap in the Control Center overlay was **not** manually verified in this
environment. See `docs/33-M24-ON-DEVICE-UX-VALIDATION.md` §6.
