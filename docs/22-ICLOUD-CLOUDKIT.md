# 22 — iCloud / CloudKit Synchronization (Milestone 13)

Time Frame can synchronize its persistent SwiftData data across a user's Apple
devices using CloudKit, while remaining **local-first**, **offline-capable**, and
**timer-authoritative**. This document is the reference for how that works, what it
requires, and — honestly — what has and has not been verified.

> **Status:** Code and automated tests are complete and green. **Production CloudKit
> synchronization was _not_ manually verified** on this machine because the signing
> team is a *personal (free)* Apple Developer team, which Apple does not allow to use
> the iCloud/CloudKit capability. See [Manual setup](#15-manual-setup-requirements)
> and [Production deployment](#16-production-cloudkit-deployment-requirements).
>
> **Milestone 18 update:** the iOS/iPadOS companion (`TimeFrameiOS`) uses the **same** SwiftData-native
> CloudKit mirroring path, the **same** App Group (`group.abirbarman.com.time-frame`), and the **same**
> V6 schema, so once the paid-team iCloud capability is enabled, history/statistics sync across Mac and
> iPhone/iPad with no extra code. The **device-local running-session policy (ADR-063) is reaffirmed on
> iOS**: `fetchRecoverableSession` only recovers this device's own session, so a session running on
> another device is never taken over. The iCloud entitlement is deliberately **not** added on iOS
> either, so the iOS store degrades safely to local until a paid team enables sync. Cross-device sync
> remains a documented, unfaked **manual blocker**. See `docs/27-IOS-COMPANION-LIVE-ACTIVITIES.md` §10–11.
>
> **Milestone 19 update:** the CloudKit *capability* is now an explicit, unit-tested seam
> (`Core/Services/Cloud/CloudKitCapability.swift`; ADR-080). The single honest switch
> `CloudKitCapability.entitledInThisBuild` is **`false`** on this personal-team build, so both macOS and
> iOS launch **local-first** and never attempt a doomed cloud container; the release-gate audit
> (`M19CloudKitHonestyTests`) fails the build if the entitlement and that constant ever disagree.
> Cross-device / merge / fallback behaviour is now proven deterministically by
> `CrossDeviceSyncValidationTests` (no real iCloud account). **Enabling real sync is a one-constant +
> entitlement change** — the exact manual steps are in `docs/28-CLOUDKIT-DEVICE-VALIDATION.md` §18.

---

## 1. Architecture

```
SwiftUI Views
   ↓
SessionCoordinator            ← the one orchestrator (unchanged, CloudKit-free)
   ↓
TimerEngine                   ← timestamp-authoritative (imports no CloudKit)
   ↓
SwiftData repositories        ← Configuration / Session / TaskTemplate / SessionPlan
   ↓
SwiftData ModelContainer      ← ModelConfiguration(cloudKitDatabase: .automatic)
   ↓
CloudKit (private database)   ← native SwiftData mirroring, below the domain
   ↓
the same user's other Apple devices
```

CloudKit sits **below the repositories**, provided entirely by SwiftData's native
mirroring. **No file in the project imports CloudKit** — there is no `CKRecord`,
`CKContainer`, `CKDatabase`, custom sync engine, or network call on any timer path
(ADR-060). The iCloud UI reads a pure `CloudSyncPresentationState` projection, the
same read-only-projection pattern used by the menu bar, widget, and App Intents.

### Files added (all under `time_frame/`)

- `Services/Persistence/PersistenceMode.swift` — the `local`/`cloudKit`/`fallback` value.
- `Services/Persistence/CloudDeviceIdentity.swift` — the per-install device id (ADR-063).
- `Services/Cloud/CloudSyncPresentationState.swift` — the pure UI projection + resolver.
- `Services/Cloud/CloudAccountStatusProvider.swift` — iCloud account availability (no CloudKit).
- `Services/Cloud/CloudSyncPreferences.swift` — UserDefaults-backed sync preference.
- `Services/Cloud/CloudSyncError.swift` — the closed "why sync is off" reason enum.
- `Services/Cloud/CloudSyncCoordinator.swift` — the `@Observable` adapter/observer.
- `Views/Cloud/CloudSyncSettingsSection.swift` — the Settings › iCloud section.

### Files changed

- `Services/Persistence/TimeFrameSchema.swift` — added `TimeFrameSchemaV6`; latest = V6.
- `Models/*.swift` — removed `#Unique`; `FocusSession` gains optional `originatingDeviceID`.
- `Services/Persistence/PersistenceController.swift` — modes + CloudKit builder + fallback.
- `Services/Persistence/SessionRepository.swift` — stamps device id; device-scoped recovery.
- `time_frameApp.swift`, `ContentView.swift`, `Views/Settings/SettingsView.swift` — wiring.

`TimerEngine` and `SessionCoordinator` were **not** changed for CloudKit.

## 2. Local-first strategy

Reads and writes always hit the **local** SwiftData store immediately; CloudKit
mirrors in the background, eventually. The app is fully usable before, during, and
without any sync. CloudKit is designed for eventual consistency, and every code path
assumes data may not yet have synchronized.

## 3. CloudKit configuration

A single line does it — `ModelConfiguration(schema:, cloudKitDatabase: .automatic)`
in `PersistenceController.makeCloudKitContainer`. `.automatic` reads the CloudKit
container id from the app's iCloud entitlement, so the source pins **no** container
identifier. There is no CloudKit schema authored by hand; SwiftData derives it from
the model graph and (in Development) creates the record types on first sync.

## 4. Entitlements

The app entitlement additions required to activate sync (see §15 for why they are
**not** committed on this free-team build):

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.abirbarman.com.time-frame</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
```

The **widget** extension entitlement is unchanged — the widget reads the App Group,
not CloudKit (ADR-060, §12).

## 5. Schema compatibility

CloudKit constraints and how the models meet them:

| Constraint | Status |
| --- | --- |
| No `@Attribute(.unique)` / `#Unique` | **Removed in V6** from all six models (was the only violation). |
| All attributes optional or defaulted | Already satisfied (every stored property has a default or is optional). |
| All relationships optional | To-one relationships already optional; to-many default to `[]`. |
| Delete rules | `.cascade` (session→intervals, plan→items) and `.nullify` (config→…) are CloudKit-legal. |
| Enums | `TimerPhase`/`SessionStatus`/`IntervalStatus` are `String`-backed `Codable` — stored as raw strings. |

Verified by `CloudKitModelCompatibilityTests` (no uniqueness constraints; full
round-trip of every model; cascade/nullify preserved).

## 6. Persistence modes

`PersistenceMode` (pure, `Sendable`, no CloudKit types):

- `local` — no mirroring requested (sync off, or no account/entitlement). Fully offline.
- `cloudKit` — SwiftData CloudKit mirroring active (still local-first).
- `fallback` — CloudKit was requested but could not initialise; running on the
  **preserved local store**. Distinct from `local` so the UI can explain *why*.

`PersistenceController.bootstrap(requestedMode:)` returns `{ container, activeMode }`
and degrades safely (see §11).

## 7. Offline behavior

Everything works offline: create configurations/templates/plans, run and stop a
session, open History and Statistics. The local in-memory container used in tests is
literally the "CloudKit unavailable" case, and `OfflinePersistenceTests` exercises the
whole flow. When connectivity/iCloud returns, SwiftData mirrors in the background —
**no custom polling timer** is introduced.

## 8. Running-session policy (device-local)

Timer execution is **device-local** (ADR-063):

- `FocusSession.originatingDeviceID` (optional; a random per-install UUID string, no
  PII) records which device started a session.
- `fetchRecoverableSession()` only returns sessions belonging to **this** device
  (`belongsToDevice`: a `nil` origin is treated as local for back-compat).
- A running/paused session synced from another device is **neither recovered into a
  second timer nor mutated** (mutating it would sync back and stop the owning device).
- Recovery otherwise follows the existing local rules (ADR-014).

> Device A runs a focus session → it syncs to Device B → Device B's launch does **not**
> start a second timer and does **not** touch the row. Proven by `RunningSessionSyncTests`.

## 9. Conflict policy

The app relies on Apple's SwiftData + CloudKit conflict handling (last-writer-wins per
record) rather than a custom distributed resolver. Per entity:

- **Configuration / TaskTemplate / SessionPlan(+Item):** mutable; last-write is fine —
  they are current-state definitions, not history.
- **FocusSession / SessionInterval:** **historical**. The frozen fields
  (`configurationName`, `startedAt`, `endedAt`, `targetEndAt`, `remainingAtPause`,
  `originatingDeviceID`, per-interval `phase`/`plannedDuration`) are written once and
  never rewritten by an unrelated edit, so a merge cannot corrupt history
  (`HistoricalIntegrityTests`). A live session is only ever advanced by its **owning
  device**, so its running anchors are not a cross-device write contention point.

## 10. History integrity

A configuration rename never rewrites a session's frozen `configurationName`; deleting
a plan cascades to its items but never to any `FocusSession`; deleting a template never
deletes a session it seeded; timestamps are untouched by any of these. Verified by
`HistoricalIntegrityTests`.

## 11. Failure isolation

`bootstrap` catches a CloudKit-init failure and reopens the **same on-disk store**
local-only as `.fallback` — it never wipes files and never substitutes an empty
in-memory store for real data. CloudKit is requested at launch only when sync is on
**and** an iCloud account is present. A CloudKit failure therefore degrades to offline
with data intact and the timer unaffected (`SyncFailureIsolationTests`).

## 12. WidgetKit interaction

Unchanged. The widget continues to read the **local App Group** `WidgetProjectionStore`
written by `WidgetProjectionWriter`; it imports no SwiftData and no CloudKit. CloudKit
is not accessed by the widget (ADR-060). Regression covered by
`CloudPersistenceRegressionTests`.

```
SwiftData/CloudKit → local app projection → App Group store → WidgetKit
```

## 13. App Intents interaction

Unchanged. Every intent still routes through the one `SessionCoordinator` via
`AppIntentSessionActions`; no intent touches CloudKit or the store directly. Regression
covered by `CloudPersistenceRegressionTests`.

## 14. Testing strategy

All CloudKit tests are deterministic and require **no** real iCloud account. CloudKit
init failures are simulated by injecting a throwing container factory into
`bootstrap`; account availability is faked via `CloudAccountStatusProviding`. Suites
added: `CloudSyncConfigurationTests`, `CloudSyncPresentationTests`,
`CloudSyncCoordinatorTests`, `CloudKitModelCompatibilityTests`,
`OfflinePersistenceTests`, `RunningSessionSyncTests`, `HistoricalIntegrityTests`,
`SyncFailureIsolationTests`, `CloudPersistenceRegressionTests`.

Baseline **434 tests / 79 suites** → **475 tests / 88 suites**, all passing, 0 warnings.

## 15. Manual setup requirements

The iCloud/CloudKit capability could **not** be enabled on this machine: `xcodebuild`
reported

> *"Personal development teams … do not support the iCloud capability."*

To enable real sync, a developer with a **paid Apple Developer Program** membership must,
in Xcode (Signing & Capabilities for the `time_frame` target):

1. Add the **iCloud** capability and check **CloudKit**.
2. Create/select the container **`iCloud.abirbarman.com.time-frame`**.
3. Xcode adds these entitlements to `time_frame/time_frame.entitlements`:
   ```xml
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array><string>iCloud.abirbarman.com.time-frame</string></array>
   <key>com.apple.developer.icloud-services</key>
   <array><string>CloudKit</string></array>
   ```
4. Do **not** add iCloud to the widget target (it uses the App Group only).

No `.pbxproj` change is otherwise required; the code already requests
`cloudKitDatabase: .automatic` and activates once the entitlement + a signed-in iCloud
account are present.

## 16. Production CloudKit deployment requirements

Beyond development:

1. In **CloudKit Console**, promote the schema from **Development → Production** (SwiftData
   creates the Development record types automatically on first sync; production requires an
   explicit deploy).
2. Ship with the iCloud entitlement in the **Production** provisioning profile.
3. Because the record types are auto-generated, deploy the schema before any user runs a
   production build, and follow SwiftData's additive-only evolution rules for future model
   changes (new optional attributes / new models; never a rename or a required field).

**Honesty note:** none of §15–§16 has been performed or verified here. The code is ready;
the account-level steps are the user's to complete.
