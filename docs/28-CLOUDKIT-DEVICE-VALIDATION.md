# 28 — CloudKit Activation, Cross-Device Sync & Device Validation (Milestone 19)

Milestone 19 is a **production-validation** milestone. It does **not** add a second
timer, a second store, a custom sync engine, or any new runtime architecture. It
takes the CloudKit architecture built in Milestone 13 (and reaffirmed on iOS in
Milestone 18) and does three honest things:

1. Makes the **CloudKit capability** an explicit, unit-testable seam — so "this build
   cannot use CloudKit" is a first-class, tested decision rather than something only
   discovered when a doomed cloud container fails to build.
2. Proves the **cross-device / merge / fallback** behaviour deterministically, with no
   real iCloud account.
3. Strengthens the **source-boundary release-gate audit** with CloudKit / App-Group /
   deep-link / honesty checks.

> **Status — read this first.** The signing team on this machine is a **personal
> (free) Apple Developer team** (`SUDJAF8XLZ`, "Abir Barman"). Apple does **not** allow
> a personal team to use the iCloud/CloudKit capability. Therefore:
>
> - The iCloud/CloudKit **entitlement is deliberately NOT added** to any target — a
>   fabricated entitlement would simply fail to sign and break the build.
> - **Real CloudKit synchronization is NOT verified** and is a documented **paid-team
>   blocker**.
> - **Physical-device Live Activity / Dynamic Island / VoiceOver on real hardware is
>   NOT verified** — no physical device was available in this environment.
> - Everything that *can* be done without a paid team **is** done: the capability seam,
>   deterministic cross-device tests, the boundary audits, and the docs.
>
> This honesty is enforced by tests: `M19CloudKitHonestyTests` **fails the build** if an
> iCloud entitlement ever appears while the capability constant still says the build is
> not entitled (or vice-versa).

---

## 1. M19 scope

| Area | Delivered | Blocked / deferred |
| --- | --- | --- |
| CloudKit capability seam | Yes — `CloudKitCapability` (Core/Services/Cloud) | — |
| Launch-time mode resolution | Yes — app + iOS consult the seam | — |
| Cross-device deterministic tests | Yes — `CrossDeviceSyncValidationTests` | — |
| Merge / frozen-field integrity | Yes — tested | — |
| Running-session device-locality | Yes — tested (macOS + iOS) | — |
| Statistics from merged history | Yes — tested | — |
| Fallback never blocks timer | Yes — tested | — |
| Source-boundary audits | Yes — `ProductionReadinessM19Tests` | — |
| Real CloudKit sync (2 devices) | — | **Paid-team blocker** |
| Physical-device Live Activity | — | **No device available** |
| iOS Home Screen widget | — | **Deferred (see §14)** |
| iOS local notifications | — | **Deferred (see §14)** |

---

## 2. CloudKit architecture (unchanged from M13/M18)

```
SwiftUI Views (macOS app + TimeFrameiOS)
   ↓
SessionCoordinator          ← the one control seam (CloudKit-free)
   ↓
TimerEngine                 ← timestamp-authoritative (imports no CloudKit)
   ↓
SwiftData repositories      ← Configuration / Session / TaskTemplate / SessionPlan
   ↓
SwiftData ModelContainer    ← ModelConfiguration(cloudKitDatabase: .automatic)
   ↓
CloudKit private database   ← native SwiftData mirroring, below the domain
   ↓
the same user's other Apple devices
```

CloudKit sits **below the repositories**, provided entirely by SwiftData's native
mirroring. No file imports CloudKit; there is no `CKRecord`/`CKContainer`, custom sync
engine, or polling loop (ADR-060). See `docs/22-ICLOUD-CLOUDKIT.md` for the full M13
reference.

### The capability seam (new in M19; ADR-080)

`Core/Services/Cloud/CloudKitCapability.swift` adds, all CloudKit-free:

- `CloudKitCapabilityProviding` — protocol reporting whether **this build** carries the
  iCloud/CloudKit entitlement (a build/provisioning fact).
- `BuildCloudKitCapabilityProvider` — the production provider; returns
  `CloudKitCapability.entitledInThisBuild`.
- `CloudKitCapability.entitledInThisBuild` — the **single honest switch**. `false` on the
  shipping personal-team build. Flip to `true` only in a build actually signed with the
  iCloud entitlement + container (paid team).
- `CloudKitCapability.resolve(entitled:syncEnabled:account:)` — the pure resolver that
  maps the three inputs to a `Decision { requestedMode, blocker }`. CloudKit is requested
  **only** when entitled **and** sync is on **and** an iCloud account is available.

The app launch (`time_frameApp.init`) and the iOS app resolve the mode through this seam,
so both platforms decide identically and testably. Because `entitledInThisBuild == false`
today, both platforms resolve to `.local` — the app never attempts a cloud container it
cannot create — while the store still degrades safely if anything else fails (ADR-062).

---

## 3. Account / capability prerequisites

Real CloudKit sync requires **all** of:

1. A **paid** Apple Developer Program membership (personal/free teams cannot use iCloud).
2. The **iCloud** capability enabled for the App ID, with **CloudKit** checked.
3. A CloudKit **container** (see §4).
4. The iCloud **entitlement** in each target's `.entitlements` (see §5).
5. The user **signed in to iCloud** on the device, with iCloud Drive enabled.

Only #5 is a runtime condition (surfaced by `CloudAccountStatusProviding`). #1–#4 are the
paid-team build/provisioning conditions represented by `entitledInThisBuild`.

---

## 4. Container configuration

Use the documented container identifier consistent with the bundle id:

```
iCloud.abirbarman.com.time-frame
```

SwiftData reads the container from the app's iCloud entitlement when
`cloudKitDatabase: .automatic` is used, so **no container id is hard-coded** in Swift.
The **same** container must be configured on **all** targets that mirror data (the macOS
app and `TimeFrameiOS`). The macOS/iOS widget extensions and the iOS Live Activity
extension read only the **local App Group projection** and do **not** need the CloudKit
container.

> **Manual, unfaked:** creating the container and deploying its schema to the CloudKit
> **Production** environment happens in the Apple Developer portal / Xcode CloudKit
> Console with a paid team. This has **not** been performed.

---

## 5. Entitlement configuration

When a paid team is available, add to `time_frame/time_frame.entitlements` **and**
`TimeFrameiOS.entitlements` (the two data-owning targets):

```xml
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.abirbarman.com.time-frame</string></array>
```

Then set `CloudKitCapability.entitledInThisBuild = true`. The App Group entitlement
(`group.abirbarman.com.time-frame`) is **already present** on all four targets and must
stay unchanged (invariant #19).

> Until then these keys are **absent by design**. `M19CloudKitHonestyTests` asserts they
> are absent and that `entitledInThisBuild == false`, so the two can never silently
> disagree.

---

## 6. Schema V6 compatibility

- The active schema is **V6** and **stays V6** — CloudKit forced no migration (M19 adds
  no model change).
- **No `#Unique` constraints** anywhere (CloudKit rejects uniqueness) — asserted by
  `CloudKitModelCompatibilityTests` and `M19CloudKitWiringTests`.
- Every stored property is **optional or defaulted**, and every relationship is optional
  or defaulted with an explicit delete rule (`.cascade` for owned intervals/items,
  `.nullify` for references) — the CloudKit requirement. Verified by round-trip tests.
- `FocusSession.originatingDeviceID` is an **additive optional** used only for the
  device-local running-session policy (ADR-063), not for timing.

---

## 7. Cross-device running-session policy (ADR-063, reaffirmed)

Timer execution is **device-local**. A running/paused session may sync to another device
as a visible row, but:

- `SessionRepository.fetchRecoverableSession()` filters by `originatingDeviceID`, so a
  device only ever recovers **its own** session.
- A session from another device is **never** recovered into a second live timer and is
  **never mutated** here (mutating it would sync back and interrupt the owner).
- A `nil` origin (legacy rows) is treated as local for backward compatibility.

Tested by `RunningSessionSyncTests`, `IOSCrossDeviceSessionPolicyTests`, and M19's
`CrossDeviceSyncValidationTests.runningSessionIsDeviceLocal`.

---

## 8. Offline behaviour

- Reads and writes always hit the **local** store immediately; CloudKit mirroring is a
  background, eventual transport. The timer never waits on the network.
- With sync on but iCloud unreachable, the store comes up in `.fallback` mode over the
  **preserved local store** (never an empty in-memory one; ADR-062). All controls work.
- Tested by `OfflinePersistenceTests` and
  `CrossDeviceSyncValidationTests.timerWorksUnderCloudFallback`.

---

## 9. Merge behaviour

CloudKit last-writer-wins merges at the record level. Time Frame's history is written to
be **merge-safe**:

- Historical/frozen fields (`configurationName`, per-interval `plannedDuration`/`phase`,
  `startedAt`/`endedAt`) are **frozen at write time** and never rewritten, so a rename or
  delete of a live configuration on any device never changes historical display.
- Deleting a configuration **nullifies** the session's reference (never deletes history).
- Statistics are a **pure re-derivation** of merged history, so two devices that see the
  same merged rows compute the same snapshot.

Tested by `CrossDeviceSyncValidationTests` (frozen-name survives rename/delete; statistics
from merged history) and `HistoricalIntegrityTests`.

---

## 10. Live Activity device-local policy

Live Activities are **iOS-only** (ActivityKit is `@available(macOS, unavailable)`), a
**read-only presentation** keyed to `FocusSession.id`, and **device-local**: they are
never a cross-device timer. macOS remains ActivityKit-free (enforced by
`ProductionReadinessPlatformTests`). See `docs/25` and `docs/27`. M19 changes nothing here.

---

## 11. Physical-device test procedure (NOT performed — no device available)

When a physical iPhone/iPad + paid team are available, verify and record:

1. Install & launch; create a session; start / pause / resume / skip / stop / restart.
2. Kill & relaunch mid-session → the **same** device recovers exactly one live timer.
3. Start a session → a Live Activity appears; check Lock Screen presentation.
4. On Dynamic Island hardware: compact leading / trailing, minimal, expanded.
5. Interactive Live Activity controls mutate the **same** `SessionCoordinator`
   (Pause/Resume/Skip/Restart/Stop) via the M15 intent seam.
6. Countdown follows the timestamp-authoritative engine (no drift, no second clock).
7. Relaunch/recovery produces **no duplicate** Live Activity; stale ones are ended.
8. VoiceOver reads the countdown and controls; Dynamic Type scales.

> None of the above has been observed on real hardware in this environment. Do not treat
> any of it as verified.

---

## 12. CloudKit cross-device test procedure (NOT performed — paid-team blocker)

With CloudKit genuinely enabled on two devices signed into the same iCloud account:

1. Create a historical session on Device A → confirm it appears on Device B.
2. History and Statistics **converge** on both.
3. Rename/delete a configuration → historical frozen names stay correct on both.
4. Start a session on Device A → Device B does **not** recover or control it.
5. Stop it on Device A → the completion eventually appears on Device B.
6. Drop the network → offline local control works → reconnect → sync resumes.
7. Never run a destructive store reset on real data.

---

## 13. Failure / fallback behaviour

| Situation | Behaviour | Test |
| --- | --- | --- |
| No entitlement (this build) | Local-first; `blocker = .cloudKitUnavailable` | `CloudKitCapabilityTests` |
| Sync off | Local; `blocker = .syncDisabled` | `CloudKitCapabilityTests` |
| No iCloud account | Local; `blocker = .accountUnavailable` | `CloudKitCapabilityTests` |
| CloudKit init throws | `.fallback` over preserved local store; timer fully usable | `CrossDeviceSyncValidationTests` |
| Corrupt local store | Rebuild once (on-disk) or in-memory last resort | `StoreMigrationRobustnessTests` |
| All integrations fail | Timer unaffected | `AllIntegrationsFailureIsolationTests` |

A CloudKit failure can **never** stop or corrupt the timer, lose local data, or block a
control.

---

## 14. Widget & notification status

- **Widgets** remain **read-only projections** over the **local App Group**
  (`group.abirbarman.com.time-frame`); they import no SwiftData and no CloudKit and never
  construct a timer (asserted by the boundary audits). The App Group id is identical
  across all four entitlements files (`M19AppGroupConsistencyTests`).
- **A dedicated iOS Home Screen widget is DEFERRED** (see §14 of the report / Deferred
  work): the iOS widget extension currently hosts the Live Activity only, and the
  configurable Home-Screen widget views live in the macOS widget target. Adding an iOS
  Home Screen widget cleanly requires target-membership work that is out of scope for a
  validation milestone and must not compromise the CloudKit/device-validation focus.
- **iOS local notifications are DEFERRED** for the same reason (the macOS notification
  service is app-target-only; porting it to iOS is a feature, not validation).

Both are deferred **explicitly** rather than compromising the milestone's architecture.

---

## 15. Accessibility validation

- The two live countdowns carry `.accessibilityAddTraits(.updatesFrequently)` (M17).
  Static a11y text is covered by `AccessibilityTextTests`.
- **VoiceOver / Dynamic Type on real hardware is NOT verified** in this environment.

---

## 16. Manual verification results

| Check | Result |
| --- | --- |
| macOS Debug build | Yes — succeeds, 0 warnings |
| macOS Release build | Yes — succeeds, 0 warnings |
| macOS full test suite | Yes — passes (M13/M17 + new M19 suites) |
| iOS Debug build | Yes — succeeds, 0 warnings |
| iOS Release build | Yes — succeeds, 0 warnings |
| iOS simulator tests | Yes — pass (incl. new iOS capability suite) |
| App Intents metadata extraction | Yes — succeeds |
| Widget extension embed | Yes — builds & embeds |
| Real CloudKit sync | No — **blocked** (paid team) |
| Physical-device Live Activity | No — **not observed** (no device) |

(Exact counts are in the Milestone 19 Completion Report.)

---

## 17. Blocked / unverified items

- **Real CloudKit synchronization across two devices** — blocked on a paid Apple
  Developer team + iCloud container deployment.
- **Physical-device Live Activity, Dynamic Island, VoiceOver-on-device, TestFlight, App
  Store signing** — not observed; no physical device / distribution signing available.
- **CloudKit schema deployment to Production** — a manual CloudKit Console step, not
  performed.

None of these were faked. The code is production-ready and the switch is a single
constant + entitlement.

---

## 18. Exact steps required outside the code environment

1. Enroll in the **paid** Apple Developer Program; select the paid team in Xcode Signing.
2. In the Apple Developer portal (or Xcode → Signing & Capabilities), enable **iCloud →
   CloudKit** for both `abirbarman.com.time-frame` (macOS) and the iOS app id, and create
   the container `iCloud.abirbarman.com.time-frame`.
3. Add the iCloud entitlement keys (see §5) to `time_frame.entitlements` and
   `TimeFrameiOS.entitlements`.
4. Set `CloudKitCapability.entitledInThisBuild = true`.
5. Deploy the SwiftData/CloudKit schema to the **Production** environment via the CloudKit
   Console.
6. Sign in to iCloud on two devices with the same account and run the §12 procedure.
7. Perform the §11 physical-device Live Activity checks.

> **Milestone 20 note.** M20 (iOS Home Screen widgets + local notifications) adds **no** CloudKit
> dependency: `CloudKitCapability.entitledInThisBuild` stays **`false`**, no iCloud entitlement or
> container is added, and the iOS widget reads only the **local** App Group projection. The
> `ProductionReadinessM20Tests` re-assert no-CloudKit-import across the macOS + iOS roots and schema
> **V6**. Real cross-device CloudKit sync remains a documented, unfaked paid-team blocker. See
> `docs/29-IOS-WIDGETS-NOTIFICATIONS.md`.
