# 26 — Production Readiness (Milestone 17)

Milestone 17 takes the feature-complete M16 codebase toward a **production-quality
release candidate**. It is a **hardening** milestone: no new user-facing features,
no architectural rewrites. Every architectural invariant established in M1–M16 is
preserved, and the milestone's output is a stronger, better-audited release
candidate — not a larger surface.

---

## 1. Scope

Hardening across: test-host hermeticity, an automated production-readiness audit,
migration robustness, large-history/stress coverage, accessibility, keyboard
navigation, integration-failure isolation, timer boundary edge cases, UI-state
safety, and a release-configuration audit + Release build.

Explicitly **not** in scope: new features, ActivityKit on macOS, an iOS target, a
custom CloudKit sync engine, telemetry/analytics, schema changes, or any rewrite of
`TimerEngine`/`SessionCoordinator`/SwiftData/WidgetKit/App Intents.

## 2. Baseline (start of M17)

| Property | Value |
|---|---|
| Debug build | **SUCCEEDED**, 0 warnings |
| Tests / suites | **602 tests / 122 suites**, all passing |
| Schema | **V6** |
| Deployment target | **macOS 27.0** |
| Toolchain | Swift 6.4 / Xcode 27 (`SWIFT_VERSION = 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |
| Git | root `time_frame/`, branch `main`, HEAD `32e8712 m10`; M11–M16 uncommitted (preserved) |

The Debug baseline was green before any M17 change. No git state was modified
(no init/commit/reset/checkout); all uncommitted M11–M16 work was preserved.

## 3. Hardening work implemented

### 3.1 Test-host hermeticity (production code)
`time_frameApp.init()` already skipped live seeding/recovery, CloudKit, App-Group
writes, and intent registration under the XCTest host. M17 **extracts that detection
into a pure, testable `Support/TestHostEnvironment.swift`** (`isHostingUnitTests`),
so hermeticity is now a *tested* regression, not only a code-reading guarantee.
Behaviour is identical to the previous inline check.

### 3.2 Automated production-readiness audit (new test suites)
`ProductionReadinessTests.swift` + `ProductionReadinessSupport.swift` scan the source
tree on disk (comments and string literals blanked; identifier-boundary aware, so
`openTimer(` never masquerades as `Timer(`) and assert, as a release gate:

- schema is **V6** (compile-linked) and all six models are present;
- **exactly one** production file schedules the heartbeat (`SessionCoordinator`); the
  engine and every presentation/integration layer contain **no** scheduling primitive;
- `TimerEngine` is declared once and constructed only by `SessionCoordinator`;
- observer integrations, `Shared/`, and the widget extension import **no** SwiftData
  and touch **no** `ModelContext`; no integration mutates the engine directly;
- **ActivityKit** is imported **only** in the iOS targets and **nowhere** on the macOS side
  (the app, `Core/`, `Shared/`, the macOS widget, and the tests) — this was "nowhere at all" at
  M17; Milestone 18 scoped it to the sanctioned iOS zone (ADR-079). **No** production file imports
  CloudKit / references `CKRecord`/`CKContainer`;
- the timer core uses no `fatalError`/`try!`/`as!`;
- the live process is detected as an XCTest host and launch guards live seeding/recovery.

### 3.3 Migration & store robustness (new)
`StoreMigrationRobustnessTests.swift` exercises the *actual* upgrade policy —
**rebuild-on-incompatibility** (ADR-016/061) — hermetically against temporary stores:
an incompatible legacy store is rebuilt into a usable V6 store; a corrupt store file
is rebuilt, not crashed on; every model round-trips across a real close/reopen with no
data loss; the additive optional `originatingDeviceID` defaults to `nil` and legacy
(nil-origin) rows stay device-local (ADR-063). A small **testability seam**
(`PersistenceController.openOnDiskContainer(schema:configuration:)`) was extracted so the
rebuild path is exercisable against a temp URL — production behaviour is unchanged.

### 3.4 Large-history / stress (new)
`LargeHistoryStressTests.swift`: the pure `StatisticsAggregator` over **5,000** and
**12,000** intervals with exact, reproducible totals; and the real
`StatisticsRepository` fetch+map+aggregate over **1,000** persisted sessions / 4,000
intervals. Timing ceilings are deliberately generous (machine-dependent) and only guard
against pathological regressions; the value is the exact correctness assertions.

### 3.5 Accessibility (production code + new tests)
The app was already strongly accessible (combined countdown element with a spoken value,
charts with per-mark labels, state carried by text not colour). M17 adds the idiomatic
`.accessibilityAddTraits(.updatesFrequently)` to both live countdowns (`TimerDisplay`,
`MenuBarTimerView`) and locks in the pure accessibility-text helpers with
`AccessibilityTextTests.swift` (spoken durations, status/phase labels, menu-bar VoiceOver
description — never a bare `00:00`).

### 3.6 Keyboard navigation (new tests)
`TimerControls` already binds Space/Escape/R/→ with `.help()` tooltips and stable
accessibility identifiers, editors bind default/cancel actions, and setup binds
Cmd+Return with focus. `KeyboardNavigationAuditTests.swift` guards these against silent
removal.

### 3.7 Integration-failure isolation (new consolidated test)
Every integration already had a per-integration independence suite. M17 adds
`AllIntegrationsFailureIsolationTests.swift`: Calendar, Notifications, and the Widget
projection **all failing at once** — plus a deliberately throwing lifecycle observer —
while a full session runs start → completion and Stop preserves history. The timer stays
authoritative and persists correctly regardless.

### 3.8 Timer boundary & UI-state robustness (new tests)
`TimerBoundaryHardeningTests.swift`: remaining is never negative however far past an
interval end the clock runs; a backwards clock correction never corrupts the run and
self-heals forward; skip/stop exactly at a boundary; a 24-hour interval; a ten-year
sleep/wake gap converges to completion without hanging. `EmptyStateRobustnessTests`:
empty history yields zeros and `nil` (never NaN) ratios; a deleted-configuration session
shows a safe, non-empty label.

### 3.9 Release-configuration finding (production code)
The Release build surfaced one pre-existing **Release-only** warning (whole-module
optimisation): a spurious *"weak reference will always be nil"* at the Restart intent's
call site (the one control that transitively starts the heartbeat `Task { [weak self] }`).
Fixed by binding the `AppIntentSessionActions` value to a local so its lifetime spans the
call — behaviour identical, warning gone.

## 4. Release-configuration audit

| Item | Finding |
|---|---|
| App sandbox | **ON** (app + widget) |
| Hardened runtime | **ON** |
| Deployment target | macOS **27.0** (app + widget) |
| Bundle ids | `abirbarman.com.time-frame` / `…​.TimeFrameWidgets` / `…​Tests` — consistent |
| App Group | `group.abirbarman.com.time-frame` on both targets; matches `WidgetProjectionStore` |
| URL scheme | `timeframe` registered; matches `WidgetDeepLink` (`timeframe://`) |
| Widget embedding | `TimeFrameWidgets.appex` embedded via *Embed Foundation Extensions*; packaged & signed in Release |
| Calendar entitlement | `com.apple.security.personal-information.calendars` present (EventKit) |
| CloudKit / iCloud | **entitlement intentionally absent** — needs a paid Apple Developer team + iCloud container (ADR-060…062). App runs local-first; sync is not activated. |
| Live Activities | no `NSSupportsLiveActivities`, no ActivityKit — correct for native macOS (ADR-076) |
| Signing | Automatic, Apple Development, personal team `SUDJAF8XLZ` — **unchanged** |

## 5. Automated audit results

All production-readiness audits pass (schema V6; single timer authority; persistence,
widget, App Intent, CloudKit, and ActivityKit boundaries; test-host hermeticity).

## 6. Manual verification limitations

- **CloudKit production sync is not verified.** It requires a paid Apple Developer team,
  the iCloud entitlement, and a provisioned container — unavailable here. The app is
  proven to run local-first and to fall back safely (ADR-062); real cross-device mirroring
  is untested.
- **No Live Activity** exists to display on macOS (ADR-076); nothing to manually verify.
- **GUI/VoiceOver walkthrough** was not performed as an automated step; accessibility is
  verified through the pure-text helper tests and code audit, not a live screen-reader
  session. (The rendered-UI accessibility modifiers are asserted by source audit, not by a
  running AX tree.)
- Performance ceilings are machine-dependent; thresholds are intentionally generous.

## 7. Remaining release blockers

1. **CloudKit sync activation** — paid team + iCloud entitlement/container, then a real
   two-device sync verification pass. (Architecture is ready; transport is dormant.)
2. **Signing/notarization for distribution** — the project signs with a personal
   development team; Developer-ID signing + notarization is required for outside-App-Store
   distribution. Not changed in M17 (no account capability to do so).
3. A **live VoiceOver / Full-Keyboard-Access walkthrough** on device is recommended before
   release to complement the automated coverage.

None of these block the timer, the app's local functionality, or the build.

## 8. Commands used

```bash
# Debug build
xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame -destination 'platform=macOS' clean build
# Full test suite
xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame -destination 'platform=macOS' test
# Release build (app + embedded widget extension)
xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame -configuration Release -destination 'platform=macOS' clean build
# Build settings audit
xcodebuild -project time_frame/time_frame.xcodeproj -scheme time_frame -configuration Release -showBuildSettings
```

## 9. Final counts

| Property | Baseline | Final |
|---|---|---|
| Tests | 602 | **653** |
| Suites | 122 | **137** |
| New tests added | — | **51** (15 new suites) |
| Debug build | SUCCEEDED / 0 warnings | SUCCEEDED / 0 warnings |
| Release build | (not run) | **SUCCEEDED / 0 warnings** |
| Schema | V6 | **V6 (unchanged)** |

New test suites: `ProductionReadiness*` (schema/timer/boundary/platform/hermeticity),
`StoreMigrationRobustnessTests`, `LargeHistory*StressTests`, `AccessibilityText`/
`StatusLabel`/`MenuBarAccessibilityText`/`SpokenDuration`, `KeyboardNavigationAuditTests`,
`AllIntegrationsFailureIsolationTests`, `TimerBoundaryHardeningTests`,
`EmptyStateRobustnessTests`.

## 10. Invariants preserved

One `TimerEngine`; one `SessionCoordinator` control seam; timestamp-authoritative time;
widgets/App Intents read-only/thin; CloudKit below persistence; schema **V6**; no
ActivityKit on macOS; test host cannot touch the user's real session. See ADR-077.
