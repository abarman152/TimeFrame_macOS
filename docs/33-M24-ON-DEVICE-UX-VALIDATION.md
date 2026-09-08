# 33 — Milestone 24: Product Identity, On-Device UX Validation & Final Polish

Milestone 24 is a **product-identity + validation + polish** milestone. It ships the app's name and
logo, validates the presentation surfaces built in M11–M23 as far as the environment allows, hardens
accessibility, and makes the Control Center quick-start catalog refresh event-driven. **It adds no
runtime architecture** — there is still exactly one `TimerEngine`, one `SessionCoordinator`, one
`AppIntentSessionActions` mutation seam, one App Group, and the SwiftData schema stays **V6**
(ADR-098).

See also: `docs/31-CONTROL-CENTER-CONTROLS.md`, `docs/32-CONFIGURABLE-CONTROL-CENTER.md`,
`docs/26-PRODUCTION-READINESS.md`, and `docs/DECISIONS.md` (ADR-096/097/098).

---

## 1. Product identity

The product name — everywhere the OS shows it to a user — is **Time Frame** (two words, capital T,
capital F). Internal identifiers are deliberately **unchanged**: the Swift module / target names
(`time_frame`, `TimeFrameiOS`, `TimeFrameWidgets`, `TimeFrameiOSWidgets`), the bundle identifier
(`abirbarman.com.time-frame`), the App Group (`group.abirbarman.com.time-frame`), the URL scheme
(`timeframe://`), and the SwiftData schema are all as they were (ADR-096).

## 2. App name

| Surface | Mechanism | Value |
| --- | --- | --- |
| macOS app (Finder, menu bar, About) | `INFOPLIST_KEY_CFBundleDisplayName` (build setting, both configs) | **Time Frame** |
| iOS/iPadOS app (Home Screen) | `CFBundleDisplayName` in `TimeFrameiOS-Info.plist` | **Time Frame** |
| macOS widget | `.configurationDisplayName("Time Frame")` | **Time Frame** |
| iOS Home Screen / Lock Screen widgets | `.configurationDisplayName("Time Frame")` | **Time Frame** |
| Control Center controls | `.displayName(…)` / `.description(…)` | "Time Frame Timer", "Start Focus Timer", "Stop Timer", "Quick-Start Timer" |
| Menu bar / Settings / Notifications / Calendar strings | Swift string literals | "Time Frame" |

**Fix applied.** The macOS app previously had **no** `CFBundleDisplayName` override, so its user-facing
name resolved to `PRODUCT_NAME` = `time_frame`. M24 adds
`INFOPLIST_KEY_CFBundleDisplayName = "Time Frame"` to both macOS configs. Verified in the built bundle:
`Contents/Info.plist → CFBundleDisplayName = "Time Frame"`.

**Polish applied.** The macOS Settings ▸ About row previously read a stale developer string
("Milestone 16"). It now shows the real `CFBundleShortVersionString` ("Version 1.0"), read from the
bundle so it never goes stale.

No user-facing occurrences of the disallowed variants `TimeFrame`, `time_frame`, `Time-Frame`, or
"Time Frame App" exist. (Those spellings survive only as internal identifiers/module names and in code
comments, which is correct.)

## 3. Logo

The user supplied **one** logo: `tf_logo.png`, **1024×1024**, PNG, opaque (no alpha), a black field
with a white "TF". It is the single source artwork for the entire application identity.

- **One logo.**
- **Same logo in Light Mode.**
- **Same logo in Dark Mode.**
- **No alternate dark logo, no tinted logo, no recolor, no inversion.** The artwork is used unaltered.

The only processing performed is the **technically necessary rasterization** to the sizes Apple's icon
slots require (see §4). Every generated raster is the same artwork at a different resolution — there are
no design variants (ADR-096).

## 4. App icon asset placement

Each platform target owns an `AppIcon` asset catalog. The logo lives there.

```
time_frame/time_frame/Assets.xcassets/AppIcon.appiconset/     (macOS)
  Contents.json
  icon_16x16.png  icon_16x16@2x.png  icon_32x32.png  icon_32x32@2x.png
  icon_128x128.png  icon_128x128@2x.png  icon_256x256.png  icon_256x256@2x.png
  icon_512x512.png  icon_512x512@2x.png            ← 10 raster slots (16…1024 px)

time_frame/TimeFrameiOS/Assets.xcassets/AppIcon.appiconset/   (iOS/iPadOS — created in M24)
  Contents.json
  AppIcon-1024.png                                 ← single 1024 "single-size" universal slot
```

- **macOS** keeps the classic mac icon ladder (16/32/128/256/512 at @1x/@2x). All ten PNGs are the
  same artwork downscaled from the 1024 source with `sips`. The macOS app target already referenced
  `AppIcon` (`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`); M24 only supplied the previously-missing
  raster files and the filename-referencing `Contents.json`.
- **iOS/iPadOS** uses the modern single-size universal AppIcon: one 1024×1024 image that iOS
  automatically downscales and corner-masks for every size and idiom (iPhone, iPad, Settings,
  Spotlight, App Store). The iOS target had **no** asset catalog before M24 — the catalog was created,
  and `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` was added to both iOS configs.

Both catalogs were verified in the compiled products: the macOS `Assets.car` contains an `AppIcon`
image set and `Contents/Info.plist → CFBundleIconName = AppIcon`; the iOS build compiles `AppIcon-1024`
into its `Assets.car` and injects `CFBundleIcons`.

## 5. Light / Dark same-logo policy

Neither `Contents.json` declares an `"appearances"` split. A single image with **no** appearance
specifier is used by the system for light, dark, and tinted contexts alike. This is the mechanism by
which "the same logo serves Light and Dark" is expressed **without** creating a second asset
(ADR-096). `ProductionReadinessM24Tests` fails the build if any `*Dark*`/`*Light*`/`*tinted*` icon set
or an `"appearances"` key ever appears.

## 6. Control Center

M23 shipped four controls in the **iOS** `TimeFrameiOSWidgets` extension:
`TimeFramePrimaryControl` (adaptive Start/Pause/Resume/Skip), `TimeFrameStartControl`,
`TimeFrameStopControl`, and the configurable `TimeFrameQuickStartControl`
(`AppIntentControlConfiguration`, user picks which saved timer to start). M24 validated them **as far
as the environment permits**:

- **AUTOMATED / SIMULATOR:** the control metadata (`kind`, `displayName`, `description`), the
  `AppIntentControlConfiguration`, the `QuickStartTimerEntity` resolution from the App Group catalog,
  the pure `ControlCenterPresentation`/`QuickStartControlPresentation` decision layer, and the routing
  chain (`ControlWidgetButton → App Intent → WidgetControlActions → AppIntentSessionActions →
  SessionCoordinator`) are exercised by the iOS test suite and build into the extension. Configuration
  identity (rename keeps id, delete fails safe, recreate gets a fresh id) is covered by
  `ProductionReadinessM24Tests` and the M23 suites.
- **NOT MANUALLY VERIFIED (GUI/physical device):** placing a control via Settings ▸ Control Center ▸
  Add a Control, and the live tap behaviour in the Control Center overlay, were **not** manually
  verified in this environment. *Control Center API, metadata, routing and simulator tests verified;
  GUI placement/tap behavior not manually verified in this environment.*

## 7. Quick-start configuration

The configurable quick-start control (M23) is unchanged in shape. The app re-resolves the
**authoritative** configuration by stable `UUID` at tap time through
`AppIntentSessionActions.startSession(configurationID:)`, so a rename or duration change takes effect
on the next tap, a deleted configuration fails safely
(`TimeFrameIntentError.configurationUnavailable`), and a nil selection starts the default. M24 adds no
new path — it only makes the *picker's catalog* fresher (§8).

## 8. Catalog refresh (ADR-097)

Before M24 the quick-start picker catalog (`QuickStartCatalog` in the App Group) was published **once**
at launch. M24 makes it **event-driven** without any polling, timer, or second store:

- `ConfigurationRepository` gained a neutral, opaque `onChange: (@MainActor () -> Void)?` hook fired
  after every successful mutation (create / update / delete / duplicate / setDefault / seed). The
  persistence layer knows nothing about widgets — it just fires an opaque event, preserving the
  downward-only dependency rule.
- `SessionCoordinator.init` forwards the hook (a new optional parameter, default `nil`) to the
  repository. The coordinator owns no widget knowledge; it only threads the closure through.
- Each **app** (macOS and iOS) wires the hook to `QuickStartCatalogWriter.refresh(…)`. It is
  suppressed under the XCTest host (hermeticity — no App Group writes during tests, ADR-077) and is
  best-effort (a failed write never disturbs the app or the timer).
- The one-time launch publish is retained (it covers a normal launch where nothing changed), so the
  two mechanisms together keep the catalog current: publish once on launch, republish on every config
  change.

The App Group catalog remains a **projection/cache**; the authoritative configuration remains the
app's SwiftData domain model. No polling loop, no new persistence store, no Control Center database
(ADR-097). `ProductionReadinessM24Tests` proves the hook fires on mutations, does **not** fire on a
rejected create, and is safe when nil.

## 9. Home Screen widgets

The macOS widget and the iOS Home Screen widget (M11/M14/M20) were validated, not redesigned. Small /
medium / large families, Timer / Today / Statistics modes, configuration through
`TimeFrameWidgetConfigurationIntent`, projection freshness on meaningful transitions, the
`Text(timerInterval:)` countdown between frozen anchors (running / paused / completed), malformed
projection handling, and the M15 interactive control seam are all covered by the existing macOS and
iOS suites, which remain green. No widget was rewritten.

## 10. Lock Screen widgets

The iOS `TimeFrameLockScreenWidget` (M21) — families `.accessoryCircular`, `.accessoryRectangular`,
`.accessoryInline` — was validated: running/paused countdown, completed state, stale projection and
missing-anchor degradation via the pure `AccessoryWidgetPresentation`, and read-only tap-to-open. No
change.

## 11. StandBy

StandBy is **not** a separate WidgetKit API — it reuses the existing `.systemSmall` / `.systemMedium`
Home Screen widget families. M24 confirmed the system-family design remains appropriate for StandBy;
no fake "StandBy API" was invented (consistent with M21).

## 12. Live Activity

ActivityKit is **iOS-only** (three iOS files — attributes, adapter, UI — and nowhere on macOS/`Core/`/
`Shared/`, enforced by `ProductionReadinessTests`). The M18 Live Activity code path — start / update /
end, per-`FocusSession.id` duplicate prevention, `staleDate`, pause/resume/skip/stop, completed and
interrupted states, and the Dynamic Island + Lock Screen presentations — is covered by the iOS suite
and builds into `TimeFrameiOSWidgets`. **Physical-device Dynamic Island / Live Activity rendering was
not verified** (no physical device in this environment; a documented, unfaked blocker).

## 13. Notifications

The shared notification stack (`Core/Services/Notifications/`, M20) — authorization / denied handling,
scheduled interval-boundary notifications from **frozen anchors** (`UNTimeIntervalNotificationTrigger`,
one per boundary, never a per-tick clock), completion notification, cancellation/reconciliation,
duplicate prevention (deterministic identifiers), action routing back through `SessionCoordinator`, and
failure isolation — is covered by the existing suites and unchanged. Notifications stay anchored to
authoritative interval timestamps; no countdown timer or polling was added.

## 14. Accessibility

M24 performed a review pass. The codebase already has mature coverage (a VoiceOver-labeled countdown
with `.accessibilityAddTraits(.updatesFrequently)` from M17; verb-labeled controls via
`Label("Pause", systemImage:)` etc.; full menu-bar phrasing in `MenuBarStatusPresentation`; pure
accessibility strings in the Control Center and accessory presentations; per-view labels/values/hints
across the app). Key states are conveyed without relying on color: the countdown carries the phase +
remaining time as its accessibility value, and controls carry action names. No genuine gaps were found
in the core surfaces, so no churn was introduced (consistent with "no unrelated changes"). Examples of
existing phrasing: "Start Deep Work Timer", "Time Frame, focus, 24 minutes remaining", "Time Frame,
paused, 12 minutes remaining", "Time Frame, session complete".

## 15. Dynamic Type

The UI uses system text styles and flexible SwiftUI layouts throughout (no fixed pixel dimensions used
to force a screenshot-perfect layout). Primary information — the countdown, phase, and controls —
remains readable at larger content sizes. No change was required.

## 16. iPhone validation

Automated: the iPhone (iOS simulator) test suite. GUI/visual placement and physical-device behaviour
were not manually verified in this environment (see §19).

## 17. iPad validation

Automated: the iPad (iOS simulator) test suite. Same manual-verification limitations as §16.

## 18. macOS validation

Automated: the full macOS suite, Debug + Release builds, App Intents metadata extraction, and the M24
boundary audits. The macOS app icon and display name were verified in the compiled `.app` bundle.

## 19. App Intents metadata

The App Intents metadata for the app and widget targets is generated by the build
(`ExtractAppIntentsMetadata`) and validated (`--validate-assistant-intents`). The M15/M22/M23 intents —
including `QuickStartTimerEntity`, `QuickStartControlConfigurationIntent`, and
`TimeFrameQuickStartIntent` — remain discoverable/valid. M24 introduced no new intent.

## 20. Release build validation

macOS Debug, macOS Release, iOS Debug, and iOS Release all build with **0 compiler warnings**. Builds
were run **serially** (the project has previously hit `build.db` locking under concurrent xcodebuild).
Compiler warnings are counted separately from CoreData runtime logs, simulator logs, and test
diagnostic output.

## 21. CloudKit status

**CloudKit remains disabled because the project is using a Personal/Free Apple Developer team.**
`CloudKitCapability.entitledInThisBuild == false`, no iCloud entitlement is added, and no CloudKit
container is created. Both apps launch local-first and the store degrades safely to local (ADR-062/080).
M24 changes none of this and works entirely without CloudKit.

## 22. Manual verification limitations

Clearly distinguished:

- **AUTOMATED (deterministic tests):** macOS + iOS suites, including `ProductionReadinessM24Tests`.
- **SIMULATOR:** iPhone/iPad build + test on the iOS simulator; app icon and name compiled into the
  bundles.
- **GUI (not performed):** manual placement/tap of Control Center controls; manual Home Screen / Lock
  Screen widget placement; manual Dynamic Type slider sweeps.
- **PHYSICAL DEVICE (not performed):** real Live Activity / Dynamic Island rendering, physical VoiceOver
  pass, real 2-device CloudKit sync.

Nothing above claimed as "verified" was left untested.

## 23. Remaining blockers

- Real CloudKit cross-device sync — needs a **paid** Apple Developer team (documented since M13/M19).
- Physical-device Live Activity / Dynamic Island / VoiceOver — needs hardware.
- Manual Control Center / widget GUI placement — needs an interactive device/simulator GUI session.

## 24. Deferred work

- On-device screenshot capture and an App Store screenshot set.
- A dedicated iOS About screen with a version row (macOS has one; iOS defers).
- A marketing-appearance macOS icon with HIG rounded-rect padding (the supplied artwork is used
  as-is by explicit instruction — no padding/masking was applied).

## 25. Recommended M25

App Store submission readiness: privacy nutrition labels, App Store screenshots + preview, marketing
copy, a paid-team CloudKit enablement pass (flip `entitledInThisBuild`, add the entitlement/container,
verify 2-device sync), and an on-device accessibility + Dynamic Type audit on real hardware.

---

## Verification

Full matrix run **serially** (2026-08-17; Xcode 27, Swift 6.4, macOS 27 / iOS 27 SDK):

| Step | Result |
| --- | --- |
| macOS Debug build | `** BUILD SUCCEEDED **`, 0 warnings |
| macOS tests | `** TEST SUCCEEDED **`, **808 tests / 181 suites** (was 789/176), 0 warnings |
| macOS Release build | `** BUILD SUCCEEDED **`, 0 warnings |
| iOS Debug build (iPhone 17 sim) | `** BUILD SUCCEEDED **`, 0 warnings |
| iPhone tests (iPhone 17 sim) | `** TEST SUCCEEDED **`, 101 tests, 0 warnings |
| iPad tests (iPad Pro 11-inch M5 sim) | `** TEST SUCCEEDED **`, 101 tests, 0 warnings |
| iOS Release build (generic iOS sim) | `** BUILD SUCCEEDED **`, 0 warnings |
| App Intents metadata | `Metadata.appintents` emitted for all four targets (macOS app + widget, iOS app + widget); `QuickStartTimerEntity`, `QuickStartControlConfigurationIntent`, `TimeFrameQuickStartIntent`, `WidgetStartIntent`, `TimeFramePrimaryControlIntent` all present |
| macOS bundle | `CFBundleDisplayName = "Time Frame"`, `CFBundleIconName = AppIcon`, `Assets.car` carries the AppIcon ladder |
| iOS bundle | `CFBundleDisplayName = "Time Frame"`, `CFBundlePrimaryIcon → CFBundleIconName = AppIcon`, `Assets.car` rendition from `AppIcon-1024.png` |
| Widget embedding | `TimeFrameWidgets.appex` embedded in the macOS app; `TimeFrameiOSWidgets.appex` in the iOS app |

Compiler-warning counts above are `warning:`-line counts, kept separate from CoreData runtime logs,
simulator logs, and test diagnostics. The iPad count (101) differs by one from the M23-noted 100 because
an idiom-conditional test runs on the iPad Pro 11-inch (M5) simulator used here; **no iOS test was added
or removed in M24**, and both idioms report 0 failures.

**Git.** Read-only status only. During the session an external commit (`0e27214 "update"`, authored
13:58) captured the prior M11–M23 working-tree changes; it was **not** created by this work (only
read-only git commands were run), and the M24 changes remain uncommitted. No prior work was removed.
