# Milestone 31 — Data Safety and Store Recovery

A correctness milestone with one subject: Time Frame must never destroy a user's data because
it could not open it.

No feature was added. The timer, the coordinator, the repositories, the widgets, Quick Start and
CloudKit are untouched, and the SwiftData schema stays **V7**.

## The defect

`PersistenceController.openOnDiskContainer` was written like this:

```swift
do {
    return try ModelContainer(for: schema, migrationPlan: …, configurations: [configuration])
} catch {
    AppLog.persistence.error("Opening on-disk store failed …; rebuilding store.")
    removeStoreFiles(at: configuration.url)          // ← deletes the user's data
    return try ModelContainer(for: schema, migrationPlan: …, configurations: [configuration])
}
```

Three things made this worse than it looks.

**The `catch` was not narrow.** It caught everything `ModelContainer` could throw — a schema
mismatch, a locked file, a denied permission, a truncated WAL, a transient I/O error — and
answered all of them by erasing the store.

**There was no backup.** `removeStoreFiles` removed `.store`, `-wal` and `-shm` outright. No
copy, no rename, no prompt. On a Mac without Time Machine, the data was simply gone.

**The result looked normal.** After the rebuild the app opened onto an empty Templates list and
an empty History — indistinguishable from a fresh install. The only trace was one log line the
user would never see. That is why this could destroy years of history without anyone noticing at
the moment it happened.

It was justified by ADR-016, written in Milestone 2, when the only thing at risk was a
re-seedable default configuration. That justification expired the moment the app persisted
templates, plans and history. The code did not change with it — and two tests were written that
asserted the deletion happened, which made the behaviour look intentional and reviewed.

### It was not hypothetical

During this milestone's own investigation, a locally built copy of the app was launched to take
screenshots. Because the app is not sandboxed and passed no store URL, it opened the developer's
real store (see ADR-110), hit this path, and destroyed it — templates, plans, configurations and
every recorded session. There were no APFS snapshots and no Time Machine destination on the
machine. **The data was not recoverable.**

## What changed

### 1. Failures are classified, not assumed

`Core/Services/Persistence/StoreOpenFailure.swift` turns an error into a specific cause:

| Kind | Means |
| --- | --- |
| `schemaMismatch` | Model hashes do not match the current schema |
| `migrationFailed` | A migration started and could not finish |
| `storeCorrupt` | A database whose contents are damaged |
| `malformedStore` | Not a database at all (`SQLITE_NOTADB`) |
| `fileAccessFailed` | A filesystem problem other than permissions |
| `permissionDenied` | Not permitted to read or write the store |
| `fileLocked` | Another process or connection holds it |
| `unknown` | Could not be established |

`unknown` is the important one. Previously, "we do not know why this failed" was silently treated
as "the data is rubbish". Being unable to explain a failure is not evidence about the data, and
it is never grounds for deleting it.

### 2. A failed open changes nothing

`openOnDiskContainer` now classifies and throws `StoreOpenError`. It touches no files.
`removeStoreFiles(at:)` was **deleted from the codebase**, not left unused — while it existed,
the safest-looking `catch` in the file was one line away from erasing a user's history.

Across the whole production tree there is now **no call to `FileManager.removeItem`** at all.

### 3. The failure is a state the app must handle

`PersistenceState` makes "the store did not open" representable:

```swift
case ready(PersistenceMode)
case needsRecovery(StoreOpenFailure)                     // nothing deleted; awaiting the user
case recoveredWithFreshStore(preservedAt: URL, mode: PersistenceMode)
```

`bootstrap` returns `.needsRecovery` with a **scratch in-memory** container, so the app can launch
far enough to explain itself while writing nothing to disk. `isShowingDurableData` is `false` in
that state, so the UI cannot present a scratch store as the user's library.

### 4. The user is told, and decides

`PersistenceRecoveryView` takes over the window. It leads with the sentence that matters —
**"Your data has not been deleted."** — explains the specific failure, and offers:

- **Try Again** — re-attempts the open; changes nothing either way. For a locked file this is the
  actual fix.
- **Show in Finder** — reveals the store so the user can copy it somewhere safe first.
- **Continue Without Existing Data** — the only action that changes anything, and it confirms
  first.

### 5. Starting fresh preserves, and never overwrites

`StoreQuarantine` *moves* the store and both sidecars into
`TimeFrame Recovery/2026-09-07T13-42-10Z/` beside the original. All three files travel together:
the WAL can hold committed transactions the main file does not yet have, so preserving only
`.store` would silently drop recent work.

Folder names are UTC, sortable, contain no `:`, and are created with
`withIntermediateDirectories: false` plus a unique-suffix retry — so an existing recovery copy is
never overwritten. If the move fails, the whole operation fails and the app stays in recovery
rather than trading the user's data for a clean launch.

### 6. Development and test isolation (ADR-110)

`StoreLocation` makes the store's location explicit, with production as the case a process falls
through to rather than gets by default:

1. `TIMEFRAME_STORE_DIRECTORY` redirects any build to a scratch store;
2. an XCTest host resolves to an isolated store under the temporary directory;
3. otherwise production — at exactly the path the app has always used, so no existing user's data
   is orphaned.

`assertNotProductionStore(_:)` traps for destructive tests. The isolation is asserted against the
**live** environment, not a synthetic one: if the suite ever runs against a real library, that
test fails.

## V6 → V7 migration is now actually tested

The schema file asserted that "an existing V6 store opens in place". Nothing verified it, and
nothing *could*: the app keeps no frozen per-version models, so `TimeFrameSchemaV6.models` and
`TimeFrameSchemaV7.models` return the same current classes. There was no way to write a V6 store.

`time_frameTests/PersistenceV6FixtureModels.swift` adds frozen V6 model copies — the current
models minus the three attributes Milestone 28 introduced (`iconIdentifier`, `isPinned`,
`pinnedAt`) — nested in an enum so their entity names match the app's. A test can now write a
genuine V6 store and reopen it with the production schema.

**Result: the migration is sound.** A realistic V6 library — a `PF45` configuration with
non-default durations, two templates, a plan with an ordered three-item timeline, and three
completed sessions with six intervals — survives completely: counts, identities, values,
timestamps, relationships and history. The attributes V7 added read as their defaults
(`isPinned == false`, `icon == .templateDefault`) on rows that predate them, and the store stays
writable afterwards.

So the data loss was **not** caused by a broken migration. It was caused entirely by the deletion
path in ADR-016 reacting to a failure that, on that machine, would have been survivable.

### A note for whoever writes the next SwiftData test

Three harness traps cost a full debugging pass here, each presenting as a "migration crash"
(`SIGTRAP` inside SwiftData) that had nothing to do with migration:

- **Keep the `ModelContainer` alive.** A `ModelContext` does not retain it. `try open(…).mainContext`
  releases the container immediately and faults later. This is in `CLAUDE.md`'s testing rules and
  was still easy to get wrong.
- **Evaluate `try` outside `#expect`.** A throwing fetch inside the macro faults.
- **Do not delete the store directory in a `defer`** while a container may still be tearing down.

A fourth cost a false alarm: an integer literal inside `#expect` (`45 * 60`) compares unequal to a
stored `TimeInterval`, which looks exactly like data loss. Use explicit `Double` literals.

## Tests

| Suite | Tests | Covers |
| --- | --- | --- |
| `PersistenceMigrationV6ToV7Tests` | 5 | A genuine V6 store opens with the current schema: nothing dropped; identities, values, timestamps, relationships and history preserved; V7 attributes take defaults; the migrated store stays writable |
| `StoreOpenFailureClassificationTests` | 6 | Each cause classifies distinctly; unknown is never "corrupt"; every kind preserves; log summaries carry no paths |
| `StoreQuarantineTests` | 5 | Store and both sidecars move; folders never collide; nothing-to-preserve fails loudly; timestamps are safe and sortable |
| `PersistenceFailureTests` | 4 | A failed open throws and leaves bytes identical; bootstrap reports `needsRecovery`; a good open reports `ready`; starting fresh preserves before opening |
| `PersistenceIsolationTests` | 5 | Test host is isolated; **this** process is isolated; override wins; production path unchanged; isolated stores are unique |
| `M31DataSafetyAuditTests` | 7 | No production source calls `removeItem`; `removeStoreFiles` is gone; the opener classifies; quarantine only moves; preserve precedes open; failure is representable and handled; the recovery surface is honest and confirms |
| `M31StoreIsolationAuditTests` | 4 | Store URL is explicit; production access is named; no test names the production path; the fixture refuses production |
| `StoreMigrationRobustnessTests` | 6 | **Rewritten**: the two tests that asserted deletion now assert preservation |

## Verification

| Check | Result |
| --- | --- |
| macOS Debug build | succeeded, 0 compiler warnings |
| macOS Release build | succeeded, 0 compiler warnings |
| macOS test suite | 998 tests in 211 suites passed (baseline 962 in 204) |
| iOS build (shared `Core/` changed) | succeeded, 0 compiler warnings |
| Destructive tests against the production store | none — every test uses a temporary directory, asserted by two audits |

## Known limitations

- **The already-lost data is gone.** This milestone prevents recurrence; it recovers nothing. The
  store destroyed during the investigation had no snapshot or backup on that machine.
- **The recovery surface has not been exercised on screen.** Its behaviour is covered by value and
  source tests, and the app builds and runs, but no screenshot was taken of a real failed launch,
  and the Try Again / Show in Finder / Continue Without Existing Data buttons have not been
  clicked in a running app.
- **After recovery, a relaunch is expected.** "Try Again" and "Continue Without Existing Data"
  update the persistence state and open a store, but the app's coordinators were built during
  `init` against the previous container; the new store is used from the next launch. The
  recovery actions log this. Swapping a live `ModelContainer` at runtime was deliberately not
  attempted in a data-safety milestone.
- **The bundle identifier is unchanged, so `UserDefaults` is still shared** between an installed
  copy and a local build. Only the SwiftData store is isolated. Changing the identifier would
  orphan existing users' data and their notification and calendar permissions.
- **CloudKit remains disabled** and untouched (`entitledInThisBuild == false`).
- **`fileLocked` is classified but not specially handled** beyond being marked transient and
  suggesting "quit any other copy". There is no lock-wait or automatic retry.
