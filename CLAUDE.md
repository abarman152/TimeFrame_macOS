# CLAUDE.md — Time Frame Project Constitution

Concise operating rules for anyone (human or AI) working on Time Frame. Read
this first, then the relevant document under `docs/`.

## Product

Time Frame is a **native macOS 27 Pomodoro and productivity application**. It is
a native macOS app, not a multiplatform app. The current foundation delivers a
correct, testable timer core; the polished UI and integrations come in later
milestones.

## Technology

- **Swift** + **SwiftUI** (presentation), **SwiftData** (persistence),
  **Observation** (state), **Swift Testing** (tests), modern Swift concurrency.
- Native Apple frameworks only. **Avoid third-party dependencies** unless there
  is a strong technical reason.
- Target: **macOS 27** only. Do not add back-deployment abstractions unless an
  Apple framework forces it.

## Architecture principles

- SwiftUI for presentation only. **Domain logic must not live inside views.**
- SwiftData for persistence.
- The **timer engine is independent of SwiftUI** and testable without launching
  the UI. It derives time from an injected clock, never from a per-second UI
  callback.
- **Calendar/EventKit integration is isolated behind a service** (implemented in
  Milestone 6; ADR-032/035). `EventKitCalendarService` is the **only** file importing
  EventKit; `TimerEngine` and the core domain import none of it. `SessionCoordinator`
  emits pure `SessionLifecycleEvent`s that `CalendarCoordinator` subscribes to, and a
  Calendar failure can never stop or corrupt a timer. Calendar settings/associations
  persist in `UserDefaults`, not SwiftData (ADR-037). See
  `docs/15-CALENDAR-INTEGRATION.md`.
- **Notification integration is isolated behind a service** (implemented in Milestone 7;
  ADR-038/042). `UserNotificationService` is the **only** file importing UserNotifications;
  `TimerEngine`, `SessionCoordinator`, and the core domain import none of it.
  `NotificationCoordinator` subscribes to the **same** `SessionLifecycleEvent` seam as
  Calendar (the app fans one event out to both), and the two integrations are independent —
  they never call each other. A notification failure can never stop or corrupt a timer, and
  notification actions route back through `SessionCoordinator`, never mutating the engine
  directly (ADR-043). Notifications are scheduled only for meaningful transitions, never on
  a timer tick (ADR-040). Preferences persist in `UserDefaults`, not SwiftData (ADR-044).
  See `docs/16-NOTIFICATIONS.md`.
- **The Menu Bar is a presentation/control surface, not a second timer** (implemented in
  Milestone 8; ADR-045/046/047/049). There is exactly **one** `SessionCoordinator` and one
  `TimerEngine`, owned by `time_frameApp` and shared by the main window **and** the
  `MenuBarExtra`. `MenuBarCoordinator` is an `@Observable` observer/adapter over that one
  coordinator: it exposes a pure `MenuBarPresentationState` projection and routes every
  control (Pause/Resume/Skip/Stop/Restart) back through `SessionCoordinator` — it never owns
  timer state, decrements no counter, and persists nothing timer-related. The live countdown
  is a `TimelineView` **repaint** of `TimerEngine.remaining` (repaint only, never a clock).
  Visibility persists in `UserDefaults` (ADR-048); the schema stays **V5**. The menu bar
  observes the same lifecycle state as Calendar and Notifications and is independent of both.
  See `docs/17-MENU-BAR.md`.
- **The Liquid Glass visual identity is a presentation-layer concern only** (implemented in
  Milestone 9; ADR-050/051/052/053). The `Support/DesignSystem/` tokens (`TimeFrameDesign`,
  `TimeFrameGlass`) and the `Views/` tree carry all styling; **no file under `Timer/`,
  `Services/`, or `Models/` may change for a purely visual reason**, and the design system
  imports none of the domain. **Visual components must not contain domain timing logic** — the
  countdown is always a `contentTransition`/`TimelineView` *repaint* of the engine's derived
  `remaining`, never a counter, and no new `Timer`/`Task.sleep`/`asyncAfter`/decrement is
  introduced for presentation. Glass (native macOS 27 `glassEffect`/`GlassEffectContainer`/
  `.glass`/`.glassProminent`, no availability fallback) is used **selectively** for
  control/primary surfaces; ordinary content stays quiet (`tfQuietSurface`). Semantic colour
  comes only from `TFPalette` (system colours/accent), always paired with a label/icon.
  Animation goes through the Reduce-Motion-aware `tfAnimation`. The schema stays **V5**; the
  full test suite stays green. See `docs/18-LIQUID-GLASS-DESIGN.md`.
- **Statistics are a read-only projection of persisted history** (implemented in Milestone 10;
  ADR-054). The `Statistics/` value types (`SessionStatInput`/`IntervalStatInput`,
  `StatisticsPeriod`/`StatisticsDateRange`, `StatisticsSnapshot`, `StatisticsAggregator`) are
  pure and `Sendable`; a `@MainActor` `StatisticsRepository` performs a **single** fetch and
  maps `FocusSession`→`SessionStatInput`, and the `nonisolated` aggregator deterministically
  derives an immutable `StatisticsSnapshot` from those values, a `StatisticsDateRange`, and the
  user's `Calendar`. The statistics layer **never mutates** `TimerEngine`, `SessionCoordinator`,
  `FocusSession`, `SessionInterval`, a configuration, template, or plan, and adds **no second
  timer, no clock (no `Timer`/`TimelineView`/`Task.sleep`/decrement), and no second database**.
  Nothing derived is persisted — snapshots are recomputed from history and are reproducible.
  Session-level metrics attribute by `startedAt`; interval-level metrics by a **completed**
  interval's end instant; configuration grouping uses the **frozen** name (survives
  rename/delete). `TodayView` uses the **same** aggregator over `.today` (one implementation).
  The schema stays **V5** (no change). See `docs/19-STATISTICS.md`.
- **WidgetKit surfaces are a read-only projection, not a second timer** (implemented in
  Milestone 11; ADR-055). There is still exactly **one** `TimerEngine`/`SessionCoordinator`.
  A `WidgetProjectionWriter` observes the **same** `SessionLifecycleEvent` seam as
  Calendar/Notifications (plus the additive, non-semantic `SessionCoordinator.onMeaningfulTransition`
  hook fired only where `reconcileIfChanged()` already writes — never per-tick), maps
  authoritative state to an immutable `WidgetProjection`, and writes it to an **App Group**
  `UserDefaults` suite (`group.abirbarman.com.time-frame`) that the `TimeFrameWidgets`
  app-extension reads. The widget extension imports **no** SwiftData and no app model layer,
  never instantiates `TimerEngine`/`SessionCoordinator`, and creates **no** `Timer`/timer
  publisher/`DispatchSourceTimer`/async countdown loop — the live countdown is
  `Text(timerInterval:)` between the projection's frozen anchors (a repaint, like the menu
  bar). The pure projection value types in `Support`-style `Shared/` compile into **both**
  the app and the widget; deep links use a neutral `timeframe://…` scheme mapped to the
  **existing** `AppSection`s. `StaticConfiguration` only (no App Intents this milestone); the
  schema stays **V5**. See `docs/20-WIDGETKIT.md`.
- **App Intents are a thin integration layer, not a second timer** (implemented in Milestone 12;
  ADR-056/057/058/059). Every intent under `Intents/` resolves its inputs and then calls an
  **existing** `SessionCoordinator` operation via the one `@MainActor AppIntentSessionActions`
  — no intent constructs a `FocusSession`, writes a `ModelContext`, or introduces any timer
  primitive (`Timer`/`Task.sleep`/`asyncAfter`/`scheduledTimer`/countdown/decrement). There
  remains exactly **one** `TimerEngine` and **one** `SessionCoordinator`. Selectable entities
  (`TaskTemplateEntity`/`SessionPlanEntity`/`ConfigurationEntity`) carry a **stable `UUID`** and
  resolve through the **existing** repositories; the read-only `CurrentSessionEntity` and
  `GetCurrentTimeFrameStatusIntent` project authoritative state through the pure, immutable
  `AppIntentSessionState` (same in-memory math as the menu bar/widget) with all phrasing in
  `AppIntentDialogText`. The app registers its one coordinator + an `IntentDataProvider` with
  `AppDependencyManager` (`@AppDependency`); navigation intents reuse the existing `timeframe://`
  deep link. Start-from-template keeps the chain `TaskTemplate → SessionSetupPrefill →
  startSession`; start-from-plan uses `SessionPlan.executionSnapshot → startPlan`. Errors are the
  closed `TimeFrameIntentError` set (never a leaked Swift/SwiftData error/UUID). The schema stays
  **V5**. See `docs/21-APP-INTENTS.md`.
- **iCloud/CloudKit sync is a persistence transport, not timer authority** (implemented in
  Milestone 13; ADR-060/061/062/063). Sync is **SwiftData's native mirroring**
  (`ModelConfiguration(cloudKitDatabase: .automatic)`) below the repositories — **no file imports
  CloudKit** (no `CKRecord`/`CKContainer`, no custom sync engine, no polling). `TimerEngine`/
  `SessionCoordinator` are unchanged and CloudKit-free (ADR-060). Schema bumped **V5 → V6**: the
  only change is removing `#Unique` from all six models (CloudKit rejects uniqueness constraints)
  plus an additive optional `FocusSession.originatingDeviceID` (ADR-061). `PersistenceController`
  resolves an explicit `PersistenceMode` (`local`/`cloudKit`/`fallback`) and **degrades safely to
  the preserved local store** on any CloudKit failure — never an empty in-memory store, never
  blocking the timer (ADR-062). Timer execution is **device-local**: `fetchRecoverableSession`
  only recovers sessions started on *this* device, so a synced running session never starts a
  second timer or is mutated cross-device; historical/frozen fields stay frozen (ADR-063). The
  iCloud Settings section reads a pure `CloudSyncPresentationState` projection. WidgetKit still
  reads the **local App Group** projection and App Intents still route through `SessionCoordinator`
  — both unaffected. **Manual step:** enabling real sync needs a paid Apple Developer team + the
  iCloud entitlement/container (a personal team cannot); CloudKit production sync is **not**
  verified. See `docs/22-ICLOUD-CLOUDKIT.md`.
- **The configurable widget is presentation configuration, not timer state** (implemented in
  Milestone 14; ADR-064/065/066/067/068). The M11 widget becomes **user-configurable** via
  **`AppIntentConfiguration`** (the `StaticConfiguration` is replaced; the provider becomes an
  `AppIntentTimelineProvider`), keeping the **same** widget `kind` (`"TimeFrameTimerWidget"`),
  families (`.systemSmall`/`.systemMedium`), and App Group. A pure, Foundation-only
  `TimeFrameWidgetConfiguration` (`displayMode` ∈ timer/today/statistics, `destination` ∈
  timer/today/statistics/history, `showsCountdown`) selects **presentation only**: the pure
  `WidgetTimelineBuilder` derives entries + reload from the **projection's state alone**, so a
  config change can **never** alter timing or introduce a second clock. The
  `TimeFrameWidgetConfigurationIntent` (`WidgetConfigurationIntent` + three `AppEnum`s, in
  `Shared/` — the **only** shared file importing `AppIntents`) is owned and persisted by **WidgetKit**;
  the app persists **nothing** for widget config (no UserDefaults, no SwiftData). Two **additive
  optional** `WidgetProjection` fields (`completedFocusIntervalsToday`, `focusTrendToday`) feed the
  Today/Statistics modes with **no schema-version bump** (projection stays `v1`) — the trend is
  computed by the app from the **same** `StatisticsAggregator` the dashboard uses (the widget never
  aggregates). The widget stays **read-only** and **CloudKit-independent** (reads only the local App
  Group projection; imports no SwiftData/CloudKit/`TimerEngine`/`SessionCoordinator`). Taps reuse the
  existing `timeframe://` deep links → `AppSection`. The SwiftData schema stays **V6**. See
  `docs/23-CONFIGURABLE-WIDGETS.md`.
- **Interactive widget controls are command surfaces, not a second timer** (implemented in
  Milestone 15; ADR-069/070/071). The configurable widget gains `Button(intent:)` controls
  (Pause/Resume/Skip/Restart/Stop/Start). Each is a thin `AppIntent` in
  `Shared/WidgetControlIntents.swift` (compiled into **both** targets so the widget can reference it —
  the **second** shared file importing `AppIntents`) that owns **no** domain: it resolves an
  `@AppDependency` **`WidgetControlActions`** router and calls it. WidgetKit runs a widget-button
  intent in the **app process**, where the app registered a router wired to the existing Milestone-12
  **`AppIntentSessionActions`** — the **one** place an intent mutates the timer. So the chain is
  `Button(intent:) → WidgetControlActions → AppIntentSessionActions → SessionCoordinator → TimerEngine`,
  with exactly **one** `TimerEngine`/`SessionCoordinator`. The widget still owns no timer state,
  decrements nothing, and writes nothing: which controls appear is a **pure** `WidgetControlSet`
  projection of `WidgetSessionState`/`WidgetPhase` (interactive controls in **Timer** mode only;
  Today/Statistics stay read-only), the countdown stays a `Text(timerInterval:)` repaint (no new
  `Timer`/`Task.sleep`/`asyncAfter`/decrement), and the projection is still produced only by
  `WidgetProjectionWriter` (the router calls `update()` after each action so `restart` — which emits no
  lifecycle event — still refreshes; a **targeted** reload on a meaningful transition, never per tick).
  Actions fail safely (unavailable router / no session / already running / invalid transition / stale
  action) via the existing `TimeFrameIntentError`, never resurrecting a session or crashing; a widget or
  CloudKit failure can never stop or corrupt the timer. The widget `kind`, families,
  `AppIntentConfiguration`, App Group (`group.abirbarman.com.time-frame`), deep links, projection
  format, and SwiftData schema (**V6**) are all **unchanged**. See `docs/24-INTERACTIVE-WIDGETS.md`.
- **A Live Activity is a read-only projection, and it is NOT available on native macOS** (Milestone 16;
  ADR-072/073/074/075/076). ActivityKit / Live Activities are `@available(macOS, unavailable)` — the
  framework ships in the macOS SDK **only for Mac Catalyst**, and the compiler rejects a native-macOS
  `ActivityAttributes` conformance. Time Frame is a **native macOS** app, so M16 was delivered as a
  **platform-feasibility milestone**: the reusable, platform-neutral *live-session core* is built and
  fully tested (`Shared/LiveSessionProjection.swift` value types + `Shared/LiveActivityPresentation.swift`;
  app-side `Services/LiveActivity/` — the `LiveActivityService` protocol + `NoopLiveActivityService`,
  `LiveActivityContentMapper`, `LiveActivityCoordinator`, `LiveActivityPreferences`), but the ActivityKit
  half (attributes conformance, adapter, `ActivityConfiguration`/Dynamic Island UI, Settings surface,
  `NSSupportsLiveActivities`) is **not** built and the core is **inert in the shipping macOS app**. There
  remains exactly **one** `TimerEngine`/`SessionCoordinator`; the core owns no timer, introduces no clock
  (`Text(timerInterval:)` repaint only), persists nothing, imports no ActivityKit/WidgetKit/SwiftData/
  CloudKit, keys activity identity to `FocusSession.id` (duplicate-prevention + launch reconciliation),
  and reuses the Milestone-15 control seam (no new action path). **`import ActivityKit` appears nowhere in
  the codebase.** A future iOS/iPadOS companion target completes the feature by adding only those platform
  pieces, reusing the core unchanged. The schema stays **V6**. See `docs/25-LIVE-ACTIVITIES.md`.
- **Production hardening adds no runtime architecture; the source-boundary audit is the release
  gate** (Milestone 17; ADR-077). M17 is a hardening milestone — no features, no rewrites — so
  `TimerEngine` stays the one timing authority, `SessionCoordinator` the one control seam, and the
  schema stays **V6**. Its only production edits are behaviour-preserving: the XCTest-host detection
  is extracted into the pure `Support/TestHostEnvironment.swift` (so launch still skips live
  seeding/recovery/CloudKit/App-Group writes/intent registration under the test host — hermeticity is
  now *tested*); `PersistenceController.openOnDiskContainer(schema:configuration:)` exposes the
  existing rebuild-on-incompatibility path for hermetic migration tests; the two live countdowns gain
  `.accessibilityAddTraits(.updatesFrequently)`; and the Restart intent binds its
  `AppIntentSessionActions` to a local to clear a spurious Release-only optimizer warning. The
  `ProductionReadinessTests` suite scans the whole source tree and **fails the build** if any invariant
  regresses (single scheduling authority, single engine/coordinator, persistence/widget/App-Intent
  boundaries, **ActivityKit only on the iOS side** — Milestone 18 scopes this; it was "nowhere" at M17,
  no CloudKit import, V6 schema, hermetic test host).
  Debug **and** Release builds pass with **0 warnings** (widget `.appex` embedded); CloudKit production
  sync stays unverified by design (needs a paid team). See `docs/26-PRODUCTION-READINESS.md`.
- **The iOS/iPadOS companion is a native app over the SAME shared core; Live Activities are a
  presentation surface, and macOS stays ActivityKit-free** (Milestone 18; ADR-078/079). The
  platform-neutral domain was extracted into a top-level **`Core/`** synchronized group attached to
  **both** the macOS and iOS app targets (`Models/`, `Timer/` incl. `TimerEngine`/`SessionCoordinator`,
  `Statistics/`, `Support/`, `Intents/`, `Widgets/`, `Navigation/`,
  `Services/{Persistence,Cloud,LiveActivity,Statistics}/`); the macOS module compiles the **identical**
  files, so `@testable import time_frame` and the macOS suite are unchanged (ADR-078). The new
  `TimeFrameiOS` app (SwiftUI: Timer/Today/History/Statistics/Settings) builds **one**
  `SessionCoordinator`/`TimerEngine` over the same `ModelContainer` — never a second timer — and reuses
  the `StatisticsAggregator`, projections, and App-Intent seams verbatim. Recovery is **device-local**
  (ADR-063) with **no new code**: a session running on another device is never recovered/mutated here.
  The `TimeFrameiOSWidgets` extension hosts the real Live Activity: `TimeFrameLiveActivityAttributes`
  (in `TimeFrameiOSShared/`, compiled into both iOS targets) reuses the M16
  `TimeFrameLiveActivityContent` **verbatim** as its `ContentState`, and the countdown is a
  `Text(timerInterval:)` repaint between frozen anchors — no clock. The app-side
  `ActivityKitLiveActivityService` is the concrete M16 `LiveActivityService` (idempotent per
  `FocusSession.id`, reconciles on launch, swallows every failure); interactive Live Activity buttons
  reuse the **shared** M15 control intents → the one `AppIntentSessionActions` seam. **`import
  ActivityKit` appears in exactly three iOS files** (attributes, adapter, Live Activity UI) and NOWHERE
  on the macOS side/`Core/`/`Shared/` — enforced by `ProductionReadinessTests`. Schema stays **V6**;
  CloudKit cross-device sync stays a documented **paid-team** blocker (the iCloud entitlement is not
  added, so the store degrades safely to local). See `docs/27-IOS-COMPANION-LIVE-ACTIVITIES.md`.
- **CloudKit capability is an explicit, testable seam; the free-team blocker stays honest and
  self-enforcing** (Milestone 19; ADR-080/081/082). M19 is a **production-validation** milestone — it
  adds **no** second timer/store/clock/control seam and **no** schema change (stays **V6**). The pure,
  CloudKit-free `Core/Services/Cloud/CloudKitCapability.swift` separates the **build/provisioning** fact
  (is this build entitled for iCloud/CloudKit) from the **runtime** account fact, and resolves the
  launch-time persistence mode via `CloudKitCapability.resolve(entitled:syncEnabled:account:)`. The one
  honest switch is `CloudKitCapability.entitledInThisBuild` — **`false`** on the shipping **personal
  (free) team** build, so both macOS and iOS launch **local-first** and never attempt a doomed cloud
  container (the store still degrades safely per ADR-062). The iCloud entitlement is **NOT** added and no
  container is invented (a fabricated entitlement would fail to sign); `M19CloudKitHonestyTests` **fails
  the build** if the entitlement and the constant ever disagree. Cross-device/merge/fallback behaviour is
  proven deterministically by `CrossDeviceSyncValidationTests` (one in-memory store models the merged
  store; two device-scoped coordinators): frozen fields survive rename/delete, running sessions stay
  **device-local** (ADR-063), statistics re-derive from **merged** history, and a CloudKit `.fallback`
  never blocks the timer. `ProductionReadinessM19Tests` adds App-Group-consistency, no-fabricated-
  entitlement, CloudKit-wiring, deep-link-scheme, and no-committed-secrets audits. **Real CloudKit sync,
  physical-device Live Activity/Dynamic Island/VoiceOver, an iOS Home-Screen widget, and iOS
  notifications remain documented blockers/deferrals** — none faked. See
  `docs/28-CLOUDKIT-DEVICE-VALIDATION.md`.
- **iOS Home Screen widgets and iOS local notifications are presentation/projection surfaces over the
  ONE timer, not a second clock** (Milestone 20; ADR-083/084/085/086). The **iOS Home Screen widget**
  lives in the **existing** `TimeFrameiOSWidgets` extension (alongside the M18 Live Activity — no new
  extension) and reads the **same** `WidgetProjection` from the **same** App Group
  (`group.abirbarman.com.time-frame`) written by the **same** `WidgetProjectionWriter`, resolves the
  **same** `TimeFrameWidgetConfigurationIntent` (`AppIntentConfiguration`), and derives its timeline
  from the **same** pure `WidgetTimelineBuilder` as the macOS widget (families small/medium/large;
  modes Timer/Today/Statistics; configuration is presentation-only; countdown is `Text(timerInterval:)`
  between frozen anchors; interactive Timer controls reuse the **M15** `Button(intent:) →
  WidgetControlActions → AppIntentSessionActions → SessionCoordinator` seam). The iOS widget imports
  **no** SwiftData/CloudKit/`TimerEngine`/`SessionCoordinator` (ADR-084/085). **iOS local
  notifications** reuse the neutral notification stack, which **moved to `Core/Services/Notifications/`**
  and is now shared by macOS **and** iOS (one source of truth); `UserNotificationService` stays the
  **only** UserNotifications importer, and the neutral timer core imports none of it (ADR-083).
  Notifications are scheduled from the engine's **frozen interval-end anchors**
  (`UNTimeIntervalNotificationTrigger`, one per boundary — never a per-tick/second clock), with
  deterministic identifiers (idempotent reconcile, no duplicates), actions routed back through
  `SessionCoordinator`, and every failure caught so a notification failure **can never stop or corrupt
  the timer** (ADR-086). iOS notification preferences persist in **UserDefaults**; the iOS Settings
  screen adds a `NotificationSettingsView` with an in-context permission flow. ActivityKit stays
  iOS-only, CloudKit stays honestly disabled, and the schema stays **V6**. See
  `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.
- **iOS Lock Screen accessory widgets and StandBy are read-only projections over the ONE timer, not a
  second clock** (Milestone 21; ADR-087/088/089). A new `TimeFrameLockScreenWidget` (kind
  `"TimeFrameLockScreenWidget"`) in the **existing** `TimeFrameiOSWidgets` extension adds families
  **`.accessoryCircular`/`.accessoryRectangular`/`.accessoryInline`**, reusing the **same**
  `WidgetProjection`/App Group (`group.abirbarman.com.time-frame`), the **same** `WidgetProjectionWriter`,
  the **same** `TimeFrameWidgetConfigurationIntent` (`AppIntentConfiguration`), the **same**
  `HomeScreenWidgetProvider`/`HomeScreenWidgetEntry`, and the **same** pure `WidgetTimelineBuilder` — it
  differs only by `kind` and its accessory views. Per-family content comes from the **pure, Foundation-only**
  `Shared/AccessoryWidgetPresentation.swift` (imports no WidgetKit/SwiftUI/AppIntents/ActivityKit/SwiftData;
  neutral `AccessoryWidgetFamily`/`AccessoryCountdown` vocabulary), which reads the projection's **frozen**
  anchors and degrades information density per family — never a second projection (ADR-088). The live
  countdown is `Text(timerInterval:)`/`ProgressView(timerInterval:)` between frozen anchors; paused shows
  the frozen remaining (no `Timer`/publisher/`Task.sleep`/decrement). **StandBy** is served by the
  **unchanged** `.systemSmall`/`.systemMedium` Home Screen widget (StandBy is not a separate WidgetKit
  API). Accessory families are **read-only** — a tap opens the configured `timeframe://` destination; the
  M15 interactive seam stays on the Home Screen widget + Live Activity, so there is still **one** mutation
  seam (ADR-089). The Home Screen widget, Live Activity, notifications, App Intents, and
  `TimerEngine`/`SessionCoordinator` are unchanged; ActivityKit stays iOS-only, CloudKit stays honestly
  disabled, App Group + deep links unchanged, schema stays **V6**. Freshness is meaningful-transition-only
  (re-proven by `WidgetProjectionFreshnessTests`); `ProductionReadinessM21Tests` audits the boundaries.
  See `docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md`.
- **iOS Control Center controls are a command adapter over the ONE mutation seam, not a second timer**
  (Milestone 22; ADR-090/091/092). Three `ControlWidget`s (WidgetKit, iOS 18+) live in the **existing**
  `TimeFrameiOSWidgets` extension (`ControlCenterWidgets.swift`; **no new appex**): an adaptive
  `TimeFramePrimaryControl` (Start/Pause/Resume/Skip by situation) plus dedicated `TimeFrameStartControl`
  and `TimeFrameStopControl`. Two reuse the **M15** `WidgetStartIntent`/`WidgetStopIntent` verbatim; the
  primary adds ONE thin `TimeFramePrimaryControlIntent` (in `Shared/WidgetControlIntents.swift`) that
  routes through the SAME seam — `ControlWidgetButton(action:) → App Intent → WidgetControlActions →
  AppIntentSessionActions → SessionCoordinator → TimerEngine`. `WidgetControlActions` gains a
  `performPrimary()` capability, and `WidgetControlRouting` resolves the primary action from **live** state
  with the pure `ControlCenterControlSet.primaryAction(for:)` and performs it through the **same**
  `perform(_:)` helper — **one** router, **one** decision path, **one** engine. The pure, Foundation-only
  `Shared/ControlCenterPresentation.swift` (`ControlCenterSessionState`/`ControlCenterControlSet`/
  `ControlCenterActionCatalog`/`ControlCenterPresentation`) derives situation + controls + appearance from
  the read-only `WidgetProjection` — no WidgetKit/AppIntents/SwiftData/CloudKit, **no clock**. Control
  Center is **iOS-only** (macOS/`Core/`/`Shared/`/macOS-widget stay `ControlWidget`-free), reads the local
  App Group projection, refreshes the projection after every action (incl. `restart`), fails safely
  (`WidgetControlError`/`TimeFrameIntentError`), and stays **CloudKit-independent**
  (`entitledInThisBuild == false`). Schema stays **V6**. `ProductionReadinessM22Tests` audits every
  boundary. See `docs/31-CONTROL-CENTER-CONTROLS.md`.
- **The configurable Control Center quick-start control is a command adapter over the ONE timer, not a
  second timer** (Milestone 23; ADR-093/094/095). A new **user-configurable** `ControlWidget`
  (`TimeFrameQuickStartControl`, iOS 18+) in the **existing** `TimeFrameiOSWidgets` extension uses
  **`AppIntentControlConfiguration`** (the piece M22 deferred) so the user chooses **which** saved timer it
  starts. Its configuration is `QuickStartControlConfigurationIntent` (a `ControlConfigurationIntent` with
  one optional `timer` parameter) — WidgetKit persists the choice; the app persists **nothing** for it. The
  selectable `QuickStartTimerEntity` (stable **`UUID`** id, frozen display strings) resolves from a
  Foundation-only App Group **catalog snapshot** (`QuickStartTimerDescriptor`/`QuickStartCatalog`/
  `QuickStartCatalogStore`, same App Group `group.abirbarman.com.time-frame`, distinct key) that the
  app-side `Core/Widgets/QuickStartCatalogWriter` publishes from the existing `ConfigurationRepository` at
  launch — so the widget extension imports **no** SwiftData and the picker resolves in any process. A tap
  routes through the ONE seam via `TimeFrameQuickStartIntent`: `ControlWidgetButton(action:) →
  WidgetControlActions.performQuickStart(configurationID:) → AppIntentSessionActions.startSession(configurationID:)
  → SessionCoordinator → TimerEngine`. `WidgetControlActions` gains **one** `performQuickStart` capability
  (wired in `WidgetControlRouting`) and stays the **one** router. The app **re-resolves the authoritative
  configuration by id** (never a cached duration), so a **rename**/duration change takes effect on tap, a
  **deleted** configuration fails safely (`TimeFrameIntentError.configurationUnavailable`, no phantom
  session), a **nil** selection starts the default, and `requireNoActiveSession()` makes rapid taps
  idempotent. The pure `QuickStartControlPresentation` (in `Shared/ControlCenterPresentation.swift`,
  Foundation-only) gives the title + VoiceOver phrasing ("Start Deep Work Timer"). Control Center stays
  **iOS-only** (macOS/`Core/`/`Shared/`/macOS-widget stay `ControlWidget`/`AppIntentControlConfiguration`-free),
  **CloudKit-independent** (`entitledInThisBuild == false`); **no new appex, no new App Group, schema stays
  V6**. `ProductionReadinessM23Tests` audits every boundary. See `docs/32-CONFIGURABLE-CONTROL-CENTER.md`.
- **Product identity is a presentation/build concern; M24 adds no runtime architecture** (Milestone 24;
  ADR-096/097/098). The user-facing name is **"Time Frame"** everywhere the OS shows it (macOS
  `INFOPLIST_KEY_CFBundleDisplayName`, iOS `CFBundleDisplayName`, widget/control display names), while
  **every internal identifier is unchanged** (module/target names, bundle id `abirbarman.com.time-frame`,
  App Group `group.abirbarman.com.time-frame`, `timeframe://`, schema **V6**). The user supplied **one**
  1024² logo (`tf_logo.png`), used **unaltered** as the single icon artwork for **both** Light and Dark on
  every platform — the macOS `AppIcon.appiconset` carries the mac raster ladder generated from it, the iOS
  `AppIcon.appiconset` (created in M24) a single 1024 universal slot; **no** `"appearances"` split and **no**
  `*Dark*`/`*Light*`/tinted variant set (ADR-096). The Control Center quick-start catalog refresh became
  **event-driven**: `ConfigurationRepository` gained a neutral opaque `onChange` hook (fired after each
  successful mutation), forwarded through `SessionCoordinator.init`, wired by each app to
  `QuickStartCatalogWriter.refresh` — **no polling, no new timer/store**, the App Group catalog stays a
  projection over the authoritative model (ADR-097). There remains exactly **one** `TimerEngine`/
  `SessionCoordinator`/`AppIntentSessionActions` seam; accessibility was reviewed (not churned), widgets/
  Live Activity/notifications validated (not rewritten), CloudKit stays disabled (personal team,
  `entitledInThisBuild == false`). `ProductionReadinessM24Tests` gates the name/icon/identity invariants.
  See `docs/33-M24-ON-DEVICE-UX-VALIDATION.md`.
- **A `MenuBarExtra` label must never contain a `TimelineView`** (or any scheduling primitive)
  (Milestone 26; ADR-101). SwiftUI renders a status-item label into an `NSStatusBarButton` and
  re-renders it **synchronously**; a `TimelineView` re-arms during that render, collapsing its delay to
  zero and producing an unbounded `updateButton → setImage: → invalidate` loop that pins the main thread
  at 100% CPU for as long as a session runs — the app freezes the moment you start one. A status-item
  countdown must be repainted from **outside** the render pass: observe `SessionCoordinator.displaySecond`
  (the display-only whole-second signal the **existing** heartbeat publishes — not a second clock, no
  timing authority, and never a place to hang persistence/notification/projection work). `TimelineView`
  remains correct in ordinary hosted views (`TimerDisplay`, `TodayView`, the menu-bar popover).
  `MenuBarLabelRepaintTests` enforces this.
- **Nothing on the timer control path may do unbounded or persistence-heavy work**
  (Milestone 26; ADR-099/100). `SessionCoordinator.pause()/resume()/stop()/skip()/startSession()` emit
  their lifecycle event **synchronously**, so every observer runs inside the user's Pause. An observer
  may therefore only do work derived from the engine's **in-memory anchors**; anything that reads the
  store, aggregates history, or grows with recorded data must be **deferred** onto a fresh main-actor
  task (the Notification/Calendar `deferWork` pattern) and **coalesced**. `WidgetProjectionWriter`
  follows this: the session projection is written synchronously, the today summary on a coalesced
  follow-up. Period statistics are **never** fetched over all history — route every period-scoped read
  through `StatisticsDateRange.mayContainActivity` / `StatisticsRepository.sessionInputs(in:)`, whose
  equivalence to unbounded aggregation is the load-bearing test. The heartbeat is the **one** scheduling
  primitive in `Core/` (`Task.sleep` appears in exactly one file) and is **generation-stamped**: a
  cancelled tick loop must never clear a newer one's handle, or tick loops multiply without bound.
  `ProductionReadinessM26Tests` enforces all of this. See `docs/34-M26-STABILITY-AND-RELIABILITY.md`.
- **The menu bar popover is ordered by importance, and Quick Start is a projection — never a
  second store** (Milestone 28; ADR-102/103/104/105). The four navigation actions (Open Time Frame,
  Settings, History, Quit) live behind **one** native gear `Menu` in the popover's top-right corner,
  never as permanent rows in the primary content; the transport controls and countdown are laid out
  **outside any scroll view** so a long pinned list can never push them off screen (only the pinned
  list scrolls, height-bounded). Running and paused offer the same four controls (Pause/Resume, Skip,
  Restart, Stop) and route through the unchanged `MenuBarCoordinator → SessionCoordinator → TimerEngine`
  seam; the status-item **label** still contains no `TimelineView` (ADR-101). **Icons are a closed,
  typed catalog** (`Core/Support/TimeFrameIcon.swift`): the persisted value is a stable dot-free
  identifier, **never** an SF Symbol name and never free text; `TimeFrameIconIdentifier.symbolName` is
  the **one** mapping and `resolve(_:fallback:)` the one entry point for stored data, so an unknown
  value can never reach `Image(systemName:)`. **Pin state lives on the pinned item** (`isPinned`/
  `pinnedAt` on `TaskTemplate`/`SessionPlan`, keyed by the stable `UUID`) — no side table, no
  UserDefaults key, no App Group key — so a rename keeps the pin, a delete removes it, an edit never
  changes it, and a duplicate copies the icon but not the pin. The Quick Start list is a read-only
  projection (`Core/Services/QuickStart/`) ordered oldest-pin-first, and a start routes through the
  **existing** `AppIntentSessionActions` seam, re-resolving the authoritative item by id so a stale
  row fails safely. Refresh is **event-driven** off the repositories' neutral `onChange` hook
  (forwarded via `SessionCoordinator.init(onLibraryChanged:)`) — **no polling, no second clock**. The
  M23 App Group `QuickStartCatalog` is unchanged: it serves the iOS Control Center picker, which runs
  in a SwiftData-free extension process. Schema bumped **V6 → V7** (three attributes on each of two
  models; the same six model types, every attribute defaulted or optional and CloudKit-legal).
  `ProductionReadinessM28Tests` + `MenuBarPopoverLayoutTests` enforce all of this. See
  `docs/37-M28-MENU-BAR-QUICK-START-ICONS.md`.
- **A pushed detail page presents its own sheets, and the app has ONE design system**
  (Milestone 29; ADR-106/107). On macOS a `.sheet` requested from a `NavigationStack`'s **root**
  while a `navigationDestination` is pushed is **not presented** — the request is held until the
  stack pops back. That is why Template/Plan **Edit** did nothing. `TemplateDetailView` and
  `PlanDetailView` therefore own their editor sheet (`@State` + `.sheet(item:)`) and take **no**
  `onEdit` closure; the lists keep their own sheet only for Create and their own row actions.
  Editing still goes through the **same** editor and the **same** `TaskTemplateRepository.update` /
  `SessionPlanRepository.update`, so identity, pin, icon, timeline and history are untouched
  (`EditorFlowTests` covers both the behaviour and the presentation structure). The **menu bar
  popover does not scroll** (ADR-107, supersedes the bounded list of ADR-102): the pinned list is
  capped at `MenuBarQuickStartView.visibleLimit` rows with a "N more..." menu for the rest, and
  `MenuBarPopoverLayoutTests` fails the build if any menu-bar view contains a `ScrollView`.
  Presentation vocabulary is centralised: `Core/Support/DesignSystem/` owns the tokens, the glass
  surfaces, and the **one** content card (`tfCard`; `tfQuietSurface` delegates to it), and
  `time_frame/Views/Components/` owns the shared macOS pieces (`TFPageHeader`, `TFSectionHeader`,
  `TFDetailCard`/`TFDetailRow`, `TimeFrameIconTile`/`TFSymbolTile`, `TFRowActions`,
  `TFManageSection`, `TFNoticeBanner`, `TFSheetHeader`, `TFChip`, `TFDefaultMarker`). Each page has
  **exactly one** prominent action; preferences are switches; destructive actions live in a separate
  "Manage" group. The Timer screen's Quick Start reads the **same** `QuickStartCoordinator` the menu
  bar uses — never a second list — and Recent Tasks is a **bounded** `FetchDescriptor` (ADR-100). No
  screen added a timer, clock, store or seam; schema stays **V7**. See
  `docs/38-M29-MACOS-UI-REDESIGN.md`.
- **The type scale and the control-size rule live in the design system** (Milestone 30;
  ADR-108). `Core/Support/DesignSystem/TimeFrameDesign.swift` owns `TFTypography` (the roles
  `pageTitle`/`subjectTitle`/`sectionTitle`/`rowTitle`/`body`/`secondary`/`metadata`/
  `numericValue`/`groupTitle`/`rowLabel`/`rowValue`, in **native system fonts** — no custom faces,
  no arbitrary point sizes) and `TFControl` + `tfPrimaryAction()`/`tfSecondaryAction()`. The rule:
  a screen has **exactly one** prominent action, **sized to its content** at the native `.regular`
  height with a 108 pt floor width — **never** a full-width filled slab, and **never**
  `.controlSize(.large)` for a page action. `tfPrimaryAction` deliberately offers no full-width
  variant; the **one** control that spans its container is the menu-bar popover's fallback action,
  which says so at the call site and is recorded by a test. The shared components (`TFPageHeader`,
  `TFSectionHeader`, `TFDetailCard`, `TFDetailActions`) read their sizes from the scale, so
  changing what a section title or a primary action looks like is **one edit**. A disabled Start
  states why in **words**, not by dimming alone. M30 adds **no** feature, store, timing authority,
  clock or seam: no file under `Timer/`, `Services/` or `Models/` changed, the design system still
  imports none of the domain, and the schema stays **V7**. `ProductionReadinessM30Tests` fails the
  build if a page reaches for `.large`, if the Timer's Start becomes full-width again, if a type
  role disappears, or if a redesigned screen introduces a scheduling primitive. See
  `docs/39-M30-DESIGN-SYSTEM-CONSOLIDATION.md`.
- **A store that cannot be opened is PRESERVED, never deleted** (Milestone 31; ADR-109/110,
  **supersedes ADR-016**). `PersistenceController.openOnDiskContainer` classifies the failure
  (`StoreOpenFailure`: `schemaMismatch`/`migrationFailed`/`storeCorrupt`/`malformedStore`/
  `fileAccessFailed`/`permissionDenied`/`fileLocked`/`unknown`) and throws `StoreOpenError`
  **without touching a single file**. An unrecognised failure is `unknown` — **never** defaulted to
  "corrupt", because that default is what licensed the deletion. `removeStoreFiles(at:)` is
  **deleted**, and there is **no** `FileManager.removeItem` anywhere in production source; the only
  filesystem mutation is `StoreQuarantine`, which **moves** a store (plus `-wal`/`-shm`, which can
  hold committed transactions) into `TimeFrame Recovery/<UTC timestamp>/`, never overwriting an
  earlier copy, and only from an explicit, confirmed user action. `bootstrap` returns
  `PersistenceState.needsRecovery` with a **scratch in-memory** container so the app can launch and
  explain itself; `isShowingDurableData` is false, and `PersistenceRecoveryView` takes over the
  window rather than presenting an empty library — an empty library is exactly what a destroyed
  store used to look like. The store URL is resolved explicitly by `StoreLocation`
  (`TIMEFRAME_STORE_DIRECTORY` > XCTest-isolated > production at the unchanged path), so a test or
  a dev build cannot reach the user's data by default. V6 → V7 migration is **executed**, not
  assumed, against frozen V6 models (`SchemaV6Fixture`, test target only). Schema stays **V7**;
  CloudKit unchanged. `ProductionReadinessM31Tests` fails the build if any of this regresses. See
  `docs/40-M31-DATA-SAFETY-AND-RECOVERY.md`.
- **There is ONE main window, and ONE pathway to it** (Milestone 32; ADR-111). The macOS main
  scene is a single-instance **`Window`**, not a `WindowGroup` — a `WindowGroup` exists to allow
  more than one window, `openWindow(id:)` creates a new one on every call, and that is what
  produced duplicates from four surfaces that each held the capability. Every request now goes
  through `MainWindowPresenter.showMainWindow(_:)`, exposed to views as the `\.showMainWindow`
  environment action; **`openWindow` appears in exactly one file** (`MainWindowPresentation.swift`),
  and window ordering (`makeKeyAndOrderFront`/`orderFront`/`deminiaturize`/`unhide`) only in
  `AppKitMainWindowHost`. The decision is the pure `MainWindowPolicy` over a snapshot read **fresh
  from the live window every time** — never a `windowIsOpen` boolean, which is wrong the moment the
  window is closed, minimized, hidden, or rebuilt. The host holds its `NSWindow` **weakly** and
  deregisters on `willCloseNotification`. `applicationShouldHandleReopen` never consults
  `hasVisibleWindows` (false for a minimized window *and* a hidden app — the Dock duplicate bug);
  it asks the presenter. Concurrent requests **coalesce** for one run-loop turn, released by a
  one-shot main-actor continuation and by the window registering — no timer, no poll.
  `applicationShouldTerminateAfterLastWindowClosed` returns **`false`**: `WindowGroup` kept the
  process alive on last-window-close and `Window` does not, so without it ⌘W would end a running
  Pomodoro. Focusing a window is window behaviour **only** — it never resets navigation or setup
  state and never touches `TimerEngine`, `SessionCoordinator`, or history. The window layer is
  macOS-only, owns no domain, and adds no clock or store. `ProductionReadinessM32Tests` enforces
  all of this. See `docs/41-M32-LOGIN-ITEM-AND-WINDOW-MANAGEMENT.md`.
- **"Open at Login" is registered with `SMAppService`, and the SYSTEM is the source of truth**
  (Milestone 32; ADR-112). `Services/Login/LoginItemService.swift` is the **only** file importing
  ServiceManagement (isolated like `EventKitCalendarService`/`UserNotificationService`), behind a
  `LoginItemManaging` seam; no deprecated `SMLoginItemSetEnabled`/`LSSharedFileList`. **Nothing is
  persisted** — no `UserDefaults` key, no `@AppStorage`. `LoginItemCoordinator.isEnabled` is derived
  from the status macOS reports, re-read on launch, when Settings appears, and **after every
  change**, so a refused registration leaves the toggle off and `.requiresApproval` reads off with
  System Settings offered. Errors are the closed `LoginItemError` set; one attempt per user action
  and **no scheduling primitive** in the coordinator, so a failure can never become a retry loop.
  The XCTest host gets `UnavailableLoginItemService` (hermeticity, ADR-077). Schema stays **V7**.
- **The user-facing product name lives in `PRODUCT_NAME`; internal identifiers never move for
  branding** (Milestone 33; ADR-113, completes ADR-096). The macOS application menu's title (beside
  the Apple menu) comes from **`CFBundleName`**, not `CFBundleDisplayName` — M24 set the display
  name, tested it, and the menu still read `time_frame`, because the menu *items* use the display
  name and the title does not. `CFBundleName` is generated from `PRODUCT_NAME`, and the generated
  value **wins over the physical Info.plist**; `INFOPLIST_KEY_CFBundleName` is **not honoured**.
  So the macOS app sets `PRODUCT_NAME = "Time Frame"` with **`PRODUCT_MODULE_NAME = time_frame`
  pinned beside it** — without that pin the Swift module is renamed and every
  `@testable import time_frame` stops compiling — and `TEST_HOST` follows the product in both
  configurations. The built product is `Time Frame.app`. On iOS (`GENERATE_INFOPLIST_FILE = NO`)
  `CFBundleName` **and** `CFBundleIconName` are stated in the plist directly; without the latter the
  icon compiles into `Assets.car` undeclared and App Store validation rejects it. **Never** rename
  the bundle identifier, App Group, `timeframe://` scheme, Swift module, `.xcodeproj`, targets or
  source directories for branding — none is user-facing and each breaks signing, widgets, deep links
  or persistence. **macOS and iOS need different icon canvases**: macOS does **not** mask app icons, so the
  artwork must carry its own rounded shape — a **rounded body with alpha on a 1024x1024
  canvas**, corner radius **0.225 x side**. Time Frame fills the canvas (body 1024, radius 230.4)
  because Apple's nominal 824 grid read too small beside document-shaped icons; a full-bleed
  *square* renders as a hard square (M24's one-file-for-both is why it did). iOS is the opposite: **full bleed, no alpha**, system-masked.
  One logo *design*, two canvases; no Light/Dark or tinted variants, one `AppIcon.appiconset` per
  platform catalog. Schema stays **V7**. `ProductionReadinessM33Tests` guards the keys M24's suite
  missed. See `docs/42-M33-PRODUCT-NAME-AND-ICON.md`.
- **Task Templates reference `PomodoroConfiguration`** rather than duplicating
  configuration data (implemented in Milestone 4; ADR-022). Starting a session
  from a template **copies** its values into the existing setup/start path, so the
  running session is independent of the template (ADR-023/025). The chain
  `TaskTemplate → PomodoroConfiguration → SessionSetupDraft → FocusSession →
  SessionInterval` must stay intact.
- **The Session Planner is a planning layer, not a second timer** (implemented in
  Milestone 5; ADR-026). `SessionPlan`/`SessionPlanItem` are persisted, editable
  plans that may mix configurations (per focus item; ADR-030). Starting one freezes
  an immutable `SessionPlanExecutionSnapshot` (ADR-028) and runs it through the
  **existing** `SessionCoordinator.startPlan` → `TimerEngine` → `FocusSession` path.
  A running/historical session is independent of the saved plan and its
  configurations; deleting a plan never deletes sessions/history (ADR-029). Do not
  build a `PlannerTimerEngine`/`PlannerSession`. See `docs/14-SESSION-PLANNER.md`.
- Use **dependency injection** where it improves testability (e.g. the clock).
- **Preserve data integrity.** Use explicit delete rules and a versioned schema.
- **Do not make unrelated changes.**

## Layering

```
SwiftUI Views  →  App State / Coordinators  →  Domain (Timer Engine)  →  Persistence (SwiftData)
```

Dependencies point downward only. The Timer Engine depends on neither SwiftUI
nor SwiftData.

## Source layout (inside the `time_frame/` app target)

- `App/` conceptually — `time_frameApp.swift` (entry point + ModelContainer; owns the one
  `SessionCoordinator` and the Calendar/Notification/MenuBar/Login adapters; declares the
  single-instance `Window(id: "main")` — **never** a `WindowGroup` (ADR-111) — the `MenuBarExtra`
  scene, and the `@NSApplicationDelegateAdaptor` that owns the `MainWindowPresenter`).
- `Models/` — SwiftData `@Model` types (`PomodoroConfiguration`,
  `FocusSession`, `SessionInterval`, `TaskTemplate`, `SessionPlan`,
  `SessionPlanItem`).
- `Timer/` — the pure engine: `TimerEngine`, `TimerState`, `TimerPhase`,
  `IntervalPlan` (the engine's execution plan — renamed from `SessionPlan` in
  Milestone 5; ADR-031), `PomodoroConfigurationSnapshot`, `TimeSource`,
  `IntervalRecord`, `SessionCoordinator`. Also the planner value types
  `SessionPlanGenerator` and `SessionPlanExecutionSnapshot`, and the
  integration-agnostic `SessionLifecycleEvent` seam the Calendar **and** Notification
  layers subscribe to (plus the read-only `currentLifecycleContext()` accessor).
- `Services/Persistence/` — schema, migration plan, container factory, and the
  repositories (`Configuration`, `Session`, `TaskTemplate`, `SessionPlan`) +
  validation.
- `Services/Calendar/` — the isolated Calendar integration (Milestone 6):
  `CalendarService` (+ `EventKitCalendarService`), `CalendarCoordinator`,
  `CalendarEventGenerator`, and the pure value types (`CalendarEventDraft`,
  `CalendarEventReference`, `CalendarDescriptor`, `CalendarAuthorizationStatus`,
  `CalendarIntegrationError`, `CalendarEventStyle`) plus the UserDefaults-backed
  `CalendarSettings`/`CalendarEventRecord` stores.
- `Core/Services/Notifications/` — the isolated Notification integration (Milestone 6's pattern
  reused; Milestone 7; **moved to `Core/` and shared by macOS + iOS in Milestone 20, ADR-083**):
  `NotificationScheduling` (+ `UserNotificationService`, the sole UserNotifications importer and
  notification-center delegate — now shared by both platforms), `NotificationCoordinator` (its
  `openSystemSettings()` is `#if canImport(AppKit)` / `#elseif canImport(UIKit)`), the pure
  `NotificationContentGenerator`/`NotificationScheduleBuilder`/
  `NotificationActionResolver`, and the pure value types (`NotificationDescriptor`,
  `NotificationContent`/`NotificationIdentifier`, `NotificationCategory`,
  `NotificationAction`, `NotificationSound`, `NotificationAuthorizationStatus`,
  `NotificationIntegrationError`, `NotificationSessionSnapshot`) plus the UserDefaults-backed
  `NotificationPreferences`/`NotificationPreferencesStore`. The macOS Settings section lives in
  `time_frame/Views/Notifications/NotificationSettingsSection.swift`; the iOS one in
  `TimeFrameiOS/Views/NotificationSettingsView.swift` (Milestone 20).
- `Services/Window/` — the single-window layer (Milestone 32; ADR-111): the pure
  `MainWindowPolicy` (+ `MainWindowSnapshot`/`MainWindowAction`), the `MainWindowPresenter` (the one
  pathway), the `MainWindowHosting` protocol + `AppKitMainWindowHost` (the only place window
  ordering happens), `MainWindowPresentation` (the `\.showMainWindow` environment action, the one
  `openWindow` call site, and the window-registering accessor), and `TimeFrameAppDelegate`
  (`applicationShouldHandleReopen` + `applicationShouldTerminateAfterLastWindowClosed`, and the
  owner of the presenter and `AppNavigation`). macOS-only; imports no domain.
- `Services/Login/` — "Open at Login" (Milestone 32; ADR-112): `LoginItemStatus`/`LoginItemError`,
  the `LoginItemManaging` seam with `SMAppServiceLoginItem` (the **only** ServiceManagement
  importer) and `UnavailableLoginItemService`, and the `@Observable` `LoginItemCoordinator`.
  Persists nothing — the system's registration is the state.
- `Services/MenuBar/` — the menu-bar adapter (Milestone 8): the pure
  `MenuBarPresentationState` projection, the `MenuBarCoordinator` observer/control adapter,
  and the UserDefaults-backed `MenuBarPreferences`/`MenuBarPreferencesStore`.
- `Core/Services/QuickStart/` — the Quick Start layer (Milestone 28; ADR-104/105): the pure
  `QuickStartItem` + `QuickStartOrder` (the one ordering comparator), the pure
  `QuickStartPinPresentation` (the one place the pin control's words live), the read-only
  `QuickStartProvider` (pinned templates/plans → rows), and the `@Observable`
  `QuickStartCoordinator` (the popover's list, refreshed on the repositories' `onChange` hook;
  starts route through the existing `AppIntentSessionActions` seam). Imports only Foundation/
  Observation — no SwiftUI, no WidgetKit, no CloudKit, and **no scheduling primitive**.
- `Statistics/` — the pure, read-only analytics engine (Milestone 10): `StatisticsInput`
  (`SessionStatInput`/`IntervalStatInput`), `StatisticsPeriod`/`StatisticsDateRange`,
  `StatisticsSnapshot` (+ `DailyStatistics`/`ConfigurationStatistics`/`StatisticsComparison`),
  and `StatisticsAggregator`. Imports only Foundation; no SwiftData/SwiftUI/timer.
- `Services/Statistics/` — the read-only `StatisticsRepository` (fetch + map to inputs).
- `Services/Cloud/` — the iCloud/CloudKit integration surface (Milestone 13): the pure
  `CloudSyncPresentationState` projection + resolver, `CloudAccountStatusProvider`
  (CloudKit-free account availability), `CloudSyncError`, the UserDefaults-backed
  `CloudSyncPreferences`, and the `@Observable` `CloudSyncCoordinator`. Imports **no** CloudKit.
  The `PersistenceMode` value and `CloudDeviceIdentity` live under `Services/Persistence/`, and
  the store itself is CloudKit-backed via `PersistenceController` (SwiftData native mirroring).
- `Views/` — the sidebar areas, including `Views/Templates/`, `Views/Plans/`,
  `Views/Statistics/` (the dashboard, period picker, and Swift Charts),
  `Views/Calendar/` (settings section, calendar picker, event preview, sync status),
  `Views/Notifications/` (`NotificationSettingsSection` in Settings), and `Views/MenuBar/`
  (the `MenuBarExtra` label + `.window` popover, its sub-views, the pure
  `MenuBarStatusPresentation`, and `MenuBarSettingsSection` in Settings; Milestone 28 adds
  `MenuBarGearMenu` — the **only** place the Open/Settings/History/Quit actions appear —
  plus `MenuBarQuickStartView`/`MenuBarQuickStartRowView`/`MenuBarOpenSectionButton`), and
  `Views/Components/` (`TimeFrameIconPicker`/`TimeFrameIconBadge` — the one icon picker and the
  one icon renderer — and `QuickStartPinButton`/`QuickStartPinMenuButton`/`QuickStartPinnedMarker`,
  Milestone 28; plus the Milestone 29 shared design pieces `TFPageHeader`/`TFSectionHeader`,
  `TFDetailCard`/`TFDetailRow`, `TFManageSection`/`TFNoticeBanner`, `TFSheetHeader`,
  `TimeFrameIconTile`/`TFSymbolTile`, `TFRowActions`, `TFChip`, `TFDefaultMarker`),
  and `Views/Cloud/`
  (`CloudSyncSettingsSection` — the Settings › iCloud section, Milestone 13). `AppNavigation`
  (the shared window/section navigation seam) also lives under `Views/`.
  `Components/`, `Utilities/` — created when there is real code to put there.
- `Support/` — pure, SwiftUI-free helpers (`TimeFormatting`; `TimeFrameIcon.swift` — the closed
  icon catalog `TimeFrameIconIdentifier`/`TimeFrameIconCategory` and its one resolver, Milestone 28/
  ADR-103) and, under
  `Support/DesignSystem/` (Milestone 9), the presentation-only visual system:
  `TimeFrameDesign.swift` (`TFSpacing`/`TFRadius`/`TFMotion`/`TFPalette` + `tfAnimation`) and
  `TimeFrameGlass.swift` (`tfGlassSurface`/`tfQuietSurface`). Imports no domain (ADR-050).
- `Shared/` (Milestone 11; **repo-root**, compiled into **both** the app and the widget) —
  the pure, Foundation-only widget projection value types: `WidgetProjection` (+ Milestone 14
  additive optional `completedFocusIntervalsToday`/`focusTrendToday`), `WidgetProjectionState`
  (+ `WidgetFocusTrend`), `WidgetProjectionStore`, `WidgetDeepLink`, `WidgetTimelinePolicy`.
  **Milestone 14** adds the pure `TimeFrameWidgetConfiguration` (`WidgetDisplayMode`/
  `WidgetDestination`), the pure `WidgetTimelineBuilder` (projection+config → entries+reload), and
  `TimeFrameWidgetConfigurationIntent` (`WidgetConfigurationIntent` + `AppEnum`s). **Milestone 15**
  adds `WidgetControlIntents.swift` — `WidgetControlAction`, the pure `WidgetControlSet`
  (state→controls), `WidgetControlResult`/`WidgetControlError`, the app-owned `WidgetControlActions`
  router, and the six thin `Widget{Pause,Resume,Skip,Restart,Stop,Start}Intent`s. Those **two** files
  are the only shared files importing `AppIntents`; every other shared file imports no
  SwiftData/SwiftUI/WidgetKit/`AppIntents`/domain (ADR-055/064/069). **Milestone 16** adds the pure,
  Foundation-only live-session projection: `LiveSessionProjection.swift` (`TimeFrameLiveActivityContent`,
  `LiveActivityIdentity`, `LiveActivitySnapshot`, `LiveActivityRunState`) and `LiveActivityPresentation.swift`
  — both import **no** ActivityKit (Live Activities are unavailable on macOS, ADR-076). **Milestone 21**
  adds the pure, Foundation-only `AccessoryWidgetPresentation.swift` (`AccessoryWidgetFamily`,
  `AccessoryCountdown`, and the circular/rectangular/inline presentation value types) — the per-family
  mapper for the iOS Lock Screen accessory widget; it imports no WidgetKit/SwiftUI/AppIntents/ActivityKit/
  SwiftData (ADR-088). **Milestone 22** adds the pure, Foundation-only `ControlCenterPresentation.swift`
  (`ControlCenterSessionState`, `ControlCenterControlSet`, `ControlCenterActionCatalog`,
  `ControlCenterPresentation`) — the decision layer behind the iOS Control Center controls; it imports no
  WidgetKit/SwiftUI/AppIntents/ActivityKit/SwiftData/CloudKit and **no clock** (ADR-091). `WidgetControlIntents.swift`
  also gains `TimeFramePrimaryControlIntent` + `WidgetControlActions.performPrimary()` for the adaptive
  control (ADR-090). **Milestone 23** adds the configurable quick-start layer to the **existing** shared
  files (no new `Shared/` file, so no `.pbxproj` change): `WidgetControlIntents.swift` gains
  `QuickStartTimerEntity`(+`QuickStartTimerEntityQuery`), `QuickStartTimerDescriptor`/`QuickStartCatalog`/
  `QuickStartCatalogStore` (App Group snapshot for the picker), `QuickStartControlConfigurationIntent`
  (a `ControlConfigurationIntent`), `TimeFrameQuickStartIntent`, and `WidgetControlActions.performQuickStart(configurationID:)`;
  `ControlCenterPresentation.swift` gains the pure `QuickStartControlContent`/`QuickStartControlPresentation`
  (ADR-093/094/095). `Shared/` is **not** a synchronized group — new files need explicit membership in
  all four app/widget targets' Sources phases in `.pbxproj`.
- `Services/LiveActivity/` — the platform-neutral live-session core (Milestone 16; ADR-072/074): the
  `LiveActivityService` isolation protocol + `NoopLiveActivityService` and `LiveActivityDismissal`, the
  pure `LiveActivityContentMapper` (authoritative state → `LiveActivitySnapshot`), the
  `LiveActivityCoordinator` (lifecycle observer/adapter + `reconcileOnLaunch()`), and the
  UserDefaults-backed `LiveActivityPreferences`/`LiveActivityPreferencesStore`. Imports only
  Foundation/Observation — **no ActivityKit** — and is **inert in the shipping macOS app**.
- `time_frame/Widgets/` (Milestone 11; app target) — the app-side `WidgetProjectionMapper`,
  `WidgetProjectionWriter`, and `WidgetDeepLink+AppSection` (+ `TodaySummary`, extended in
  Milestone 14 with completed focus intervals and a focus trend).
- `TimeFrameWidgets/` (Milestone 11; the **`TimeFrameWidgets` app-extension target**,
  bundle id `abirbarman.com.time-frame.TimeFrameWidgets`) — the `@main WidgetBundle`
  (Milestone 14: **`AppIntentConfiguration`**, same `kind`), `AppIntentTimelineProvider`, entry
  (carries the config), per-mode/per-state views (Timer/Today/Statistics), preview data, and
  formatting. Imports WidgetKit + SwiftUI + `Shared/`; never SwiftData, CloudKit, or the app
  model layer.
- `Intents/` (Milestone 12; app target) — the App Intents integration surface: the pure
  `AppIntentSessionState` projection + `AppIntentDialogText` phrasing, the closed
  `TimeFrameIntentError`, the `@MainActor AppIntentSessionActions` (the one place intents act),
  `IntentDependencies` (`IntentDataProvider` + `AppDependencyManager` registration), the 11
  intents, the 4 App entities (`TaskTemplateEntity`/`SessionPlanEntity`/`ConfigurationEntity`/
  `CurrentSessionEntity`) with their `EntityStringQuery`s, and `TimeFrameShortcuts`
  (`AppShortcutsProvider`). Imports AppIntents; reaches the domain only through the existing
  `SessionCoordinator` and repositories (ADR-056). App Intents metadata is generated
  automatically by the build (`ExtractAppIntentsMetadata`) — no `.pbxproj` change was needed.
  **Milestone 15** adds `WidgetControlRouting` (builds the `WidgetControlActions` closure delegating
  to the one `AppIntentSessionActions` seam + refreshing the widget projection) and
  `IntentDependencies.registerWidgetControl(_:)` (advertises the router). The widget's interactive
  intents themselves live in `Shared/` (ADR-069).

The Xcode project uses **file-system-synchronized groups**: any `.swift` file
placed under `time_frame/` (macOS app), `TimeFrameWidgets/` (macOS widget), `Core/` (shared
neutral domain — compiled into **both** the macOS app and the `TimeFrameiOS` app), `TimeFrameiOS/`
(iOS app), `TimeFrameiOSWidgets/` (iOS Live Activity extension), or `TimeFrameiOSTests/` is compiled
automatically into its owning target(s) — no `.pbxproj` edit is needed to add a source file there.
`Shared/` files are compiled into all four app/extension targets via explicit build membership, and
`TimeFrameiOSShared/` (the one ActivityKit attribute type) into both iOS targets the same way. Adding
a **target** (e.g. tests, an extension) does require `.pbxproj` changes.

## Development workflow

Before implementing a feature:

1. Read the relevant `docs/` document.
2. Inspect the existing implementation.
3. Explain the implementation plan.
4. Make the **smallest coherent change**.
5. **Build** the project.
6. **Run relevant tests.**
7. Update documentation to match what now exists.
8. Report changed files and verification results.

## Build & test commands

Build:

```bash
xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame -destination 'platform=macOS' build
```

Test:

```bash
xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame -destination 'platform=macOS' test
```

## Testing rules

- Prefer **Swift Testing** (`@Test`, `@Suite`, `#expect`).
- The timer engine must be tested **deterministically** via the injected
  `TimeProviding` clock — tests must never wait real seconds.
- In SwiftData tests, **keep the `ModelContainer` alive** for the whole test; a
  `ModelContext` does not retain its container.

## Phase discipline

**Never implement a future milestone unless explicitly requested.** If you find
something that belongs to a later phase, **document it** (in `docs/DECISIONS.md`
or the relevant doc) instead of building it. See
`docs/00-PRODUCT-REQUIREMENTS.md` for the explicit V1 boundaries.
