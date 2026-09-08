# 27 — iOS/iPadOS Companion & Real Live Activities (Milestone 18)

> Status: implemented. Native iOS/iPadOS companion target + real ActivityKit Live Activities.
> macOS remains ActivityKit-free. Schema stays **V6**. See ADR-078 and ADR-079.
>
> **Milestone 19 update.** The iOS app now resolves its launch-time `PersistenceMode` through the shared
> CloudKit capability seam (`CloudKitCapability`; ADR-080) — identical to macOS. Because this
> personal-team build is not entitled, the iOS store launches **local-first** and degrades safely; the
> device-local running-session policy is additionally proven under a merged synced store
> (`IOSCloudKitCapabilityTests` + `CrossDeviceSyncValidationTests`). Real cross-device CloudKit sync and
> on-device Live Activity visuals remain documented, unfaked blockers. See
> `docs/28-CLOUDKIT-DEVICE-VALIDATION.md`.

## 1. Objective

M18 is Time Frame's first multi-platform expansion. It adds a **native iOS/iPadOS companion app**
and **real ActivityKit Live Activities** (Lock Screen + Dynamic Island), reusing the platform-neutral
Milestone-16 live-session core, without redesigning or destabilizing the mature macOS app.

The load-bearing invariants are unchanged and non-negotiable:

1. **One timer.** There is exactly one `TimerEngine`, still the only timing authority.
2. **One session-control seam.** Every control still routes through `SessionCoordinator`.
3. **A Live Activity is a presentation surface, never timer authority.** It renders a frozen
   projection and a `Text(timerInterval:)` repaint — it owns no clock and decrements nothing.
4. **macOS stays ActivityKit-free.** `import ActivityKit` appears only in the two iOS targets.
5. **No fabricated CloudKit or device verification.** Cross-device CloudKit sync remains a
   documented manual blocker (needs a paid Apple Developer team).

## 2. Platform requirements (verified against the installed SDK)

- Xcode **27.0** (build 27A5194q); Swift **6.4**; SDKs **iOS 27.0** (device + simulator), **macOS 27.0**.
- ActivityKit is present in the iOS Simulator SDK (`ActivityKit.framework`), and it remains
  `@available(macOS, unavailable)` — the native-macOS constraint from ADR-076 is unchanged.
- iOS deployment target: **26.0** (Live Activities, interactive widgets, and Liquid Glass all available).
- Simulators available: iPhone 17 / 17 Pro / Air, iPad Pro/Air/mini (iOS 27).

## 3. Target architecture

```
                         Core/ (shared, platform-neutral)
        Models · Timer (TimerEngine, SessionCoordinator) · Services/Persistence
        Services/Cloud · Services/LiveActivity (M16 core) · Statistics · Intents · Widgets
                             │                         │
              ┌──────────────┘                         └───────────────┐
        macOS app (time_frame)                              iOS app (TimeFrameiOS)
        Views · MenuBar · Calendar                    RootView · TimerScreen · Today ·
        Notifications · macOS widget                  History · Statistics · Settings
              (NO ActivityKit)                                     │
                                                    ActivityKitLiveActivityService  ← only app-side
                                                                   │                   ActivityKit importer
                                                        LiveActivityCoordinator (M16)
                                                                   │
                                                    Activity<TimeFrameLiveActivityAttributes>
                                                                   │
                                              iOS widget ext (TimeFrameiOSWidgets)
                                              ActivityConfiguration + Dynamic Island  ← only other
                                                                                        ActivityKit importer
```

Shared value types (`Shared/`) compile into every target. `TimeFrameiOSShared/` holds the one
ActivityKit attribute type, compiled into both iOS targets.

## 4. Project structure (ADR-078 — the `Core/` extraction)

The platform-neutral domain was moved out of the macOS app's synchronized group into a new top-level
`Core/` synchronized group **attached to both the macOS and iOS app targets**. The macOS module
compiles the identical set of files (now under two synchronized groups instead of one), so
`@testable import time_frame` and the whole macOS test suite are unaffected. Moved into `Core/`:
`Models/`, `Timer/`, `Statistics/`, `Support/`, `Intents/`, `Widgets/`, `Navigation/` (the neutral
`AppSection`/`AppNavigation`), and `Services/{Persistence,Cloud,LiveActivity,Statistics}/`.

Left in the macOS app (`time_frame/`): `Views/`, `Services/{Calendar,MenuBar,Notifications}/`,
`ContentView.swift`, `time_frameApp.swift`, `Assets.xcassets`.

New targets:

| Target | Product | Role |
| --- | --- | --- |
| `TimeFrameiOS` | `.app` | iOS/iPadOS companion (SwiftUI). Attaches `Core/` + `Shared/` + `TimeFrameiOSShared/`. Embeds the iOS widget. |
| `TimeFrameiOSWidgets` | `.appex` | Live Activity extension. Attaches `Shared/` + `TimeFrameiOSShared/`. **No `Core/`, no SwiftData.** |
| `TimeFrameiOSTests` | `.xctest` | iOS unit tests, hosted by the companion. |

## 5. ActivityKit adapter (`ActivityKitLiveActivityService`)

The concrete `LiveActivityService` (the M16 isolation protocol) injected into the M16
`LiveActivityCoordinator` on a normal launch; a `NoopLiveActivityService` is used under the unit-test
host (hermeticity). It is the **only** app-process ActivityKit importer. It:

- maps `LiveActivitySnapshot` → `Activity<TimeFrameLiveActivityAttributes>` request/update/end;
- is **idempotent per session id** (never a duplicate — ADR-073), and exposes `activeSessionIDs()`
  for launch reconciliation;
- derives an ActivityKit `staleDate` from the frozen `phaseTargetEndAt` (running only) — never a loop;
- swallows every failure (unsupported / unauthorized / throw): the timer runs on regardless.

The full chain: `TimerEngine → SessionCoordinator → LiveActivityCoordinator → LiveActivityContentMapper
→ ActivityKitLiveActivityService → Activity<TimeFrameLiveActivityAttributes>`.

## 6. Activity attributes & content

`TimeFrameLiveActivityAttributes: ActivityAttributes` (in `TimeFrameiOSShared/`) holds the **static**
per-session identity (mirrored from `LiveActivityIdentity`: `sessionID`, `taskName`,
`configurationName`, `sessionStartedAt`) and declares `typealias ContentState =
TimeFrameLiveActivityContent` — the **Milestone-16 neutral value reused verbatim** (ADR-072/078). No
new mutable state model, no independently ticking counter.

## 7. Live Activity lifecycle (reuses the M16 coordinator, unchanged)

| Event | Action |
| --- | --- |
| Session started | `Activity.request` (idempotent per session id) |
| Pause / Resume / Skip / auto interval boundary | `Activity.update` |
| Restart | `Activity.update` (M16 meaningful-transition hook) |
| Stop | `Activity.end` (immediate) |
| Completion / Interrupted | `Activity.end` (system-default dismissal, final content) |
| Launch / recovery | `reconcileOnLaunch()` → exactly one activity for a recovered session, none otherwise |

Duplicate prevention and reconciliation are the M16 coordinator's, keyed to `FocusSession.id`.

## 8. Dynamic Island & Lock Screen

`TimeFrameLiveActivity` (an `ActivityConfiguration`) renders every region from
`LiveActivityPresentation` (shared) + a `Text(timerInterval:)` repaint:

- **Lock Screen**: phase + task + progress, large countdown, control row.
- **Dynamic Island** — compact leading (phase icon), compact trailing (countdown), minimal (icon),
  expanded leading (phase), trailing (session progress), center (task), bottom (countdown + controls).

Accessibility-first: labels come from `LiveActivityPresentation.accessibilityLabel`, the countdown
carries `.updatesFrequently`, and no state is conveyed by colour alone.

## 9. Interactive controls (reuse the M15 seam — no second action path)

Live Activity buttons are `Button(intent:)`s bound to the **shared** Milestone-15 intents
(`WidgetPauseIntent`, `WidgetResumeIntent`, `WidgetSkipIntent`, `WidgetStopIntent`). The system runs
them in the app process, where the app registered a `WidgetControlActions` router wired to the one
`AppIntentSessionActions` seam. Chain: `Button(intent:) → WidgetControlActions → AppIntentSessionActions
→ SessionCoordinator → TimerEngine`. The Live Activity mutates nothing directly.

## 10. Device identity & cross-device running-session policy (ADR-063, reaffirmed on iOS)

Recovery is **device-local**: `SessionRepository.fetchRecoverableSession()` filters
`belongsToDevice(CloudDeviceIdentity.current)`, so a session running on another device is never
recovered as a local timer, never mutated, and never triggers a second timer. **No new code was
required** — the iOS companion inherits the M13 policy from `Core/`. `CloudDeviceIdentity` is a single
stable per-install UUID (no PII), reused unchanged.

## 11. CloudKit integration & the manual blocker

The iOS target uses the **same** SwiftData-native CloudKit mirroring path as macOS
(`PersistenceController.bootstrap`), the **same** App Group (`group.abirbarman.com.time-frame`), and
the **same** V6 schema — so history/statistics sync naturally once sync is enabled, and Statistics use
the one `StatisticsAggregator` over synced history. The iCloud **entitlement/container is intentionally
NOT added**: enabling real CloudKit sync requires a **paid Apple Developer team**; a personal team
cannot. Until then the store degrades safely to local (`PersistenceMode.fallback`), the timer is
unaffected, and **cross-device CloudKit sync is UNVERIFIED by design** (see §14).

## 12. Failure isolation

A Live Activity is an observer. Every `Activity.request/update/end` is best-effort and contained in
the adapter; an unsupported platform, a disabled/again-unauthorized user, or a throw yields no activity
and never reaches the timer. The `ProductionReadinessTests` prove no scheduling primitive exists in any
iOS presentation file, and the M16 failure-isolation suite (fake service throwing on every call) proves
the coordinator degrades cleanly.

## 13. Tests

- **macOS suite** (unchanged, still green): `ProductionReadinessTests` updated for `Core/` paths and
  the new **ActivityKit-boundary** assertion (allowed only in the iOS targets).
- **iOS suite** (`TimeFrameiOSTests`): `IOSLiveActivityTests` (attributes mirror identity; ContentState
  is the neutral type and round-trips; presentation mapping; accessibility label),
  `IOSCrossDeviceSessionPolicyTests` (device-local recovery — remote session never taken over),
  `IOSCompanionTests` (shared aggregator; deep-link navigation; inert no-op service).
- ActivityKit-facing lifecycle stays deterministically tested via the M16 fake service — no test
  depends on a real Dynamic Island being present.

## 14. Manual verification status

| Item | Status |
| --- | --- |
| macOS Debug/Release build, full macOS suite | see the Milestone 18 report |
| iOS Debug/Release build (simulator SDK) | see the report |
| iOS unit suite | see the report |
| Live Activity on a running simulator (Lock Screen / Dynamic Island visuals) | **NOT VERIFIED in this environment** — requires an interactive simulator/device session |
| Cross-device CloudKit sync | **BLOCKED** — requires a paid Apple Developer team + iCloud container |

## 15. Release requirements & remaining blockers

- **Paid Apple Developer team** for: the iCloud entitlement/container (real sync), device install +
  TestFlight, and App Store submission. A personal team builds for the simulator only.
- App icons/launch assets for the iOS app (a full asset catalog) before store submission.
- On-device Live Activity/Dynamic Island verification (hardware with a Dynamic Island).

## 16. What is intentionally deferred

- ~~iOS **home-screen** widgets~~ — **delivered in Milestone 20** (configurable small/medium/large
  Timer/Today/Statistics widget in the existing `TimeFrameiOSWidgets` extension, reusing the shared
  projection/App Group/config intent and the M15 control seam). See `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.
- ~~iOS local notifications~~ — **delivered in Milestone 20** (the neutral notification stack moved to
  `Core/Services/Notifications/` and is now shared by macOS + iOS). See
  `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.
- ActivityKit **push** updates (`pushType` is wired as `nil`; local updates only) — still deferred.
