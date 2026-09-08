# Changelog

All notable changes to Time Frame are documented here.

## [Milestone 33 — Product Name and Icon Identity] — 2026-09-08

An identity milestone. No feature, no architecture change; schema stays **V7**.

### Fixed
- **The macOS application menu read `time_frame`.** The bold title beside the Apple menu comes
  from `CFBundleName`, not `CFBundleDisplayName`. Milestone 24 set the display name and tested
  it, so the menu *items* ("About Time Frame", "Quit Time Frame") were already correct — but the
  menu's own title fell back to `PRODUCT_NAME`, the internal target name. Fixed by setting
  `PRODUCT_NAME = "Time Frame"` with `PRODUCT_MODULE_NAME = time_frame` pinned beside it
  (ADR-113). Verified by reading the menu bar of the running app.
- **iOS declared no app icon.** With `GENERATE_INFOPLIST_FILE = NO`, actool's injected keys are
  not merged, so `AppIcon` compiled into `Assets.car` while `CFBundleIconName` was absent —
  which builds fine and fails App Store validation. Now stated in the iOS `Info.plist`.
- **iOS `CFBundleName` was `$(PRODUCT_NAME)`** (`TimeFrameiOS`); it is now "Time Frame".

### Changed
- The macOS built product is now **`Time Frame.app`** with executable `Time Frame`, so the Dock,
  Finder, Force Quit and Activity Monitor all show the product name. `TEST_HOST` follows it in
  both configurations.

### Fixed (icon)
- **The macOS app icon rendered as a hard black square.** M24 used one identical full-bleed file
  on both platforms — correct for iOS, wrong for macOS, which does not mask app icons and draws
  exactly what the PNG contains. The macOS artwork is now shaped to Apple's icon grid: an 824 x 824
  rounded body (radius 185.4) centred on a 1024 x 1024 canvas with a 100 px transparent margin, and
  alpha enabled (it was `hasAlpha: no`). The mark, its colours and its proportions are unchanged.
  The iOS master stays full bleed, which was already correct.

### Unchanged, deliberately
- Bundle identifier `abirbarman.com.time-frame`, App Group `group.abirbarman.com.time-frame`,
  URL scheme `timeframe://`, Swift module `time_frame`, `time_frame.xcodeproj`, all target and
  directory names, and the SwiftData schema (V7).
- The app icon: one 1024 master, full macOS raster ladder, single iOS universal slot, no
  Light/Dark or tinted variants. Re-verified, not regenerated.

### Added
- `ProductionReadinessM33Tests` — 8 tests asserting the keys M24's suite did not: `PRODUCT_NAME`,
  the module pin, `TEST_HOST`, iOS `CFBundleName`, iOS `CFBundleIconName`, and that the technical
  identifiers did not move.

### Verified
- macOS Debug build: succeeded, 0 compiler warnings.
- macOS Release build (signed): succeeded, 0 compiler warnings.
- macOS test suite: 1071 tests in 218 suites passed.
- iOS Debug and Release builds: succeeded, 0 compiler warnings.
- iPhone 17 Pro: 105 tests passed. iPad Pro 13-inch (M5): 105 tests passed.
- Built products inspected directly: `CFBundleName`, `CFBundleDisplayName`, `CFBundleIconName`,
  and `AppIcon` present in each platform's compiled `Assets.car`.

### Not verified
- No iOS device or simulator run; the iOS name and icon were checked from the built bundle, not
  on screen.
- No screenshots — the menu-bar check returns text via the accessibility API, not images.

## [Milestone 32 — Open at Login and Single-Window Management] — 2026-09-08

Two pieces of macOS application behaviour that had never been stated: when Time Frame starts, and
how many windows it has. No feature of the timer changed; the engine, coordinator, repositories,
widgets, intents, notifications, Calendar and CloudKit are untouched, and the schema stays **V7**.

### Fixed
- **Opening Time Frame could create a second main window.** The main scene was a `WindowGroup` — a
  scene type that exists to allow more than one window, where `openWindow(id:)` creates a new one on
  every call. Four surfaces each held that capability and each wrote their own copy of
  activate-then-open. Clicking the Dock icon while the window was **minimized** or the app was
  **hidden** was worse: nothing implemented `applicationShouldHandleReopen`, and the default
  machinery reads `hasVisibleWindows`, which is false in both cases — so it opened a second window
  beside the first (ADR-111).
- **Closing the main window quit the app.** Found while verifying the scene change: `WindowGroup`
  kept the process alive when the last window closed, and a single-instance `Window` does not.
  `applicationShouldTerminateAfterLastWindowClosed` now returns `false`, restoring the documented
  behaviour — the menu bar, and a running Pomodoro, survive ⌘W.

### Added
- **Open at Login** — Settings ▸ General. Registers the app with `SMAppService.mainApp`, macOS's
  modern login-item API. No helper bundle, no deprecated `SMLoginItemSetEnabled` or
  `LSSharedFileList` (ADR-112).
- **`LoginItemService`** — the only file importing ServiceManagement, behind a `LoginItemManaging`
  seam, with `UnavailableLoginItemService` injected under the XCTest host so the suite can never
  register a developer build.
- **`LoginItemCoordinator`** — the toggle's state is read back from the system on launch, whenever
  Settings appears, and after every change. Nothing is persisted: there is no `UserDefaults` key
  standing in for the registration. A refused registration leaves the switch **off** and says why;
  a registration awaiting the user's approval reads as off and offers System Settings.
- **`MainWindowPolicy`** — the pure decision: create, reuse (with unhide/deminiaturize), or coalesce.
  No AppKit, no stored state, no `windowIsOpen` boolean.
- **`MainWindowPresenter`** — the one pathway. Every surface, and the Dock, routes through it.
- **`AppKitMainWindowHost`** — finds the `NSWindow`, holds it weakly, deregisters on close.
- **`TimeFrameAppDelegate`** — answers `applicationShouldHandleReopen` from real window state
  rather than from `hasVisibleWindows`.
- **`\.showMainWindow`** — the environment action a view calls. `openWindow` now appears in exactly
  one file in the codebase.

### Changed
- The main scene is `Window("Time Frame", id: "main")`, not `WindowGroup`. There is no File ▸ New
  Window command.
- The menu bar views no longer take an `AppNavigation` or hold `openWindow`; they ask for the window
  and decide nothing.
- Saved window frames move from the `main-AppWindow-1` key to `main`, so the window's remembered
  size and position reset once on first launch after upgrading.
- `AppLog` gained an `appLifecycle` channel.

### Verified
- macOS test suite: **1063 tests in 216 suites passed** (baseline 998 in 211).
- macOS Debug build, macOS Release build and the iOS build: succeeded, **0 compiler warnings** each.
- **Window behaviour, on the running Release build** (isolated store, reopen driven through
  LaunchServices, window counted via `CGWindowList` and the accessibility window list): launch → 1
  window; 4 × reopen → 1; minimize + reopen → 1, restored; hide + reopen → 1; close → 0 windows with
  the process still alive; 3 × reopen after close → 1. One process throughout.
- Focusing the window repeatedly, from every entry point, leaves a running session's id, engine
  state, phase, remaining time and interval count unchanged, with no second `FocusSession` recorded.

### Not verified
- **Launch at login was not tested by logging out and back in.**
- **`SMAppService` registration was not exercised against the real login-item database** — that
  would register a development build on the developer's Mac. The states are covered through the
  service seam instead.
- No screenshots: screen capture is unavailable in this environment, and none was fabricated. The
  Settings toggle was not confirmed on screen — the app's SwiftUI content exposes an empty
  accessibility tree to System Events — so its presence and wording are asserted by source audit.

## [Milestone 31 — Data Safety and Store Recovery] — 2026-09-07

A correctness milestone. No feature was added; the timer, coordinator, repositories, widgets,
Quick Start and CloudKit are untouched, and the schema stays **V7**.

### Fixed
- **Time Frame deleted a user's data when it could not open the store.** `openOnDiskContainer`
  answered *any* failed open — schema mismatch, locked file, denied permission, truncated WAL,
  transient I/O error — by removing `.store`, `-wal` and `-shm` and building an empty store in
  their place, with no backup and no prompt. The app then opened onto an empty library that was
  indistinguishable from a fresh install, so the loss was invisible at the moment it happened.
  This destroyed a real library during this milestone's own investigation, unrecoverably
  (ADR-109, supersedes ADR-016).
- **A locally built copy of the app used the installed app's store.** The app is not sandboxed
  and passed no store URL, so every build on a machine resolved to
  `~/Library/Application Support/default.store` (ADR-110).

### Added
- **`StoreOpenFailure`** — closed classification of why a store would not open
  (`schemaMismatch`, `migrationFailed`, `storeCorrupt`, `malformedStore`, `fileAccessFailed`,
  `permissionDenied`, `fileLocked`, `unknown`). An unrecognised failure is `unknown`, never
  assumed to be corruption.
- **`StoreQuarantine`** — preserves a store by **moving** it, with both sidecars, into
  `TimeFrame Recovery/<UTC timestamp>/`. Never deletes; never overwrites an earlier copy.
- **`PersistenceState`** — `ready` / `needsRecovery` / `recoveredWithFreshStore`, so "the store
  did not open" is a state the UI must handle rather than an empty library.
- **`StoreLocation`** — the store URL is resolved explicitly: `TIMEFRAME_STORE_DIRECTORY`
  redirects any build, an XCTest host is isolated, and production is the fall-through case at
  the app's long-standing path.
- **`PersistenceRecoveryView`** — the surface shown instead of an empty library: states that
  nothing was deleted, explains the failure, and offers Try Again / Show in Finder / Continue
  Without Existing Data (confirmed).
- **A genuine V6 store fixture** (`SchemaV6Fixture`, test target only) — frozen V6 model copies,
  so V6 → V7 migration can finally be executed rather than asserted in a comment.

### Changed
- `removeStoreFiles(at:)` was **deleted** from the codebase. There is now no call to
  `FileManager.removeItem` anywhere in production source.
- `StoreMigrationRobustnessTests` — the two tests that asserted the store was rebuilt now assert
  it is preserved. They were inverted rather than deleted, so the old policy cannot quietly
  return.
- `AppLog` is `nonisolated` so the pure persistence types can log.

### Verified
- **V6 → V7 migration is sound.** A realistic V6 library (a `PF45` configuration with non-default
  durations, two templates, a plan with a three-item timeline, three completed sessions with six
  intervals) survives intact: counts, identities, values, timestamps, relationships and history.
  The data loss was caused entirely by the deletion path, not by a broken migration.
- macOS Debug build: succeeded, 0 compiler warnings.
- macOS Release build: succeeded, 0 compiler warnings.
- macOS test suite: 998 tests in 211 suites passed (baseline 962 in 204).
- iOS build: succeeded, 0 compiler warnings.
- No destructive test touched the production store; two audits enforce it.

### Not verified
- The recovery surface has not been exercised on screen: no screenshot of a real failed launch
  was taken, and its three buttons have not been clicked in a running app.
- After recovery the app expects a relaunch — the coordinators were built during `init` against
  the previous container. Swapping a live `ModelContainer` at runtime was not attempted here.
- The data already destroyed is **not** recovered. This milestone prevents recurrence only.

## [Milestone 30 — Design System Consolidation] — 2026-09-07

A presentation-consistency milestone. No feature, no store, no timing authority, no schema change:
there is still exactly one `TimerEngine`, one `SessionCoordinator`, one mutation seam and one Quick
Start projection, and the schema stays **V7**.

### Fixed
- **The Timer screen's Start was a full-width filled slab.** It spanned the content column at
  `.controlSize(.large)` while every other action in the app was sized to its content, which made
  the app's most important screen read as a web form. Start is now a compact, content-sized
  prominent action (ADR-108).
- **A disabled Start gave no reason.** The only signal was the button being dim. It now says
  "Enter a task to start." beside the control, so the reason is not carried by appearance alone.
- **Stale menu-bar documentation.** Three places still described the Milestone 28 popover, in which
  the pinned list scrolled inside a bounded height. ADR-107 removed scrolling from the popover in
  Milestone 29 and the code and tests already matched — only the prose did not. Corrected in
  `TimeFrameMenuBarView.swift`, `MenuBarPopoverLayoutTests.swift`, and
  `docs/37-M28-MENU-BAR-QUICK-START-ICONS.md` (marked superseded rather than deleted).

### Added
- **`TFTypography`** in `Core/Support/DesignSystem/TimeFrameDesign.swift` — the type scale named by
  role (`pageTitle`, `subjectTitle`, `sectionTitle`, `rowTitle`, `body`, `secondary`, `metadata`,
  `numericValue`, `groupTitle`, `rowLabel`, `rowValue`), in native system fonts. Spacing, radii,
  motion and colour were centralised in Milestone 9; typography now joins them.
- **`TFControl`** plus `tfPrimaryAction()` / `tfSecondaryAction()` — the control-size rule in one
  place: one prominent action per screen, content-sized, at the native `.regular` height with a
  108 pt floor. Deliberately no full-width variant.
- **`ProductionReadinessM30Tests`** — 10 tests in 3 suites auditing both rules and the absence of
  architectural change.

### Changed
- `TFPageHeader`, `TFSectionHeader`, `TFDetailCard` and `TFDetailActions` read their sizes from
  `TFTypography` instead of naming fonts inline.
- Template detail (Start, Create Plan, Choose Configuration) and Plan detail (Start, Add to
  Calendar) use the shared action treatment, so those pages and the Timer screen share one control
  height instead of three similar ones. What the actions do is unchanged.
- The menu-bar popover's fallback action still spans its 288 pt container — the one deliberate
  full-width action, now recorded by a test rather than by memory.

### Verified
- macOS Debug build: succeeded, 0 compiler warnings.
- macOS Release build: succeeded, 0 compiler warnings.
- macOS test suite: 959 tests in 203 suites passed (baseline 949 in 200).

### Not verified
- No screenshot of the running app was captured and no pixel comparison was made: the environment
  had no screen-recording or accessibility permission. The visual claims are claims about which
  control treatment and type role each screen uses, not about a rendered image. Light Mode was not
  visually inspected; it remains correct by construction (system colours and materials only).

## [Milestone 29 — macOS Interface Redesign & Editor Presentation Fix] — 2026-09-07

A macOS presentation milestone with one real defect fix. The eight screens are unified behind one
design system, and the Template and Plan **Edit** buttons work again. No timing authority, no second
store, no clock and no polling were added: there is still exactly one `TimerEngine`, one
`SessionCoordinator` and one mutation seam, and the schema stays **V7**.

### Fixed
- **Template Edit and Plan Edit did nothing.** Both detail pages delegated editing to their list via
  an `onEdit` closure, and on macOS a `.sheet` requested from a `NavigationStack`'s root while a
  `navigationDestination` is pushed is not presented — the request was held until the stack popped
  back, at which point the editor appeared over the list. Each detail page now presents its own
  editor from its own state (ADR-106). The editor, the repository call, the item's identity, its pin,
  its icon and its history are all unchanged.
- **Editor sheets had no title and mislabelled fields.** A macOS sheet has no navigation bar, so
  `navigationTitle` rendered nothing; and the field *prompt* was being passed as the field *label*,
  so a grouped `Form` showed "e.g. Research" as the row title while a plain `List` row showed no
  label at all. Both editors now open with a `TFSheetHeader` and carry real labels plus separate
  prompts.

### Added
- **Shared content surface** — `tfCard` and `TFRowDivider` in
  `Core/Support/DesignSystem/TimeFrameGlass.swift`; `tfQuietSurface` now delegates to `tfCard`, so
  the app has one card fill, one border and one corner language instead of two near-identical ones.
- **macOS components** (`time_frame/Views/Components/`) — `TFPageHeader`, `TFSectionHeader`,
  `TFDetailCard`/`TFDetailRow`, `TimeFrameIconTile`/`TFSymbolTile`, `TFRowActions`,
  `TFManageSection`, `TFNoticeBanner`, `TFSheetHeader`, `TFChip`, `TFDefaultMarker`.
- **Quick Start on the Timer screen** — a menu in the page header that reads the *same*
  `QuickStartCoordinator` the menu bar uses and starts through the *same*
  `AppIntentSessionActions` seam. No second Quick Start source.
- **Recent Tasks** on the Timer screen — the last distinct task names, from a bounded
  `FetchDescriptor` (limit 60, deduplicated to 8), so history can grow without this read growing
  with it (ADR-100). No new repository.
- **Session Plan filter** — All Sessions / Focus Only / Breaks Only. Presentation-only: it narrows
  what is listed and can never change the plan the engine runs.
- **Search** on Templates and Plans, via native `.searchable`.
- `time_frameTests/EditorFlowTests.swift` — 19 tests covering the edit flows and the presentation
  structure the fix depends on.
- `docs/38-M29-MACOS-UI-REDESIGN.md`, and ADR-106 / ADR-107 in `docs/DECISIONS.md`.

### Changed
- **The menu bar popover no longer scrolls** (ADR-107, supersedes the height-bounded list from
  ADR-102). Three pinned rows are always fully visible and any further pins are offered by a compact
  "N more…" menu that starts them directly. `MenuBarPopoverLayoutTests` now fails the build if any
  menu-bar view contains a `ScrollView`.
- **One prominent action per detail page.** Start stays prominent; Create Plan and Add to Calendar
  became bordered secondaries; pinning became a switch in a quiet card; Duplicate and Delete moved
  into a separate "Manage" group where Delete is the page's only red control; Edit and an overflow
  menu sit beside the title.
- **Every screen opens with the same header** — Timer, Templates, Plans, Configurations, History and
  Statistics; Today's greeting header was already in this shape.
- **List rows became cards** with a leading icon tile and trailing Start/overflow controls laid out
  *beside* the navigation link, so a click on them is never swallowed by it.
- **Configurations rows** show their four defining numbers as one compact metric strip instead of
  four stacked lines; a single click on a row opens the editor.
- **History rows** gained a status tile, "N of M focus sessions", the start time, and a per-day
  completed-focus total in each day heading.
- **Sidebar** glyphs render at one weight and rendering mode; the column is 190–300pt.

### Unchanged
- `TimerEngine`, `SessionCoordinator`, the repositories, the widget projection, App Intents,
  notifications, Calendar, CloudKit posture, deep links, the App Group, and the SwiftData schema
  (**V7**).
- The running-session view, `TimerControls`, `TimerDisplay` and `SessionProgressView`.
- Every action that existed before still exists; nothing was removed to achieve the design.

### Verification
- macOS Debug and Release builds: succeeded, **0 warnings**.
- macOS tests: **949 tests in 200 suites passed**. iOS tests: **104 passed**.
- Manual: every redesigned screen reviewed in the running app in both appearances; Template and Plan
  Edit/Save/Cancel exercised end to end; Start/Pause/Resume/Stop exercised on a live session with the
  menu bar staying in sync.
- Not verified: macOS screenshots could not be written to disk in this environment, and VoiceOver was
  not run. See `docs/38-M29-MACOS-UI-REDESIGN.md` §6.1.

## [Milestone 28 — Menu Bar Popover UX, Quick Start Pinning & Icons] — 2026-09-06

A macOS presentation and library milestone. The menu bar popover is reordered around the timer,
its controls, and the things the user starts most often; Templates and Plans become pinnable and
gain a chosen icon that follows them everywhere. No timing authority, no second store, no clock,
and no polling were added: there is still exactly one `TimerEngine`, one `SessionCoordinator`,
and one mutation seam.

### Added
- **Gear menu** (`Views/MenuBar/MenuBarGearMenu.swift`) — Open Time Frame, Settings, History and
  Quit now live behind one native `Menu` in the popover's top-right corner instead of four
  permanent rows. Same actions, same identifiers, same one window and set of screens (ADR-102).
- **Quick Start in the menu bar** (`Views/MenuBar/MenuBarQuickStartView.swift`,
  `MenuBarQuickStartRowView.swift`) — the user's pinned Templates and Plans, each startable in one
  click, in a height-bounded scrolling list so the transport controls can never be pushed off
  screen.
- **Pinning** — `TaskTemplate` and `SessionPlan` gained `isPinned`/`pinnedAt`, with a pin control
  on both detail pages, both list context menus, and both leading swipe actions. Wording comes
  from one pure `QuickStartPinPresentation` so every surface says and speaks the same thing
  (ADR-104).
- **Icon system** (`Core/Support/TimeFrameIcon.swift`) — a closed, typed catalog of 31 SF Symbols
  in five categories. The persisted value is a stable identifier, never a symbol name; one
  resolver maps it to a symbol, with a default for anything unrecognised (ADR-103).
- **Icon pickers** (`Views/Components/TimeFrameIconPicker.swift`) — a native sectioned `Picker` in
  the Template and Plan editors, plus `TimeFrameIconBadge`, the one renderer. The chosen icon
  appears in both lists, both detail headers, both editors, and Quick Start.
- **Quick Start layer** (`Core/Services/QuickStart/`) — the pure `QuickStartItem` +
  `QuickStartOrder`, the read-only `QuickStartProvider`, and the `@Observable`
  `QuickStartCoordinator` that starts an item through the existing `AppIntentSessionActions` seam.
- **Restart while running** — previously paused-only. Running and paused now offer the same four
  controls (Pause/Resume, Skip, Restart, Stop), so the row does not re-flow mid-session.
- `ProductionReadinessM28Tests` (21 tests) — the release gate for every boundary in this
  milestone.
- `docs/37-M28-MENU-BAR-QUICK-START-ICONS.md`, and ADR-102 through ADR-105 in `docs/DECISIONS.md`.

### Changed
- **Schema V6 → V7** — three attributes on each of `TaskTemplate` and `SessionPlan`
  (`iconIdentifier`, `isPinned`, `pinnedAt`). The **model set is unchanged** (the same six
  types), and every added attribute is defaulted or optional, so the change is CloudKit-legal and
  an existing V6 store opens in place.
- `TaskTemplateRepository` and `SessionPlanRepository` gained the neutral `onChange` hook
  `ConfigurationRepository` already carried, forwarded through one new
  `SessionCoordinator.init(onLibraryChanged:)` parameter, so the menu bar's Quick Start list
  refreshes event-driven with no polling and no restart (ADR-105).
- `MenuBarControlsView` is now transport-only; its navigation footer moved to the gear menu.
- Nine earlier `ProductionReadiness*` schema assertions were **retargeted, not relaxed**: each now
  asserts the current schema version *and* that the entity set is still exactly six — the
  invariant those milestones actually own. No test was deleted or weakened.

### Verification (measured 2026-09-06)
- macOS: `** TEST SUCCEEDED **`, **928 tests / 196 suites** (baseline 844 / 189), Debug and
  Release builds succeed, **0 compiler warnings**.
- iOS: `** TEST SUCCEEDED **`, **105 tests** on both iPhone 17 Pro and iPad Air 11-inch (M4),
  Release build succeeds, **0 compiler warnings**.
- The Debug app was built, launched, and ran at **0.0% CPU while idle** for five minutes — no
  regression of the Milestone 26 status-item spin (ADR-101).
- **Not verified on screen:** the popover's appearance and interactions. Screen-control access
  was declined for this session, so no screenshot could be taken and no click driven. No
  screenshot was fabricated; section 11 of doc 37 lists exactly what remains to check by hand.

## [Milestone 27b — macOS User Guide & Product Walkthrough] — 2026-09-06

A macOS-focused documentation milestone. Every macOS screen was opened and read in the **running
application** (not inferred from source), and one user-visible defect found that way was fixed.

### Added
- `docs/35-MACOS-USER-GUIDE.md` — a 30-section Mac manual: quick start, a
  "Choosing the right feature" decision table, the timer and each control, Pomodoro cycles,
  configurations and configuration recipes, Templates, Plans, Today, History, Statistics
  (every metric explained), the menu bar, widgets, notifications, Calendar, every Settings section,
  keyboard shortcuts, a workday walkthrough, troubleshooting, accessibility, data and privacy, an FAQ,
  known limitations, and a feature reference table.
- `docs/assets/screenshots/macos/README.md` — an honest inventory recording that **no macOS screenshot
  could be captured**, the three capture routes that were tried and failed, what was inspected in the
  running app instead, and how to capture the set once the permission exists.

### Fixed — Statistics captions rendered raw markup (user-visible)
- **Symptom:** the Statistics screen displayed the literal string
  `^[3 focus interval](inflect: true)` beneath Focus Time. Found by looking at the running app.
- **Cause:** those captions are built as Swift `String`s and passed to `Text(_: String)` and
  `accessibilityValue(_:)` — the **non-localized** initializers. SwiftUI only applies automatic
  grammar agreement to a `LocalizedStringKey`, so the markup was shown verbatim. The same pattern
  affected the "Most Productive Day" caption and a chart's VoiceOver value, where the raw markup would
  have been read aloud.
- **Fix:** an explicit `statisticsCount(_:_:)` helper replaces the markup at the three sites where the
  value travels through a `String`. Literal `Text("^[…](inflect: true)")` elsewhere in the app is
  correct and was left alone.
- **Verified on screen:** the caption now reads "3 focus intervals".
- **Regression cover:** `StatisticsCaptionTests` (3 tests) checks pluralisation, that no caption leaks
  markup, and audits the Statistics view sources. The audit uses `codeKeepingStrings` rather than
  `code`, because the latter blanks string literals and would have made the assertion vacuous.

### Changed
- `README.md` — added a prominent "User guide" section linking both guides, updated the test counts,
  and noted the absent macOS screenshots with the reason.
- `docs/README.md` — indexed the macOS guide and the macOS screenshot inventory.
- `docs/35-USER-GUIDE.md` — a note pointing Mac readers to the dedicated guide.

### Verification (measured 2026-09-06)
- macOS: `** TEST SUCCEEDED **`, **844 tests / 189 suites** (841 + 3 new), 0 compiler warnings.
- macOS Debug and Release builds succeed with 0 warnings.
- 169 relative links and image paths resolve; all in-page anchors resolve; no emoji.
- Not captured: any macOS screenshot. Screen capture is refused for the documentation tooling
  (`screencapture` denied, the system capture shortcut inert, and a Terminal-routed capture also
  denied). The application itself built, launched and was driven successfully throughout.

## [Milestone 27 — Product Documentation, User Guide & Screenshots] — 2026-09-06

A documentation and product-audit milestone. **No application behaviour was changed and no production
source file was modified.** The product was inspected from current source, run on simulators, and
documented as it actually behaves today.

### Added — user-facing documentation
- `docs/35-USER-GUIDE.md` — a complete user manual: getting started, every timer control and state,
  configurations, Today, Statistics, History, notifications, widgets, Control Center, Live Activity,
  the macOS menu bar, every setting on both platforms, accessibility, app lifecycle, data and privacy,
  troubleshooting, an FAQ, platform availability and known limitations. Illustrated with real
  screenshots.
- `docs/36-DEVELOPER-OVERVIEW.md` — orientation for a new developer: layering, targets and directory
  map, the timer engine and control seam, the concurrency model and its four load-bearing rules,
  persistence, projection architecture, the command seam, integration isolation, CloudKit status,
  testing strategy, and the invariants to know before changing anything.
- `docs/README.md` — a documentation index covering user docs, developer docs, platform features,
  release material, and every milestone document in order.
- `docs/assets/screenshots/README.md` — a screenshot inventory recording each image's surface,
  environment and verification status, plus an explicit list of what could **not** be captured and why.
- `docs/assets/time-frame-logo.png` — a copy of the existing, unaltered application icon artwork, used
  for documentation branding.

### Added — real screenshots
Nine iPhone screenshots captured from the running application on an iOS 26 simulator: idle timer,
running focus interval, paused session, Today, History, Statistics, Settings, the in-app notification
permission request, and the Lock Screen Live Activity with its Pause / Skip / Stop controls. All are
genuine, unretouched captures. No mockups were produced for any surface.

### Changed — README
Rewritten as a product README: the real application logo, honest badges, a screenshot showcase,
feature list, platform-support matrix, architecture and widget/command-seam diagrams, notification and
persistence summaries, an explicit CloudKit status, accessibility, requirements, getting started,
testing with current measured numbers, project structure, documentation links, privacy, security,
known limitations, roadmap, contributing and license.

Removed unsupportable badges from the previous README: it advertised a "Swift 6.x" language mode (the
project builds in Swift 5 language mode on a Swift 6.4 toolchain) and carried stale test counts
(macOS 808 / iOS 101).

### Fixed — documentation accuracy
- Corrected the Milestone 26 macOS test count from **843 tests / 189 suites** to **841 / 188** in
  `docs/34`, the changelog and the milestone memory. The higher figure was measured before a
  two-test temporary investigation scaffold was removed, so it never described the delivered tree.
- Removed the remaining emoji from `docs/28`, `docs/34` and the App Store privacy answers, replacing
  status glyphs with plain text.

### Verification (measured 2026-09-06)
- macOS: `** TEST SUCCEEDED **`, **841 tests / 188 suites**, 0 compiler warnings.
- iPhone simulator: `** TEST SUCCEEDED **`, **105 tests**, 0 failures, 0 compiler warnings.
- macOS Debug and Release builds succeed with 0 warnings.
- All 140 relative links and image paths across the new documentation resolve.
- Not verified: macOS screenshots (Screen Recording permission unavailable to the automation process),
  widget and Control Center screenshots (an unsigned local build embeds no App Group entitlement), the
  Dynamic Island, iPad application screenshots, and anything requiring physical hardware.

## [Milestone 26 — Stability, Freeze, Concurrency & Production Reliability] — 2026-09-05

Investigates and fixes the reported **freeze while a Pomodoro is running** (Pause/Stop/Skip becoming
unresponsive). A hardening milestone: **no features, no rewrites**. There remains exactly one
`TimerEngine`, one `SessionCoordinator`, one `AppIntentSessionActions` mutation seam, one App Group;
the schema stays **V6** and CloudKit stays disabled. **No second timer, clock, coordinator, store, or
polling loop was introduced.** See `docs/34-M26-STABILITY-AND-RELIABILITY.md` and ADR-099/100.

### Root causes (both reproduced deterministically before any fix)
- **Heartbeat multiplication.** A cancelled heartbeat resumes from `Task.sleep` on a *later*
  main-actor turn and cleared `SessionCoordinator.ticker` as it unwound — including when a control had
  started a **newer** heartbeat in between. The new loop became unreferenced (so `stopTicking()` could
  not cancel it) while the now-`nil` handle defeated the duplicate guard, so the next control started
  another. Live tick loops grew by one per pause→resume→control cycle: **11 concurrent loops after 10
  cycles**, unbounded, each waking the main actor 4×/second.
- **Unbounded statistics on the timer control path.** `WidgetProjectionWriter.handle(_:)` runs
  *synchronously inside* `pause()`/`resume()`/`stop()`/`skip()`/`startSession()`. It fetched **every**
  `FocusSession` ever recorded, faulted in each one's intervals, and ran two full aggregations before
  the control returned. Pause latency was O(lifetime history): **5.6 ms** per control at 10 recorded
  sessions vs **770 ms** at 2,000 — a **137×** regression that grows forever.

### Fixed — heartbeat lifetime (ADR-099)
- `SessionCoordinator` keeps a monotonic `tickerGeneration`; each heartbeat clears `ticker` only if it
  is still the current generation, and `stopTicking()` retires the generation before cancelling. A
  heartbeat can now be neither orphaned nor duplicated.
- `SessionCoordinator.activeTickerCount` exposes the `0...1` invariant so it is asserted behaviourally.

### Fixed — presentation work off the control path (ADR-099)
- `WidgetProjectionWriter` splits work by **cost, not importance**: the session projection (derived
  from the engine's in-memory anchors — free) is still written synchronously, so no surface shows a
  stale running/paused state; the **today summary** is refreshed on a *coalesced* follow-up main-actor
  task after the control path returns, rewriting only if the figures changed. A burst of transitions
  collapses into a single statistics pass. No timer, no clock, no polling, no retry.

### Fixed — the start-of-session freeze: no `TimelineView` in the menu-bar label (ADR-101)
- **Symptom:** the app froze the instant a session was started, and then on every launch afterwards.
- **Root cause:** a `MenuBarExtra` **label** is rendered into an `NSStatusBarButton` and re-rendered
  *synchronously* by `MenuBarExtraHost`. `TimeFrameMenuBarLabel` used `TimelineView(.periodic(by: 1))`
  while running; the `TimelineView` re-arms during that render, so the host requested the next update
  immediately instead of a second later — an unbounded
  `updateButton → setImage: → invalidate → update` loop. Sampling the live process showed **199/199**
  main-thread samples inside it, at 100% CPU. The branch is entered exactly when
  `engine.state == .running`, hence "freezes when I start a session". It was self-perpetuating: the
  frozen app could never stop the session, so it stayed `running` in the store and every later launch
  recovered it and froze again.
- **Found by** running the built app and sampling it — the domain start path measures fast and flat
  (~17–28 ms, no growth), so the defect was in a layer no unit test covers. One plausible mechanism
  hypothesis (observable/SwiftData reads *inside* the closure) was **falsified**: hoisting every
  observable read out and leaving pure arithmetic inside still span at 99%.
- **Fix:** no `TimelineView` or scheduling primitive in the label. The countdown repaints from *outside*
  the render pass, driven by the **existing** heartbeat: `SessionCoordinator` publishes a display-only
  `displaySecond` (whole-second instant of the latest tick, written at most once a second, only from
  `tick()`). Because the change originates outside rendering it cannot re-trigger itself. Not a second
  clock — same heartbeat, no timing authority, no persistence/notification/projection work on that path.
  `TimelineView` is unchanged elsewhere (`TimerDisplay`, `TodayView`, the menu-bar popover).
- **Verified on the real app**, against the store that reproduced the hang: **100% CPU / frozen →
  1–2% CPU / idle**.

### Fixed — period-bounded statistics (ADR-100)
- New pure `StatisticsDateRange.mayContainActivity(startedAt:endedAt:)` — one definition of "relevant
  to a period", an exact **superset** test.
- `StatisticsRepository` gains `sessionInputs(in:)` and `sessionInputs(in:or:)`, filtering **before**
  mapping (mapping is the expensive step — it faults in a session's intervals). The unbounded
  `sessionInputs()` is retained for genuinely all-time questions.
- Both apps' widget today summary, the macOS `TodayView`/`StatisticsView` and the iOS
  `TodayScreen`/`StatisticsScreen` now aggregate only the period shown. The iOS screens previously
  fetched all history **per body evaluation**; `TodayView` additionally aggregated the whole snapshot
  **twice** per body pass.

### Results
| Metric | Before | After |
|---|---|---|
| 10× pause/resume, 2,000 recorded sessions | 15.42 s | **0.023 s** |
| History slowdown factor | 137× | **1.0×** |
| Statistics reads on the control path | 21 | **0** |
| Live tick loops after 10 cycles | 11 | **1** (0 after stop) |

### Added — tests
- `ProductionStabilityM26Tests.swift` (macOS): `TimerHeartbeatLifetimeTests`,
  `ControlPathResponsivenessTests`, `BoundedStatisticsEquivalenceTests`,
  `ProjectionFailureIsolationTests`, `ControlStressTests` — including 100-cycle stress runs and the
  byte-identical bounded-vs-unbounded aggregation proof.
- `ProductionReadinessM26Tests.swift` — audits single scheduling authority (`Task.sleep` in exactly one
  Core file; no `Timer`/`DispatchQueue`/`asyncAfter` in `Core/`), single engine/coordinator, read-only
  projection & statistics layers, unchanged App Group/deep link/V6 schema, and the presence of the
  generation guard.
- `IOSStabilityM26Tests.swift` (iOS) — proves both fixes from the iOS module, since `Core/` is shared.
- `MenuBarLabelRepaintTests` — audits that no `TimelineView`/`Timer(`/`scheduledTimer`/`asyncAfter`/
  `Task` returns to the status-item label, that the label still observes the display heartbeat, and
  that `displaySecond` has whole-second granularity and carries no timing authority.

### Changed — tests updated to the intentionally changed contract
- `WidgetProjectionWriterTests` and `WidgetCloudKitIndependenceTests` now assert **both** the immediate
  session write and the deferred today figures (previously they assumed the summary was synchronous).

### Verification
- macOS: `** TEST SUCCEEDED **`, **841 tests / 188 suites** (from 808/181); Debug + Release build.
- iOS: **105 passed / 0 failed** on iPhone 17 Pro **and** iPad Pro 11-inch (M5) (from 101); Debug +
  Release build. Both widget `.appex` bundles embedded; App Intents metadata extracted.
- **0 compiler warnings** throughout. Schema stays V6.
- **Not verified:** physical-device behaviour (Dynamic Island, Lock Screen, StandBy, Control Center,
  VoiceOver, background execution) and CloudKit production sync (still blocked on a paid Apple
  Developer team). Builds use ad-hoc signing — this machine has no provisioning profile for the app.

## [Milestone 24 — Product Identity, On-Device UX Validation & Final Polish] — 2026-08-17

Ships the app's **name** and **logo**, validates the M11–M23 presentation surfaces as far as the
environment allows, hardens the product identity, and makes the Control Center quick-start catalog
refresh event-driven. **No runtime architecture change:** one `TimerEngine`, one `SessionCoordinator`,
one `AppIntentSessionActions` seam, one App Group, schema stays **V6**, CloudKit stays disabled
(personal/free team). See `docs/33-M24-ON-DEVICE-UX-VALIDATION.md` and ADR-096/097/098.

### Added — product identity & app icon (ADR-096)
- The user-facing name is **"Time Frame"** everywhere the OS shows it. Added
  `INFOPLIST_KEY_CFBundleDisplayName = "Time Frame"` to both macOS app configs (it previously resolved
  to `PRODUCT_NAME` = `time_frame`). iOS already had `CFBundleDisplayName = "Time Frame"`.
- The single supplied logo (`tf_logo.png`, 1024², opaque) is the one source artwork for **both** Light
  and Dark on every platform. Populated `time_frame/Assets.xcassets/AppIcon.appiconset` with the mac
  raster ladder (16…1024 px) and a filename-referencing `Contents.json`.
- Created the iOS app's first asset catalog: `TimeFrameiOS/Assets.xcassets/AppIcon.appiconset` with a
  single 1024 universal slot, and set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` on both iOS configs.
- No `"appearances"` split and no `*Dark*`/`*Light*`/tinted variant set — one logo, unaltered.

### Added — event-driven catalog refresh (ADR-097)
- `ConfigurationRepository` gained a neutral, opaque `onChange: (@MainActor () -> Void)?` hook fired
  after each successful mutation (create/update/delete/duplicate/setDefault/seed).
- `SessionCoordinator.init` forwards the hook (new optional `onConfigurationsChanged`, default `nil`).
- Both apps wire it to `QuickStartCatalogWriter.refresh(…)` (suppressed under the XCTest host,
  best-effort). No polling, no new timer, no new store; the launch-time publish is retained.

### Added — tests (`time_frameTests/`)
- `ProductionReadinessM24Tests.swift` — audits the display name, the macOS + iOS AppIcon assets and
  target references, the one-logo/no-appearance-split invariant, and the unchanged bundle id / App Group
  / URL scheme / V6 schema; plus functional coverage of the `onChange` hook and configuration-identity
  stability (rename keeps id, recreate gets a fresh id). **+19 tests / +5 suites** (macOS 789 → 808).

### Changed — polish
- macOS Settings ▸ About now shows the real bundle version ("Version 1.0") instead of the stale
  developer string "Milestone 16".

### Verification
- macOS: `** TEST SUCCEEDED **`, **808 tests / 181 suites**, 0 warnings; Debug + Release build.
- iOS: Debug + Release build; iPhone + iPad suites pass. App icon + display name verified in the built
  bundles. App Intents metadata extracted/validated. CloudKit remains disabled.

## [Milestone 23 — Configurable Control Center Quick-Start] — 2026-08-16

Adds a **user-configurable** iOS Control Center control (WidgetKit `AppIntentControlConfiguration`,
iOS 18+) so the user can choose *which* saved timer a Control Center control starts. It is a
**command / presentation adapter over the one authoritative timer**, reusing the Milestone-15 mutation
seam end to end. **No second timer, no second clock, no second mutation seam, no second router, no new
widget extension, no new App Group, no schema change (stays V6), no CloudKit.** See
`docs/32-CONFIGURABLE-CONTROL-CENTER.md` and ADR-093/094/095.

### Added — the configurable control (ADR-093)
- New `TimeFrameiOSWidgets/QuickStartControlWidget.swift` — `TimeFrameQuickStartControl`, an
  `AppIntentControlConfiguration` in the **existing** iOS widget extension. Registered in
  `TimeFrameiOSWidgetsBundle` alongside the M22 controls. Its configuration is
  `QuickStartControlConfigurationIntent` (a `ControlConfigurationIntent` with one optional `timer`
  parameter); WidgetKit persists the choice — the app persists nothing for it.

### Added — the selectable entity & App Group catalog (ADR-094)
- `Shared/WidgetControlIntents.swift` gains the Foundation/AppIntents-only quick-start layer:
  `QuickStartTimerEntity` (stable `UUID` id, frozen display strings) + `QuickStartTimerEntityQuery`
  (`EntityStringQuery`, resolves from the catalog, drops deleted ids, filters by name);
  `QuickStartTimerDescriptor` / `QuickStartCatalog` / `QuickStartCatalogStore` (a versioned snapshot in
  the **same** App Group under a distinct key — no new group).
- New `Core/Widgets/QuickStartCatalogWriter.swift` maps the existing `ConfigurationRepository` → catalog
  and writes it at launch on both platforms (`time_frameApp` / `TimeFrameiOSApp`). App-side only; never
  in the widget extension. The picker shows names, not opaque ids; a deleted configuration drops out.

### Added — quick-start routing (ADR-095)
- `TimeFrameQuickStartIntent` (Shared) carries the selected entity as data and routes through the ONE
  seam: `ControlWidgetButton(action:) → TimeFrameQuickStartIntent →
  WidgetControlActions.performQuickStart(configurationID:) → AppIntentSessionActions.startSession(configurationID:)
  → SessionCoordinator → TimerEngine`. `WidgetControlActions` gains one `performQuickStart` capability
  (wired in `WidgetControlRouting`) and remains the **one** router. The app re-resolves the
  **authoritative** configuration by id, so rename/duration changes take effect on tap and a deleted
  configuration fails safely (`TimeFrameIntentError.configurationUnavailable`); a `nil` selection starts
  the default configuration; `requireNoActiveSession()` makes rapid taps idempotent.

### Added — accessibility
- `Shared/ControlCenterPresentation.swift` gains the pure `QuickStartControlContent` /
  `QuickStartControlPresentation`: a selected timer reads as its name with a spoken "Start <name> Timer";
  no selection reads as a safe "Start Timer" / "Start Focus Timer". Foundation-only, clock-free.

### Tests
- macOS `QuickStartControlTests.swift` (entity/query/catalog/writer/presentation/routing/failure/
  concurrency) and `ProductionReadinessM23Tests.swift` (boundary audit) — **+40 tests / +12 suites →
  749 → 789 / 164 → 176**.
- iOS `IOSQuickStartControlTests.swift` — the shared code + routing from the iOS module — **+11 tests**
  (iPhone 90 → 101; iPad 90 → 100 — the delta a pre-existing M21 accessory test, all 11 M23 tests green
  on both idioms).

### Unchanged
- The M22 Control Center controls, the M15 interactive-widget seam, all App Intents, the App Group
  (`group.abirbarman.com.time-frame`), the `timeframe://` deep links, the SwiftData schema (**V6**),
  and ActivityKit confinement (exactly three iOS files). CloudKit stays honestly disabled
  (`entitledInThisBuild == false`). Debug + Release build clean (macOS + iOS), 0 warnings; App Intents
  metadata extraction + `--validate-assistant-intents` succeed; the widget `.appex` embeds correctly.

## [Milestone 22 — iOS Control Center Controls] — 2026-08-16

Adds native iOS **Control Center** controls (WidgetKit `ControlWidget`, iOS 18+) so the user can
start/pause/resume/skip/stop the timer from Control Center, the Lock Screen control tray, and the Action
button. Each control is a **command / presentation adapter over the one authoritative timer**, reusing
the existing Milestone-15 mutation seam end to end. **No second timer, no second clock, no second
mutation seam, no second router, no new widget extension, no new App Group, no schema change (stays V6),
no CloudKit.** See `docs/31-CONTROL-CENTER-CONTROLS.md` and ADR-090/091/092.

### Added — iOS Control Center controls (ADR-090)
- New `TimeFrameiOSWidgets/ControlCenterWidgets.swift` in the **existing** iOS widget extension — three
  `ControlWidget`s: an adaptive **`TimeFramePrimaryControl`** (Start/Pause/Resume/Skip by situation),
  a dedicated **`TimeFrameStartControl`** (reuses M15 `WidgetStartIntent`), and a dedicated
  **`TimeFrameStopControl`** (reuses M15 `WidgetStopIntent`, disables itself when idle). Registered in
  `TimeFrameiOSWidgetsBundle`.
- Routing reuses the M15 seam verbatim: `ControlWidgetButton(action:) → App Intent → WidgetControlActions
  → AppIntentSessionActions → SessionCoordinator → TimerEngine`. `WidgetControlActions` gains
  `performPrimary()` and one thin adapter intent `TimeFramePrimaryControlIntent` (in
  `Shared/WidgetControlIntents.swift`); `WidgetControlRouting` resolves the primary action from live
  state via the pure `ControlCenterControlSet.primaryAction(for:)` and performs it through the SAME
  `perform(_:)` helper — one router, one decision path.

### Added — pure Control Center decision layer (ADR-091)
- New `Shared/ControlCenterPresentation.swift` — **Foundation-only** `ControlCenterSessionState`
  (derived from the read-only `WidgetProjection`), `ControlCenterControlSet` (valid controls + primary
  action per situation), `ControlCenterActionCatalog` (title / SF Symbol / VoiceOver label), and
  `ControlCenterPresentation`. Imports no WidgetKit/SwiftUI/AppIntents/ActivityKit/SwiftData/CloudKit and
  no clock. Added to all four app/widget targets' Sources phases in `.pbxproj`.

### Boundaries & platform (ADR-092)
- Control Center is **iOS-only**: macOS, `Core/`, `Shared/`, and the macOS widget stay
  `ControlWidget`-free. CloudKit stays disabled (`CloudKitCapability.entitledInThisBuild == false`); the
  controls read the local App Group projection and mutate the local store through the seam.
- New `time_frameTests/ProductionReadinessM22Tests.swift` audits the boundaries (ControlWidget iOS-only,
  no persistence/CloudKit/engine construction, no timer primitive, one router, Foundation-only decision
  layer, ActivityKit still exactly three iOS files, App Group + deep link unchanged, schema V6).

### Tests & verification
- macOS: `ControlCenterPresentationTests`, `ControlCenterRoutingTests`, `ProductionReadinessM22Tests` —
  **749 tests / 164 suites** pass (was 707/152).
- iOS: `IOSControlCenterTests` (state / accessibility / routing / failure isolation / concurrency /
  configuration) — iPhone & iPad green.
- Clean Debug + Release builds, **0 compiler warnings**; App Intents metadata extraction succeeds.
- **Not verified:** Control Center GUI/manual on-device behaviour and physical VoiceOver were not
  performed (no device/GUI access) — deterministic tests, builds, metadata extraction, and the source
  audit stand in. CloudKit cross-device sync remains a paid-team blocker.

## [Milestone 21 — iOS Lock Screen, StandBy & Accessory Widgets] — 2026-08-16

Expands the iOS WidgetKit experience to Apple's Lock Screen accessory families and StandBy. Every new
surface is a **read-only projection** over the one authoritative timer, reusing the entire existing
pipeline — one `TimerEngine`, one `SessionCoordinator`, one `WidgetProjection`/App Group, one
`WidgetProjectionWriter`, one `AppIntentConfiguration`. **No second timer, no second clock, no second
mutation seam, no new widget extension, no schema change (stays V6), no CloudKit.** See
`docs/30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md` and ADR-087/088/089.

### Added — Lock Screen accessory widgets (ADR-087)
- New `TimeFrameLockScreenWidget` (kind `"TimeFrameLockScreenWidget"`) in the **existing**
  `TimeFrameiOSWidgets` extension — families **`.accessoryCircular` / `.accessoryRectangular` /
  `.accessoryInline`**. Reuses `HomeScreenWidgetProvider`, `HomeScreenWidgetEntry`, the shared
  `TimeFrameWidgetConfigurationIntent`, and the pure `WidgetTimelineBuilder`; differs only in its
  `kind` and its accessory views.
- New files: `TimeFrameiOSWidgets/LockScreenWidget.swift`, `TimeFrameiOSWidgets/LockScreenWidgetViews.swift`.
- The live countdown is `Text(timerInterval:)` / `ProgressView(timerInterval:)` between the projection's
  frozen anchors; paused shows the frozen remaining. No `Timer`/publisher/`Task.sleep`/decrement.

### Added — pure per-family presentation mapper (ADR-088)
- New `Shared/AccessoryWidgetPresentation.swift` — **Foundation-only** mapper
  `(WidgetProjection, TimeFrameWidgetConfiguration, now) → {circular, rectangular, inline}` presentation
  values (symbol, text, countdown mode + frozen anchors, one spoken accessibility sentence). Imports no
  WidgetKit/SwiftUI/AppIntents/ActivityKit/SwiftData; uses a neutral `AccessoryWidgetFamily` /
  `AccessoryCountdown` vocabulary. Added to all four app/widget targets' Sources phases in `.pbxproj`.
- Each family **degrades information density** (no task name in circular; one line inline) rather than
  forking the projection. Today/Statistics modes render a compact glance from the same additive
  projection fields the Home Screen widget uses.

### Behaviour — StandBy & interactive controls
- **StandBy** is served by the **unchanged** `.systemSmall`/`.systemMedium` Home Screen Timer widget
  (StandBy is not a separate WidgetKit API); the background-agnostic views read well when dimmed.
- Accessory families are **read-only** (ADR-089): a tap opens the configured `timeframe://` destination.
  The Milestone-15 interactive seam stays on the Home Screen widget and the Live Activity — one mutation
  seam preserved.

### Accessibility & Dynamic Type
- Every accessory family combines into one VoiceOver element with a meaningful spoken sentence (phase +
  task + remaining + interval position); state is never conveyed by symbol/colour alone; the live
  countdown carries `.updatesFrequently`. Text uses system styles with `minimumScaleFactor`/`lineLimit`
  so primary state stays legible at large Dynamic Type sizes.

### Tests
- iOS `IOSLockScreenWidgetTests` (all families × states, config isolation, frozen-anchor/no-second-clock,
  malformed/stale, accessibility, bulk-mapping performance).
- macOS `AccessoryWidgetPresentationTests` (mapper guarded from the macOS suite) and
  `WidgetProjectionFreshnessTests` (meaningful-transition-only writes).
- macOS `ProductionReadinessM21Tests` boundary audit (widget extension has no SwiftData/CloudKit/
  notifications/engine/scheduling; the mapper is Foundation-only; accessory views are read-only;
  ActivityKit stays iOS-only; App Group + deep-link + schema V6 unchanged).
- Counts: macOS **690→707** tests (147→152 suites); iOS **50→75** tests (iPhone and iPad each).

## [Milestone 20 — iOS Home Screen Widgets, Local Notifications & Companion Polish] — 2026-08-15

Completes the iOS productivity layer M18 deferred: a configurable **iOS Home Screen widget** and **iOS
local notifications**, plus companion UI polish and a Live Activity regression pass. Reuses every
existing seam — one `TimerEngine`, one `SessionCoordinator`, the shared `WidgetProjection`/App Group,
the shared `AppIntentConfiguration`, the Milestone-15 interactive-control seam, and the neutral
notification stack. **No second timer, no second clock, no schema change (stays V6), no CloudKit.** See
`docs/29-IOS-WIDGETS-NOTIFICATIONS.md` and ADR-083/084/085/086.

### Added — iOS Home Screen widgets (ADR-084/085)
- The **existing** `TimeFrameiOSWidgets` extension now vends a configurable Home Screen widget
  (`TimeFrameHomeScreenWidget`, kind `"TimeFrameHomeScreenWidget"`) alongside the M18 Live Activity —
  no new extension target. Families **`.systemSmall` / `.systemMedium` / `.systemLarge`**.
- New files: `HomeScreenWidget.swift`, `HomeScreenWidgetProvider.swift`, `HomeScreenWidgetEntry.swift`,
  `HomeScreenWidgetView.swift`, `HomeScreenWidgetPreviewData.swift`, `HomeScreenWidgetFormatting.swift`.
- Reuses the **same** `WidgetProjection` / App Group (`group.abirbarman.com.time-frame`) /
  `TimeFrameWidgetConfigurationIntent` / pure `WidgetTimelineBuilder` as the macOS widget. Modes:
  Timer / Today / Statistics; configuration is presentation-only and never affects timing. Countdown is
  `Text(timerInterval:)` between frozen anchors (no decrement). Interactive Timer controls reuse the
  shared M15 intents → `WidgetControlActions → AppIntentSessionActions → SessionCoordinator`.
- The widget imports **no** SwiftData, CloudKit, `TimerEngine`, or `SessionCoordinator`.

### Added — iOS local notifications (ADR-083/086)
- The whole notification stack moved to **`Core/Services/Notifications/`** (shared by macOS + iOS,
  one source of truth). `UserNotificationService` stays the single UserNotifications importer;
  `NotificationCoordinator.openSystemSettings()` gained a `#elseif canImport(UIKit)` branch.
- `TimeFrameiOSApp` wires the neutral `NotificationCoordinator` + `UserNotificationService` on the same
  lifecycle fan-out as the widget/Live-Activity observers, reconciles the queue on launch, and routes
  actions back through the one `SessionCoordinator`.
- New `TimeFrameiOS/Views/NotificationSettingsView.swift`: master toggle, in-context permission flow,
  per-category toggles, sound + action toggles, "Open Settings" on denial. Preferences persist in
  **UserDefaults** (no schema change). Notifications are scheduled from the engine's frozen interval-end
  anchors (never a second clock); a notification failure can never stop or corrupt the timer.

### Changed — iOS companion UI polish
- `TimerScreen`: `ScrollView` + `maxWidth: 640` for iPad/landscape/Dynamic Type; `ContentUnavailableView`
  empty state when no configuration exists.
- `TodayScreen` / `StatisticsScreen`: clean `ContentUnavailableView` empty states (Statistics keeps its
  period picker); added accessibility identifiers.

### Tests
- **iOS** (`TimeFrameiOSTests`): `IOSHomeScreenWidgetTests`, `IOSNotificationTests`,
  `IOSCompanionUIStateTests`, `IOSPerformanceTests`, and `IOSTestSupport` (mock clock + in-memory
  notification scheduler + wired rig) — added to the M18 baseline of 13.
- **macOS** (`time_frameTests`): `ProductionReadinessM20Tests` (iOS-widget / notification /
  UserNotifications / ActivityKit / CloudKit / schema-V6 boundary audits); M17 audit roots updated for
  the notification move into `Core/`. Full macOS suite stays green at 679/144.

### Live Activity regression (Milestone 18, re-verified)
- No Live Activity code changed. `import ActivityKit` stays in **exactly three** iOS files; coordinator
  wiring, M15 control routing, duplicate prevention, and stale-date behaviour intact.

### Not done (by design / blocked)
- No CloudKit activation (`CloudKitCapability.entitledInThisBuild` stays `false`); no schema change
  (V6); no ActivityKit push. On-device Live Activity/Dynamic Island visuals, real notification banners,
  and cross-device CloudKit sync remain **unverified/blocked** (paid team + hardware).

## [Milestone 19 — CloudKit Activation Readiness, Cross-Device Validation & Device Validation] — 2026-08-15

A **production-validation** milestone. It adds **no** second timer, store, clock, or control seam and
**no** schema change (stays **V6**). It makes the CloudKit *capability* an explicit, unit-testable seam,
proves the cross-device / merge / fallback behaviour deterministically (no real iCloud account), and
strengthens the release-gate source-boundary audit — all while keeping the **personal (free) team**
CloudKit blocker honest and unfaked. See `docs/28-CLOUDKIT-DEVICE-VALIDATION.md` and ADR-080/081/082.

### Added — CloudKit capability seam (ADR-080)
- `Core/Services/Cloud/CloudKitCapability.swift` (Foundation-only, CloudKit-free): a
  `CloudKitCapabilityProviding` protocol + `BuildCloudKitCapabilityProvider`, the single honest switch
  `CloudKitCapability.entitledInThisBuild` (**`false`** on this personal-team build), and the pure
  resolver `resolve(entitled:syncEnabled:account:) -> Decision{requestedMode,blocker}`.
- `time_frameApp` (macOS) and `TimeFrameiOSApp` (iOS) now resolve the launch-time `PersistenceMode`
  through the seam, so both platforms decide identically and testably. Behaviour is unchanged today
  (both resolve `.local`) — but the "not entitled" case is now explicit, not discovered via a failed
  container build.

### Added — deterministic cross-device / merge / fallback tests (ADR-081)
- `CrossDeviceSyncValidationTests` (macOS): one in-memory container models the merged synced store, two
  device-scoped coordinators act as Device A/B. Proves frozen `configurationName`/interval timing
  survive a live-config **rename** and **delete**, completed history is visible to both devices, a
  running session stays **device-local** (never taken over/mutated), statistics re-derive from **merged**
  history, and every timer control works under a CloudKit `.fallback`.
- `CloudKitCapabilityTests` (macOS) + `IOSCloudKitCapabilityTests` (iOS): the full entitled × preference
  × account matrix, including the honest "this build is not entitled" pin.

### Added — release-gate audits (ADR-082)
- `ProductionReadinessM19Tests`: App-Group consistency across all four `.entitlements` files +
  `WidgetProjectionStore`; **no fabricated iCloud entitlement** (and the capability constant must match
  the entitlements on disk); CloudKit wiring honesty (native mirroring present, the CloudKit builder
  never wipes local data, `Services/Cloud` stays CloudKit-free, schema stays V6 with no uniqueness
  constraints); `timeframe://` deep-link scheme registered in both app Info.plists; and no committed
  secrets / private keys / provisioning artifacts.

### Unchanged / preserved
- Exactly one `TimerEngine` and one `SessionCoordinator`; SwiftData schema **V6**; App Group
  `group.abirbarman.com.time-frame`; deep-link scheme; App-Intents metadata; test-host hermeticity; and
  all M11–M18 behaviour. macOS stays ActivityKit-free; ActivityKit stays confined to the two iOS targets.

### Blocked / deferred (documented, not faked)
- **Real CloudKit synchronization across two devices** — paid Apple Developer team + iCloud container
  deployment required. **Physical-device Live Activity / Dynamic Island / VoiceOver / TestFlight / App
  Store signing** — no physical device / distribution signing in this environment. **iOS Home-Screen
  widget** and **iOS local notifications** — explicitly deferred rather than compromise the validation
  focus. See `docs/28-CLOUDKIT-DEVICE-VALIDATION.md` §17–18.

## [Milestone 18 — iOS/iPadOS Companion & Real Live Activities] — 2026-08-15

Time Frame's first multi-platform expansion: a **native iOS/iPadOS companion app** and **real
ActivityKit Live Activities** (Lock Screen + Dynamic Island), reusing the platform-neutral Milestone-16
live-session core. The mature macOS app is untouched and stays **ActivityKit-free**. The SwiftData
schema stays **V6**. There is still exactly **one** `TimerEngine` and **one** `SessionCoordinator`; the
Live Activity is a presentation surface, never timer authority. See
`docs/27-IOS-COMPANION-LIVE-ACTIVITIES.md` and ADR-078/079.

### Added — shared `Core/` group (ADR-078)
- Extracted the platform-neutral domain into a top-level **`Core/`** file-system-synchronized group
  attached to **both** the macOS and iOS app targets: `Models/`, `Timer/` (incl.
  `TimerEngine`/`SessionCoordinator`), `Statistics/`, `Support/`, `Intents/`, `Widgets/`, a new
  `Navigation/` (`AppSection`/`AppNavigation`, and `SessionSetupPrefill` the App-Intent seam depended
  on), and `Services/{Persistence,Cloud,LiveActivity,Statistics}/`. The macOS module compiles the
  **identical** file set, so `@testable import time_frame` and the macOS suite are unchanged.

### Added — iOS/iPadOS companion (`TimeFrameiOS`)
- Native SwiftUI companion with a `TabView`: Timer, Today, History, Statistics, Settings. Reuses the
  one `SessionCoordinator`/`TimerEngine`, the same `ModelContainer`, the `StatisticsAggregator`, models,
  and projections — no second timer, no iOS-specific analytics. The countdown is a `TimelineView`
  repaint of the engine's derived `remaining`.
- `ActivityKitLiveActivityService` — the real `LiveActivityService` (M16 protocol) injected into the
  unchanged M16 `LiveActivityCoordinator`; a `NoopLiveActivityService` under the test host.
- Device-local recovery (ADR-063) inherited with **no new code**: a session running on another device
  is never recovered, mutated, or duplicated. Deep links (`timeframe://…`) resolve to tabs via the
  shared `WidgetDeepLink`/`AppSection`.

### Added — real Live Activity (`TimeFrameiOSWidgets`)
- `TimeFrameLiveActivityAttributes` (in `TimeFrameiOSShared/`, compiled into both iOS targets) reuses
  `TimeFrameLiveActivityContent` **verbatim** as its `ContentState`.
- `TimeFrameLiveActivity` — an `ActivityConfiguration` rendering the Lock Screen banner and every
  Dynamic Island region (compact/minimal/expanded) from the shared `LiveActivityPresentation`; the
  countdown is `Text(timerInterval:)` between frozen anchors (no clock). Interactive controls reuse the
  **shared** Milestone-15 intents → the one `AppIntentSessionActions` seam.

### Changed — ActivityKit boundary is now iOS-scoped
- `ProductionReadinessTests`/`ProductionReadinessSupport` updated to the new `Core/` roots and to assert
  ActivityKit is imported **only** in the iOS targets and **nowhere** on the macOS side/`Core/`/`Shared/`
  (it was "nowhere" at M17). `import ActivityKit` appears in exactly three iOS files.

### Added — iOS tests (`TimeFrameiOSTests`)
- `IOSLiveActivityTests` (attributes ↔ identity, neutral ContentState round-trip, presentation mapping,
  accessibility label), `IOSCrossDeviceSessionPolicyTests` (device-local recovery — a remote session is
  never taken over), `IOSCompanionTests` (shared aggregator, deep-link navigation, inert no-op service).

### Not verified / blocked (documented, not faked)
- On-device Live Activity / Dynamic Island visuals — require an interactive simulator/device session.
- Cross-device CloudKit sync — requires a **paid Apple Developer team** + iCloud container; the iCloud
  entitlement is intentionally not added, so the store degrades safely to local.

## [Milestone 17 — Production Hardening & Release Readiness] — 2026-08-15

Takes the feature-complete M16 codebase toward a **production-quality release candidate**. A
**hardening** milestone — no new user-facing features, no rewrites — that preserves every M1–M16
invariant and adds an automated release gate. The suite grew **602 → 653 tests** in **122 → 137
suites** (all passing, **0 compiler warnings**); the **Debug** build and — validated for the first
time as an explicit gate — the **Release** build both succeed with **0 warnings**, with the
`TimeFrameWidgets.appex` embedded, packaged, and signed. The SwiftData schema stays **V6**.
`TimerEngine` remains the single timing authority and `SessionCoordinator` the single control seam.
See `docs/26-PRODUCTION-READINESS.md` and ADR-077.

### Added — automated production-readiness audit (`time_frameTests/`)
- `ProductionReadinessTests.swift` + `ProductionReadinessSupport.swift` — a whole-tree source-boundary
  release gate (comments/string literals blanked, identifier-boundary aware): schema is **V6**; exactly
  one file schedules the heartbeat (`SessionCoordinator`) and the engine/presentation/integration layers
  contain none; `TimerEngine` is declared once and constructed only by `SessionCoordinator`; observer
  integrations, `Shared/`, and the widget import no SwiftData/`ModelContext`; **no `import ActivityKit`
  anywhere**; no production CloudKit import; the timer core uses no `fatalError`/`try!`/`as!`; the live
  process is a detected XCTest host and launch guards live seeding/recovery.
- `StoreMigrationRobustnessTests.swift` — the rebuild-on-incompatibility upgrade policy (ADR-016/061),
  hermetically: an incompatible legacy store and a corrupt store file are rebuilt into a usable V6 store;
  every model round-trips a real close/reopen with no data loss; `originatingDeviceID` defaults to nil and
  legacy nil-origin rows stay device-local (ADR-063).
- `LargeHistoryStressTests.swift` — the pure aggregator over **5,000** and **12,000** intervals (exact
  totals) and `StatisticsRepository` over **1,000** persisted sessions / 4,000 intervals.
- `AccessibilityTextTests.swift` — spoken durations (no NaN/negative), status/phase labels (state as text,
  not colour), and the menu-bar VoiceOver description (never a bare `00:00`).
- `KeyboardNavigationAuditTests.swift` — transport-control shortcuts + identifiers, setup Cmd+Return +
  focus, and editor default/cancel actions.
- `AllIntegrationsFailureIsolationTests.swift` — Calendar + Notifications + Widget all failing at once
  (plus a throwing lifecycle observer) while a full session completes and Stop preserves history.
- `TimerBoundaryHardeningTests.swift` / `EmptyStateRobustnessTests` — remaining never negative; backwards
  clock never corrupts; skip/stop at a boundary; 24-hour interval; ten-year sleep gap; empty history yields
  zeros and nil ratios; deleted-configuration safe label.

### Changed — production code (minimal, behaviour-preserving)
- `Support/TestHostEnvironment.swift` (**new**) — pure, testable XCTest-host detection extracted from
  `time_frameApp.init()` (identical behaviour); launch now calls `TestHostEnvironment.isHostingUnitTests()`.
- `Services/Persistence/PersistenceController.swift` — extracted `openOnDiskContainer(schema:configuration:)`
  so the rebuild-on-incompatibility path is testable against a temp store URL; the default call site is
  unchanged.
- `Views/Timer/TimerDisplay.swift`, `Views/MenuBar/MenuBarTimerView.swift` — added
  `.accessibilityAddTraits(.updatesFrequently)` to the live countdowns.
- `Intents/TimerControlIntents.swift` — bound the `AppIntentSessionActions` value to a local in the Restart
  intent, removing a spurious **Release-only** whole-module-optimisation *"weak reference will always be
  nil"* warning (the one control that transitively starts the heartbeat `Task { [weak self] }`).

### Verified
- Debug build **SUCCEEDED / 0 warnings**; Release build **SUCCEEDED / 0 warnings** (app + embedded widget).
- Full suite **653/653** passing. Schema **V6** (unchanged). Release-config audit clean (sandbox + hardened
  runtime on; App Group, URL scheme, and bundle ids consistent; signing unchanged).

### Not done (documented release blockers, not architectural gaps)
- **CloudKit production sync is unverified** — needs a paid Apple Developer team + iCloud entitlement/container
  (ADR-060…062). The app runs local-first and falls back safely.
- **Distribution signing/notarization** (Developer ID) not configured — the project signs with a personal
  development team.
- A live on-device **VoiceOver / Full-Keyboard-Access** walkthrough is recommended to complement the
  automated accessibility coverage.

## [Milestone 16 — Live Session Surface / ActivityKit] — 2026-08-15

Adds a **live-session surface** for an active Time Frame session — but honestly. ActivityKit / Live
Activities are **`@available(macOS, unavailable)`** (the framework ships in the macOS SDK only for
Mac Catalyst; the compiler rejects a native-macOS `ActivityAttributes` conformance with *"unavailable
in macOS"*). Time Frame is a **native macOS 27** app with no iOS target, so it **cannot** host a Live
Activity. Per the milestone's rule, no unsupported macOS ActivityKit implementation was fabricated.
Instead M16 ships the **reusable, platform-neutral live-session core** — a read-only projection of the
one authoritative `TimerEngine`/`SessionCoordinator`, observing the same `SessionLifecycleEvent` seam
as Calendar/Notifications/Widgets — and documents the exact remaining work for a future iOS/iPadOS
companion target. The core owns no timer, introduces no clock (`Text(timerInterval:)` repaint only),
persists nothing, imports no ActivityKit/WidgetKit/SwiftData/CloudKit, keys activity identity to
`FocusSession.id` (explicit duplicate-prevention + launch reconciliation), reuses the Milestone-15
control seam (no new action path), and is provably unable to affect the timer. It is **inert in the
shipping macOS app** (not wired into the running app), so the macOS product is unchanged. The suite
grew **557 → 602 tests** in **105 → 122 suites** (all passing, **0 warnings**); the clean build
(app + widget) succeeds; the SwiftData schema stays **V6**. **Manual acceptance is not applicable on
macOS** (there is no Live Activity to display) and is not claimed. See `docs/25-LIVE-ACTIVITIES.md`
and ADR-072…076.

### Added — Shared (`Shared/`, compiled into app + widget; Foundation-only)
- `LiveSessionProjection.swift` — the pure live-session value model intended for direct reuse as a
  future `ActivityAttributes.ContentState`: `TimeFrameLiveActivityContent` (dynamic),
  `LiveActivityIdentity` (static), `LiveActivitySnapshot`, and `LiveActivityRunState`
  (running/paused/completed/interrupted, defensive decode). Imports no ActivityKit/WidgetKit/SwiftUI/
  SwiftData/CloudKit/domain.
- `LiveActivityPresentation.swift` — pure mapping from identity + content to display primitives
  (phase title, SF Symbol, progress line, countdown/paused flags, accessibility label), reusable by a
  future Live Activity UI and unit-tested with no runtime.

### Added — App target (`time_frame/Services/LiveActivity/`, Foundation/Observation only)
- `LiveActivityService.swift` — the `LiveActivityService` isolation protocol (in pure value types),
  the neutral `LiveActivityDismissal` policy, and an inert `NoopLiveActivityService`.
- `LiveActivityContentMapper.swift` — maps authoritative `SessionCoordinator`/`TimerEngine` state to a
  `LiveActivitySnapshot` (mirrors `WidgetProjectionMapper`; no persistence, no clock).
- `LiveActivityCoordinator.swift` — observes the lifecycle fan-out; start/update/end decisions,
  `reconcileOnLaunch()` (exactly one activity per recovered session), `preferencesDidChange()`.
  Reads the coordinator and calls the service only — never mutates the timer.
- `LiveActivityPreferences.swift` — UserDefaults-backed presentation preferences (enable / show task /
  show configuration); no SwiftData, no schema change.

### Added — Tests (17 suites, +45 tests)
- `LiveActivityTestSupport.swift` (`FakeLiveActivityService` + wired rig) and suites
  `LiveActivityPresentationTests`, `LiveActivityAttributesTests`, `LiveActivityStateTests`,
  `LiveActivityMappingTests`, `LiveActivityLifecycleTests`, `LiveActivityStartTests`,
  `LiveActivityUpdateTests`, `LiveActivityPauseResumeTests`, `LiveActivitySkipTests`,
  `LiveActivityStopTests`, `LiveActivityCompletionTests`, `LiveActivityRecoveryTests`,
  `LiveActivityDuplicatePreventionTests`, `LiveActivityFailureIsolationTests`,
  `LiveActivityCloudKitIndependenceTests`, `LiveActivityBoundaryInvariantTests`,
  `LiveActivityAppIntentRoutingTests`.

### Not done (platform limitation; scoped for a future iOS/iPadOS companion target)
- No `ActivityAttributes` conformance, no ActivityKit adapter, no `ActivityConfiguration`/Dynamic
  Island UI, no Settings → Live Activity surface, no `NSSupportsLiveActivities` — all unavailable to a
  native macOS target. `import ActivityKit` appears nowhere in the codebase.

## [Milestone 15 — Interactive WidgetKit Controls] — 2026-08-15

Turns the Milestone-14 configurable widget into an **interactive control surface**: users press
**Pause / Resume / Skip / Restart / Stop / Start** directly on the widget. The widget stays a
**read-only projection** of the one authoritative `TimerEngine`/`SessionCoordinator` — it gains buttons
that *command* that one timer through the existing Milestone-12 action seam, never a second timer, a
widget-local store, or widget-owned timer state. Each control is a thin `AppIntent` used with
`Button(intent:)`; WidgetKit runs it in the **app process**, where an app-registered
`@AppDependency WidgetControlActions` router delegates to the existing `AppIntentSessionActions` — the
one and only place an intent mutates the timer. Which controls appear is a **pure** `WidgetControlSet`
projection of the state (interactive controls in **Timer** mode only; Today/Statistics stay read-only).
The countdown stays a `Text(timerInterval:)` repaint (no new `Timer`/`Task.sleep`/`asyncAfter`/
decrement); the projection is still produced only by `WidgetProjectionWriter`, reloaded on a meaningful
transition after each action (never per tick). Actions fail safely (unavailable router / no session /
already running / invalid transition / stale action) and can never stop or corrupt the timer. The
widget `kind` (`"TimeFrameTimerWidget"`), families (`.systemSmall`/`.systemMedium`),
`AppIntentConfiguration`, App Group (`group.abirbarman.com.time-frame`), deep links, projection format,
and SwiftData schema (**V6**) are all **unchanged**. The full suite grew **517 → 557 tests** in
**96 → 105 suites** (all passing, **0 warnings**), the clean build and the widget target build succeed,
and App Intents metadata is extracted and **validated** (`--validate-assistant-intents`) with all six
widget-control intents discovered (`isDiscoverable == false`). **Manual interactive-widget verification
was not performed** (no GUI/widget-gallery automation in this environment). See
`docs/24-INTERACTIVE-WIDGETS.md`.

### Added — Shared (`Shared/`, compiled into app + widget)
- `WidgetControlIntents.swift` — `WidgetControlAction` (pause/resume/skip/restart/stop/start), the pure
  `WidgetControlSet` (state→controls), `WidgetControlResult`, `WidgetControlError.unavailable`, the
  app-owned `WidgetControlActions` router (`@AppDependency` value with an inert `.unavailable`
  default), and the six thin `Widget{Pause,Resume,Skip,Restart,Stop,Start}Intent`s
  (`openAppWhenRun == false`, `isDiscoverable == false`). The **second** shared file importing
  `AppIntents`; imports no SwiftData/SwiftUI/WidgetKit/CloudKit/domain.

### Added — App target
- `time_frame/Intents/WidgetControlRouting.swift` — builds the router's closure delegating every action
  to the existing `AppIntentSessionActions` seam and refreshing the widget projection afterward (so
  `restart`, which emits no lifecycle event, still refreshes).
- `time_frame/Intents/IntentDependencies.swift` — `registerWidgetControl(_:)` advertises the router.
- `time_frame/time_frameApp.swift` — builds + registers the router on a normal launch (skipped under
  the unit-test host).

### Changed — Widget extension
- `TimeFrameWidgets/TimeFrameWidgetView.swift` — Timer-mode per-state `Button(intent:)` clusters
  (running focus → Pause/Skip[/Stop]; break → Skip/Stop; paused → Resume/Restart/Stop; idle/completed/
  interrupted → inline Start) via a new `SessionControlBar` + `WidgetControlButton` (SF Symbol **and**
  label, explicit accessibility labels). Today/Statistics modes unchanged (read-only).

### Added — Tests (`time_frameTests/Widgets/`, +40 tests / +9 suites)
- `InteractiveWidgetTestSupport`, `InteractiveWidgetActionTests`, `InteractiveWidgetStateTests`,
  `InteractiveWidgetConfigurationTests`, `InteractiveWidgetFailureTests`,
  `InteractiveWidgetConcurrencyTests`, `InteractiveWidgetRecoveryTests`,
  `InteractiveWidgetCloudKitIndependenceTests`, `InteractiveWidgetProjectionTests`,
  `InteractiveWidgetBoundaryTests`. `WidgetConfigurationBoundaryTests` updated to allow the second
  `Shared/` `AppIntents` importer.

### Decisions
- **ADR-069** — interactive widget controls are command surfaces over the one coordinator (thin shared
  intents run in the app process → `AppIntentSessionActions`).
- **ADR-070** — control availability is a pure `WidgetControlSet` projection of state.
- **ADR-071** — actions refresh through the existing writer; stale/failed actions fail safely and never
  resurrect a session.

### Project
- `Shared/WidgetControlIntents.swift` added to **both** targets' Sources build phases in `.pbxproj`
  (`Shared/` is not a synchronized group). No new target, no schema change, no entitlement change.

## [Milestone 14 — Configurable WidgetKit Experience] — 2026-08-15

Upgrades the M11 widget from a `StaticConfiguration` to a user-configurable **`AppIntentConfiguration`**
widget, without introducing a second timer, a second persistence system, or duplicated business
logic. Users choose, in the standard macOS widget editor, **what** the widget shows (Current Timer /
Today's Focus / Statistics), **where a tap goes** (Timer / Today / Statistics / History), and whether
the **countdown** is visible. The configuration is a pure presentation projection: it changes
rendering only and can never touch the one `TimerEngine`/`SessionCoordinator` (ADR-064). The widget
remains **read-only** over the local App Group projection — no SwiftData, no CloudKit, no clock. The
widget `kind`, families, App Group, and SwiftData schema (**V6**) are all unchanged. The full suite
grew **475 → 517 tests** in **88 → 96 suites** (all passing, **0 warnings**), the clean build
succeeds, and the widget's App Intents metadata is extracted and validated. **Manual widget-gallery
verification was not performed** (no GUI/widget-gallery automation in this environment). See
`docs/23-CONFIGURABLE-WIDGETS.md`.

### Added — Shared projection (`Shared/`, compiled into app + widget, Foundation-only)
- `TimeFrameWidgetConfiguration.swift` — the pure `displayMode`/`destination`/`showsCountdown` model
  (`WidgetDisplayMode`, `WidgetDestination`), `Codable`/`Hashable`/`Sendable`, defensively decoded.
- `WidgetTimelineBuilder.swift` — pure `projection + configuration + now → entries + reload`
  (`WidgetEntryDescriptor`/`WidgetTimeline`), wrapping `WidgetTimelinePolicy`; configuration never
  affects timing.
- `TimeFrameWidgetConfigurationIntent.swift` — the `WidgetConfigurationIntent` + three `AppEnum`s
  (`WidgetContentOption`/`WidgetDestinationOption`/`WidgetCountdownOption`) with user-facing display
  representations; maps to the pure configuration. The one `AppIntents` import in `Shared/`.

### Added — Widget projection (`Shared/WidgetProjection*`)
- `WidgetProjection` gains two **additive optional** fields (`completedFocusIntervalsToday`,
  `focusTrendToday`) — no schema-version bump, no storage-key change.
- `WidgetFocusTrend` — pure up/down/steady trend enum (defensively decoded).

### Changed — Widget extension (`TimeFrameWidgets/`)
- `TimeFrameWidgetsBundle.swift` — `StaticConfiguration` → `AppIntentConfiguration` (same `kind`
  `"TimeFrameTimerWidget"`, same `.systemSmall`/`.systemMedium`).
- `TimeFrameWidgetProvider.swift` — `TimelineProvider` → `AppIntentTimelineProvider`; builds entries
  via `WidgetTimelineBuilder`.
- `TimeFrameWidgetEntry.swift` — carries the `TimeFrameWidgetConfiguration`.
- `TimeFrameWidgetView.swift` — switches on `displayMode` (Timer / Today / Statistics), honours
  `showsCountdown` (quiet variant), taps route to the configured `destination` deep link.
- `TimeFrameWidgetPreviewData.swift` — sample configurations + today/statistics projections.

### Changed — App writer (`time_frame/Widgets/`, `time_frameApp.swift`)
- `TodaySummary` + `WidgetProjectionMapper` — carry completed focus intervals and a focus trend.
- `time_frameApp.todaySummary` — computes the trend (today vs yesterday) from the same
  `StatisticsAggregator` the dashboard uses; single fetch, mutates nothing.

### Added — Tests (`time_frameTests/Widgets/`)
- `WidgetConfigurationTests`, `WidgetConfigurationIntentTests`, `ConfiguredWidgetTimelineTests`,
  `WidgetProjectionConfigurationTests`, `WidgetConfigurationIsolationTests`,
  `WidgetCloudKitIndependenceTests`, `WidgetConfigurationBoundaryTests`,
  `WidgetProjectionPerformanceTests` (+42 tests, +8 suites).

### Decisions
- ADR-064 … ADR-068 (see `docs/DECISIONS.md`).

## [Milestone 13 — iCloud / CloudKit Sync] — 2026-08-14

Makes Time Frame's SwiftData store synchronize across a user's Apple devices via **CloudKit**,
while staying **local-first**, **offline-capable**, and **timer-authoritative**. Sync is
**SwiftData's native mirroring** below the repositories — **no file imports CloudKit** (no
`CKRecord`/`CKContainer`, no custom sync engine, no polling), and `TimerEngine`/
`SessionCoordinator` are unchanged and CloudKit-free (ADR-060). The schema bumps **V5 → V6** for
CloudKit compatibility. The full suite grew **434 → 475 tests** in **79 → 88 suites** (all
passing, **0 warnings**). **CloudKit production sync was not manually verified** — the signing
team is a *personal* Apple Developer team, which cannot use the iCloud capability (see
`docs/22-ICLOUD-CLOUDKIT.md` §15–16). See `docs/22-ICLOUD-CLOUDKIT.md`.

### Added — Cloud layer (`time_frame/Services/Cloud/`)
- `CloudSyncPresentationState.swift` — pure UI projection (`unavailable`/`localOnly`/`available`/
  `syncing`/`error`) + total resolver; no CloudKit types.
- `CloudAccountStatusProvider.swift` — iCloud account availability from Foundation's ubiquity
  identity (no CloudKit), injectable for tests.
- `CloudSyncError.swift` — closed "why sync is off" reason enum.
- `CloudSyncPreferences.swift` — UserDefaults-backed sync preference (mirrors other stores).
- `CloudSyncCoordinator.swift` — `@Observable` observer/adapter over the resolved mode + account.

### Added — Persistence (`time_frame/Services/Persistence/`)
- `PersistenceMode.swift` — `local`/`cloudKit`/`fallback` value.
- `CloudDeviceIdentity.swift` — stable per-install device id (random UUID, no PII).
- `TimeFrameSchemaV6` — removes `#Unique` from all six models; latest schema = V6.

### Added — UI & tests
- `Views/Cloud/CloudSyncSettingsSection.swift` — Settings › iCloud (toggle + plain-language
  status, never colour-only).
- Test suites: `CloudSyncConfigurationTests`, `CloudSyncPresentationTests`,
  `CloudSyncCoordinatorTests`, `CloudKitModelCompatibilityTests`, `OfflinePersistenceTests`,
  `RunningSessionSyncTests`, `HistoricalIntegrityTests`, `SyncFailureIsolationTests`,
  `CloudPersistenceRegressionTests`.

### Changed
- `Models/*` — removed `#Unique` (CloudKit rejects uniqueness); `FocusSession` gains additive
  optional `originatingDeviceID` (device-local recovery, ADR-063).
- `PersistenceController.swift` — `bootstrap(requestedMode:)` → `{ container, activeMode }`;
  CloudKit builder (`cloudKitDatabase: .automatic`) with **safe fallback to the preserved local
  store** (never an empty in-memory store), never wiping on a CloudKit failure (ADR-062).
- `SessionRepository.swift` — stamps `originatingDeviceID`; `fetchRecoverableSession` is
  device-scoped and non-destructive toward another device's running session.
- `time_frameApp.swift` / `ContentView.swift` / `SettingsView.swift` — wire the cloud coordinator;
  request CloudKit only when sync is on **and** an iCloud account is present; force local under
  the unit-test host. No timer change.

### Not changed (verified)
- `TimerEngine`, `SessionCoordinator`, and everything under `Timer/` — no CloudKit import, no
  new timer primitive. WidgetKit still reads the **local App Group** projection; App Intents
  still route through `SessionCoordinator`; Calendar/Notifications/Menu Bar/Statistics unaffected.

## [Milestone 12 — App Intents, Shortcuts & Siri] — 2026-08-14

Exposes Time Frame's core actions to **Shortcuts** and **Siri** through **App Intents** — an
integration surface over the **one** authoritative `TimerEngine`/`SessionCoordinator`, never a
second timer, start path, or store. Every intent routes through the existing coordinator via a
single `@MainActor AppIntentSessionActions`; no timer primitive is introduced. The SwiftData
schema is **unchanged (V5)**. The full suite grew **377 → 434 tests** in **67 → 79 suites** (all
passing, **0 warnings**). See `docs/21-APP-INTENTS.md`.

### Added — App Intents layer (`time_frame/Intents/`)
- `AppIntentSessionState.swift` — pure, immutable projection of the live session (same in-memory
  math as `MenuBarPresentationState`/`WidgetProjectionMapper`).
- `AppIntentDialogText.swift` — pure phrasing for every spoken confirmation/status (single
  future-localization edit point).
- `TimeFrameIntentError.swift` — closed, user-facing error set (`CustomLocalizedStringResourceConvertible`);
  never leaks a Swift/SwiftData error or UUID.
- `AppIntentSessionActions.swift` — the one place intents *act*; resolves inputs and calls the
  existing `startSession`/`startPlan`/`pause`/`resume`/`skip`/`restart`/`stop`.
- `IntentDependencies.swift` — `IntentDataProvider` + `AppDependencyManager` registration
  (`@AppDependency`), skipped under the unit-test host.
- Intents: `StartTimeFrameIntent`, `StartTemplateIntent`, `StartPlanIntent`,
  `PauseTimeFrameIntent`, `ResumeTimeFrameIntent`, `SkipTimeFrameIntervalIntent`,
  `RestartTimeFrameIntervalIntent`, `StopTimeFrameIntent`, `OpenTimeFrameIntent`,
  `ShowTimeFrameStatisticsIntent`, `GetCurrentTimeFrameStatusIntent`.
- Entities: `TaskTemplateEntity`, `SessionPlanEntity`, `ConfigurationEntity` (stable-UUID,
  `EntityStringQuery` over the existing repositories), and the read-only `CurrentSessionEntity`.
- `TimeFrameShortcuts.swift` — `AppShortcutsProvider` with 9 curated phrases.

### Added — Repository fetches (additive)
- `TaskTemplateRepository.template(with:)` and `ConfigurationRepository.configuration(with:)`,
  mirroring the existing `SessionPlanRepository.plan(with:)`.

### Changed
- `time_frameApp.swift` — registers the one coordinator + `IntentDataProvider` with
  `AppDependencyManager` at launch (skipped while hosting tests). No timer/persistence change.

### Added — Tests (`time_frameTests/`, +57 tests / +12 suites)
- State projection (idle/focus/short break/long break/paused/completed/interrupted), dialog text,
  entities + entity queries (stable ids, display reps, deleted records, search), Start Template /
  Start Plan / Start Time Frame (valid/invalid/default/count/active-conflict/prefill), timer
  controls (+ idle behavior), current status, App Shortcuts, failure isolation (a failing intent
  never corrupts the timer; a resolution failure creates no partial session), and a regression
  pass proving the menu bar and widget projections still read the one coordinator.

### Verified
- App Intents metadata extraction (`Metadata.appintents`, `--validate-assistant-intents`) at
  build time discovers all **11 intents, 4 entities, 4 queries, and 9 App Shortcuts**.

## [Milestone 11 — WidgetKit Surfaces] — 2026-08-14

Adds native macOS 27 **WidgetKit** surfaces as **read-only projection surfaces** over the one
authoritative timer. The widget renders a snapshot the app writes and can never become a
second timer: it creates no clock, imports no SwiftData, and never instantiates `TimerEngine`
or `SessionCoordinator` (ADR-055). The SwiftData schema is **unchanged (V5)**. The full suite
grew **341 → 377 tests** in **60 → 67 suites** (all passing, **0 warnings**). See
`docs/20-WIDGETKIT.md`.

### Added — Shared projection (`Shared/`, compiled into app + widget, Foundation-only)
- `WidgetProjection.swift` — the `Codable`/`Sendable` snapshot (schema v1) the app writes and
  the widget reads; convenience `idle`/`unavailable` constructors; schema-compatibility flag.
- `WidgetProjectionState.swift` — `WidgetSessionState` / `WidgetPhase`, both decoding
  defensively (unknown values → `.unavailable` / `.none`, never a throw).
- `WidgetProjectionStore.swift` — App-Group `UserDefaults` bridge; inert on a missing suite,
  `nil` on corrupt/incompatible payloads, mutates no app state.
- `WidgetDeepLink.swift` — neutral `timeframe://{timer,today,statistics,history}` parse/build.
- `WidgetTimelinePolicy.swift` — pure entry/reload decision (`WidgetRefreshPolicy`), no WidgetKit.

### Added — App-side writer (`time_frame/Widgets/`)
- `WidgetProjectionMapper.swift` — `@MainActor` map from `SessionCoordinator`/`TimerEngine` to a
  `WidgetProjection` (in-memory timestamp math; mirrors `MenuBarPresentationState`).
- `WidgetProjectionWriter.swift` — observes the lifecycle fan-out + meaningful-transition hook,
  writes the projection, reloads `WidgetCenter`; fully failure-isolated from the timer.
- `WidgetDeepLink+AppSection.swift` — maps a parsed deep link to the existing `AppSection`.

### Added — Widget extension (`TimeFrameWidgets/`, new app-extension target)
- `TimeFrameWidgetsBundle.swift` (`@main`, `StaticConfiguration`, small + medium, deterministic
  previews for every state), `TimeFrameWidgetProvider.swift` (`TimelineProvider`),
  `TimeFrameWidgetEntry.swift`, `TimeFrameWidgetView.swift` (idle / focus / break / paused /
  completed / interrupted / unavailable, accessible, deep-linked), `TimeFrameWidgetPreviewData.swift`,
  `WidgetFormatting.swift`.

### Added — Tests (`time_frameTests/Widgets/`, +36 tests / +7 suites)
- Projection mapping (all 7 states), timeline policy, serialization + fallback, App Group store,
  deep-link routing, the writer, and a static **boundary-invariant** scan (widget target imports
  no SwiftData, references no `TimerEngine`/`SessionCoordinator`, creates no timer loop).

### Changed
- `SessionCoordinator` — one additive, non-semantic `onMeaningfulTransition` hook fired from
  `reconcileIfChanged()` so the widget can refresh at auto interval boundaries (never per-tick).
- `time_frameApp` — builds the writer, extends the lifecycle fan-out, publishes an initial
  projection on launch; `ContentView` gains `.onOpenURL` deep-link handling.
- App entitlements + a supplementary `time_frame-Info.plist` add the App Group and the
  `timeframe` URL scheme. **No timer, coordinator, or schema semantics changed.**

## [Milestone 10 — Statistics & Productivity Analytics] — 2026-08-14

Adds a **read-only** Statistics & Productivity Analytics system on top of the existing
persisted session history. Statistics are a projection of the one historical source of
truth — they never mutate the `TimerEngine`, `SessionCoordinator`, `FocusSession`,
`SessionInterval`, a configuration, template, or plan, and introduce **no second timer,
no clock, and no second database**. The SwiftData schema is **unchanged (V5)**; every
metric derives from existing fields. The full suite grew from **290 → 341 tests** (all
passing); the timer engine and coordinator are untouched. See `docs/19-STATISTICS.md`.

### Added — Statistics engine (`Statistics/`, pure & Sendable)
- `StatisticsInput.swift` — `SessionStatInput`/`IntervalStatInput`, the immutable aggregation
  input (frozen values only, imports only Foundation).
- `StatisticsPeriod.swift` — `StatisticsPeriod` + `StatisticsDateRange`: calendar-correct,
  time-zone- and DST-aware range resolution for Today / Yesterday / This & Last Week /
  This & Last Month / Custom, plus the previous-equivalent range for trends.
- `StatisticsSnapshot.swift` — `StatisticsSnapshot`, `DailyStatistics`,
  `ConfigurationStatistics`, `StatisticsComparison` (the results; safe derived values).
- `StatisticsAggregator.swift` — deterministic aggregation (`nonisolated`, no SwiftData/SwiftUI).

### Added — Read-only repository (`Services/Statistics/`)
- `StatisticsRepository.swift` — a single `@MainActor` fetch mapping `FocusSession` →
  `SessionStatInput`; mutates nothing.

### Added — Statistics UI (`Views/Statistics/`)
- `StatisticsView.swift` — the dashboard: primary metric cards (Focus Time, Sessions,
  Completion Rate, Average Focus), a focus trend card, most-productive-day card, charts,
  and a secondary metric grid; polished new-user and empty-period states.
- `StatisticsPeriodPicker.swift` — a menu period selector + custom date-range editor whose
  field bounds enforce start ≤ end.
- `StatisticsCharts.swift` — native **Swift Charts**: Focus by Day, Sessions Completed, and
  Focus by Configuration — each accessible (per-mark labels/values), theme-aware, and with
  explicit empty/single-point placeholders.

### Changed
- `Views/AppSection.swift` / `ContentView.swift` — a new **Statistics** sidebar section
  (between History and Settings), routed to `StatisticsView`.
- `Views/Today/TodayView.swift` — now draws its two figures from the **same**
  `StatisticsAggregator` over the `.today` period, so Today and Statistics can never
  disagree (no duplicate aggregation).
- `Support/TimeFormatting.swift` — added `preciseDuration` (keeps seconds, e.g. `24m 52s`)
  for the average-focus statistic.

### Tests (+51: 290 → 341)
- `StatisticsAggregationTests`, `StatisticsDateRangeTests`, `StatisticsTrendTests`,
  `StatisticsRepositoryTests`, `StatisticsEdgeCaseTests`, `StatisticsApplicationTests`,
  and shared `StatisticsTestSupport` fixtures — all deterministic (fixed dates, injected
  calendar, in-memory store), including a 1,000-session / 5,000-interval aggregation guard.

## [Milestone 9 — macOS 27 Liquid Glass Visual Identity] — 2026-08-13

Transforms the functional app into a cohesive, native **macOS 27 Liquid Glass** experience.
This milestone is **presentation-only**: no file under `Timer/`, `Services/`, or `Models/` was
touched, the SwiftData schema stays **V5**, and the full test suite (**290 tests**) passes
unchanged. The `TimerEngine` and `SessionCoordinator` are byte-for-byte identical, so the timer
behaves exactly as before (ADR-050/§95). Glass is used **selectively** to establish hierarchy —
control regions and primary actions — while ordinary content stays visually quiet (ADR-051).
See `docs/18-LIQUID-GLASS-DESIGN.md`.

### Added — Design system (`Support/DesignSystem/`)
- `TimeFrameDesign.swift` — the token system: `TFSpacing`, `TFRadius`, `TFMotion`, and the
  semantic `TFPalette` (focus / shortBreak / longBreak / running / paused / completed / warning
  / destructive — system colours + accent only, never hard-coded RGB; ADR-052). Plus the
  Reduce-Motion-aware `tfAnimation(_:value:)` modifier (ADR-053).
- `TimeFrameGlass.swift` — the surface vocabulary: `tfGlassSurface` (a floating Liquid Glass
  surface over the native `glassEffect` API) and `tfQuietSurface` (a quiet, non-glass system
  fill for ordinary content).

### Changed — Timer (the visual centrepiece)
- `TimerDisplay` — clearer hierarchy: a small uppercase, phase-tinted phase label over a larger
  (88pt) rounded monospaced countdown; added `timeFrame.timer.phase` / `.countdown` identifiers.
- `TimerControls` — the transport is now a `GlassEffectContainer` of glass buttons with one
  dominant action (`.glassProminent` Pause/Resume) and quieter `.glass` Stop/Restart/Skip; added
  `timeFrame.timer.pause/resume/stop/restart/skip` identifiers.
- `TimerView` — paused now dims the frozen countdown *and* shows an explicit "Paused" label
  (never colour alone); tokens/palette throughout.
- `SessionSetupView` — a prominent `.glassProminent` **Start** (`timeFrame.timer.start`).
- `IntervalPlanPreview` — a lighter phase-tinted timeline on a quiet surface.
- `CompletionView` — a restrained glass summary card + `.glassProminent` Start New Session.

### Changed — Today, Menu Bar, and the rest
- `TodayView` — a time-of-day greeting; the live "current session" is the one glass card, other
  content uses quiet surfaces; prominent glass primary actions.
- Menu bar (`MenuBarControlsView`/`MenuBarTimerView`/…) — glass transport buttons in a
  `GlassEffectContainer`, phase-tinted uppercase phase label, tokens; **no** architecture or
  behavior change (ADR-045–049 intact).
- `EmptyStateView` CTA, editor **Save** actions, and detail **Start** actions → `.glassProminent`
  as the single dominant action per surface; supporting actions → `.glass`.
- Semantic tints (`StatusPresentation`, banners, notices) routed through `TFPalette`.
- `time_frameApp` — `.windowToolbarStyle(.unified)` for an integrated macOS 27 window; and a
  **test-hermeticity guard**: because the app target is also the unit-test *host*, it now skips
  live store seeding/recovery when launched under XCTest (`XCTestConfigurationFilePath` etc.),
  so the developer's real persisted state can never affect or hang the test runner. Normal
  launches are unaffected; no domain type (`TimerEngine`/`SessionCoordinator`) changed.

### Accessibility
- Added the spec's `timeFrame.timer.*` identifiers (existing identifiers preserved unchanged).
- Reduce Motion honoured via `tfAnimation`; state is always conveyed by label/icon + colour, not
  colour alone; the countdown keeps its VoiceOver label/value.

### Verification
- **Build:** SUCCEEDED. **Tests:** 290/290 passing, 46 suites. **Warnings:** 0 Swift compiler
  warnings. Audits confirm no new timer/decrement patterns and no domain-file modifications.
- Manual GUI verification: Setup, Running, and the glass control cluster confirmed in Dark mode
  on macOS 27; remaining states verified by code review + tests (see `docs/10-TESTING-PLAN.md`).

## [Milestone 8 — macOS Menu Bar Experience] — 2026-08-13

Adds a native macOS `MenuBarExtra` that gives quick visibility and control of the active
session without opening the main window. The menu bar is **only a presentation/control
surface over the one authoritative `TimerEngine`/`SessionCoordinator`** — it maintains no
timer of its own, decrements no counter, and persists no timer state (ADR-045/046). Every
control routes through `SessionCoordinator` (ADR-047); the live countdown is a pure
projection re-derived from the engine by a `TimelineView` (repaint only). It observes the
same lifecycle seam as Calendar and Notifications and is independent of both — a Calendar
or Notification failure can never break the menu bar, and vice versa (§37/§38). No other
later-milestone features (Liquid Glass, Widgets, App Intents, Siri, iCloud/CloudKit,
advanced Statistics) were implemented. The schema stays **V5**. See `docs/17-MENU-BAR.md`.

### Added — Menu bar domain & adapter (`Services/MenuBar/`)
- `MenuBarPresentationState` — a pure (`Sendable`/`Equatable`) projection of the
  authoritative engine (`init(coordinator:)`): situation, task, frozen configuration name,
  phase, remaining, focus progress, and the next interval. Never a second source of truth
  (ADR-046, §48).
- `MenuBarCoordinator` (`@MainActor @Observable`) — observes the shared coordinator, exposes
  the projection, and routes Pause/Resume/Skip/Stop/Restart and "start new session" back
  through `SessionCoordinator` (ADR-045/047).
- `MenuBarPreferences` + `MenuBarPreferencesStore` — "Show in Menu Bar" / "Show countdown"
  in `UserDefaults`, **no SwiftData schema change** (ADR-048).

### Added — UI (`Views/MenuBar/`)
- `TimeFrameMenuBarLabel` — the compact status-item icon + title; a `TimelineView` ticks
  the countdown only while running (repaint only — §11/§33).
- `TimeFrameMenuBarView` — the `.window`-style popover; switches on the projected situation.
- `MenuBarTimerView`, `MenuBarSessionSummaryView`, `MenuBarEmptyStateView`,
  `MenuBarControlsView` — countdown/phase/progress, header, idle/completed/interrupted
  header, and the transport + navigation controls (accessibility identifiers throughout).
- `MenuBarStatusPresentation` — pure title/icon/VoiceOver mapping (never a bare `00:00`).
- `MenuBarSettingsSection` (in Settings) — "Show in Menu Bar" (default on) and "Show
  countdown in menu bar" toggles.

### Added — App wiring (`Timer/`, app scene, navigation)
- `time_frameApp` — a single app-owned `MenuBarCoordinator`; the `WindowGroup` gains
  `id: "main"`; a `MenuBarExtra(isInserted:)` scene bound to the visibility preference and
  styled `.window`. One `SessionCoordinator`/`ModelContainer` shared by window and menu bar
  (ADR-049).
- `AppNavigation` — a tiny shared seam so the menu bar can bring the existing window forward
  (`openWindow(id:)`) and select an existing screen (Settings/History) — no duplicate
  windows or screens (§22/§23/§24).
- `ContentView`/`SettingsView` — observe the shared menu-bar coordinator; About now reads
  "Milestone 8".

### Added — Tests (30 new; all deterministic via the mock clock, no real menu bar)
- `MenuBarTestSupport` (`MenuBarRig`).
- `MenuBarPresentationTests` — idle/focus/short break/long break/paused/completed/
  interrupted projections + frozen-configuration independence.
- `MenuBarControlTests` — every control routes through `SessionCoordinator`; the countdown
  derives from the authoritative clock; safe no-ops for inapplicable actions.
- `MenuBarPreferencesTests` — defaults, persistence, countdown title, timer untouched.
- `MenuBarRecoveryTests` — recovered running/paused and completed-while-away projections.
- `MenuBarIndependenceTests` — a failing Notification/Calendar integration never breaks the
  menu bar; robustness for empty task names and a deleted configuration.

### Verification
- **290 tests in 46 suites pass** (260 → 290; +30). Clean build, **0 compiler warnings**.

## [Milestone 7 — macOS Notifications] — 2026-08-13

Adds an **optional, isolated** macOS local-notification integration. When enabled, Time
Frame notifies the user as focus sessions and breaks begin and when a session completes,
using the current macOS 27 UserNotifications APIs. UserNotifications is confined to one
adapter; the timer engine and core domain import none of it, and **a notification failure
can never stop or corrupt a timer** (ADR-042). Notifications are a representation of the
authoritative timer, never the source of truth, and are fully independent of the Calendar
integration (§63). No other later-milestone features (Menu Bar, Liquid Glass, Widgets, App
Intents, Siri, iCloud/CloudKit, advanced Statistics) were implemented. See
`docs/16-NOTIFICATIONS.md`.

### Added — Notification domain (pure, `Services/Notifications/`)
- `NotificationCategory`, `NotificationAction`/`ReceivedNotificationAction`,
  `NotificationSound`, `NotificationAuthorizationStatus`, `NotificationIntegrationError` —
  pure vocabulary; no UserNotifications types.
- `NotificationDescriptor`/`NotificationContent`/`NotificationIdentifier` — the pure event
  to schedule and its stable session+interval+type identity (§34).
- `NotificationContentGenerator` — deterministic `Announcement → NotificationContent`
  (Focus / Short break / Long break / Session complete; concise, never-empty titles).
- `NotificationSessionSnapshot` — a `Sendable` projection of a running `FocusSession`.
- `NotificationScheduleBuilder` — `snapshot + preferences → [NotificationDescriptor]`; one
  request per upcoming interval-start boundary, never per tick (ADR-040).
- `NotificationActionResolver` — the pure §40 action-safety rules.

### Added — Service, orchestration & persistence (`Services/Notifications/`)
- `NotificationScheduling` protocol (pure value types) + `UserNotificationService` — the
  **only** file importing UserNotifications; authorization, category/action registration,
  time-interval scheduling, prefix-scoped cancellation, and the notification-center
  delegate that parses responses into pure actions. ADR-038.
- `NotificationCoordinator` (`@MainActor @Observable`) — subscribes to the lifecycle seam,
  schedules/cancels per transition, routes actions through `SessionCoordinator`, defers all
  work and never throws toward the timer. ADR-042/043.
- `NotificationPreferences` + `NotificationPreferencesStore` — preferences in
  `UserDefaults`, **no SwiftData schema change** (ADR-044).

### Added — Timer seam (`Timer/`)
- `SessionCoordinator.currentLifecycleContext()` — read-only accessor so the notification
  layer can reschedule after relaunch recovery and on toggle-on. No UserNotifications
  import; the engine is unchanged. ADR-043.
- The app's fan-out closure now delivers each `SessionLifecycleEvent` to **both** the
  Calendar and Notification coordinators; they observe independently (§8/§63).

### Added — UI (`Views/Notifications/`)
- `NotificationSettingsSection` (in Settings) — master toggle, contextual permission flow
  (Enable / Open System Settings), per-category toggles (focus / short break / long break /
  completion), sound and action-button toggles, with accessibility identifiers (§69).
- `SettingsView` — Notifications section; About now reads "Milestone 7".

### Added — Logging
- `AppLog.notifications` — authorization, scheduling, cancellation counts, received
  actions, and failures; identifiers/counts/statuses only, never titles/bodies (§51).

### Added — Tests (all without a real notification center)
- `FakeNotificationService` + `NotificationRig` helper.
- `NotificationContentTests`, `NotificationScheduleBuilderTests`,
  `NotificationActionResolverTests`, `NotificationCoordinatorTests`,
  `NotificationTimerIndependenceTests`, `NotificationRecoveryTests`.
- **260 tests pass** (was 218), 0 warnings.

### Notes
- No entitlement or Info.plist usage-string is required for local notifications on macOS;
  authorization is requested at runtime, contextually — never on launch (§70).
- A distinct "Plan complete" notification is deferred: a running session carries no plan
  identity by design (ADR-028/029), so plan completion is folded into "Session complete".

## [Milestone 6 — Apple Calendar / EventKit Integration] — 2026-08-13

Adds an **optional, isolated** Apple Calendar integration. Focus plans can be added
to Calendar (single-event or per-interval), and a live session can create/keep a
calendar event using its **actual** timestamps. EventKit is confined to one adapter;
the timer engine and core domain import none of it, and **a Calendar failure can
never stop or corrupt a timer** (ADR-035). Calendar is a representation of Time Frame
activity, never the source of truth. No other later-milestone features (Notifications,
Menu Bar, Liquid Glass, Widgets, App Intents, Siri, iCloud/CloudKit, advanced
Statistics) were implemented. See `docs/15-CALENDAR-INTEGRATION.md`.

### Added — Calendar domain (pure, `Services/Calendar/`)
- `CalendarEventDraft`, `CalendarPlanContext` — framework-independent event/inputs
  (ADR-033).
- `CalendarEventReference`, `CalendarDescriptor`, `CalendarAuthorizationStatus`,
  `CalendarIntegrationError`, `CalendarEventStyle`, `CalendarCreationTrigger` — pure
  vocabulary; no EventKit types.
- `CalendarEventGenerator` — deterministic `CalendarPlanContext → [CalendarEventDraft]`
  (single vs per-interval; titles, notes, `start + total = end`). ADR-033.

### Added — Service, orchestration & persistence (`Services/Calendar/`)
- `CalendarService` protocol (pure value types) + `EventKitCalendarService` — the
  **only** file importing EventKit; full-access authorization, writable-calendar
  listing, create/update/adjust-end/delete, EventKit errors mapped to
  `CalendarIntegrationError`. ADR-032.
- `CalendarCoordinator` (`@MainActor @Observable`) — authorization, calendar
  selection, manual plan add, and the live-session subscription; defers all work and
  never throws toward the timer. ADR-035.
- `CalendarSettings` + `CalendarPreferencesStore` and `CalendarEventRecord` +
  `CalendarEventRecordStore` — settings and associations in `UserDefaults`, **no
  SwiftData schema change** (ADR-037).

### Added — Timer seam (`Timer/`)
- `SessionLifecycleEvent` / `SessionLifecycleContext` — pure, calendar-agnostic
  transition notifications.
- `SessionCoordinator` — new `onLifecycleEvent` closure; emits started/paused/
  resumed/skipped/stopped/completed at meaningful transitions only (never per tick).
  No EventKit import. ADR-035.

### Added — UI (`Views/Calendar/`)
- `CalendarSettingsSection` (in Settings), `CalendarPickerView`,
  `CalendarEventPreviewView` (Add to Calendar from Plan Detail),
  `CalendarSyncStatusView` (quiet status on the Timer), with accessibility
  identifiers/labels and permission/error states.
- `PlanDetailView` — "Add to Calendar" / "Update in Calendar" action + preview sheet.
- `SettingsView` — Calendar section; About now reads "Milestone 6".
- `TimerView` — subtle, non-blocking calendar sync status during a run.

### Added — Project configuration
- Entitlement `com.apple.security.personal-information.calendars` (new
  `time_frame.entitlements`, with `com.apple.security.app-sandbox`).
- `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription` build setting (usage string).

### Added — Tests (all without a real Calendar)
- `FakeCalendarService` + scratch-`UserDefaults` helper.
- `CalendarEventGeneratorTests`, `CalendarPersistenceTests`,
  `CalendarCoordinatorTests`, `CalendarTimerIndependenceTests`. Total **218 tests**
  (184 prior + 34 new), 0 warnings.

### Decisions
- ADR-032 … ADR-037 (see `docs/DECISIONS.md`).

## [Milestone 5 — Session Planner] — 2026-08-13

Adds the Session Planner: persisted, editable multi-session plans that users design,
preview, save, edit, duplicate, and start before execution. A plan is a **planning
layer**, not a second timer — starting one freezes an immutable value snapshot that
runs through the **existing** `SessionCoordinator` → `TimerEngine` → `FocusSession`
path. Plans may mix configurations (per focus item), and a running/historical session
is independent of the saved plan and its configurations. No later-milestone features
(Calendar, EventKit, notifications, menu bar, Liquid Glass, widgets, App Intents,
iCloud/CloudKit, advanced statistics) were implemented; the timer engine is unchanged
apart from a rename. See `docs/14-SESSION-PLANNER.md`.

### Added — Model & schema
- `Models/SessionPlan.swift` — `@Model` (id, name, taskName, createdAt/updatedAt,
  cascade-owned `items`) with `orderedItems`/`focusCount`/`totalDuration`/
  `isStartable`/`draft`/`executionSnapshot`. ADR-026.
- `Models/SessionPlanItem.swift` — `@Model` (id, order, phase `TimerPhase`,
  duration, optional `configuration`, frozen `configurationName`). ADR-027/030.
- `PomodoroConfiguration` — added the `planItems` inverse relationship (delete rule
  **nullify**; ADR-029).
- `SessionInterval` — added `configurationName` (frozen per-interval configuration
  name; ADR-028).
- `TimeFrameSchema` — added `TimeFrameSchemaV5` (current); incompatible older
  on-disk stores are rebuilt, additive changes migrate in place (ADR-016).

### Added — Domain (pure, in `Timer/`)
- `SessionPlanGenerator` — deterministic initial-plan generation with an **optional**
  trailing break (off by default; ADR-026).
- `SessionPlanExecutionSnapshot` — the immutable, `Sendable`, SwiftData-free freeze
  the engine runs from; derives `enginePlan`, totals, and a configuration summary.
  ADR-028.

### Added — Persistence & validation (`Services/Persistence/`)
- `SessionPlanRepository` — create / read / update (item reconciliation by id) /
  delete / duplicate, with by-id configuration resolution and order normalization.
- `SessionPlanValidation` — `SessionPlanDraft`/`PlanItemDraft` + structured
  `SessionPlanValidationError` + `PlanLimits` (≤100 items, ≤8 h/interval, ≤24 h total).
- `SessionRepository` — added `createPlannedSession(...)` (multi-configuration
  intervals, frozen names, no live configuration reference).
- `PersistenceError` — added `invalidPlan([SessionPlanValidationError])`.

### Added — Coordinator & execution
- `SessionCoordinator` — exposes a `plans` repository and `startPlan(_:)`, which runs
  an execution snapshot through the existing engine (no second timer). ADR-028.

### Added — UI (`Views/Plans/`)
- `PlanListView`, `PlanRowView`, `PlanDetailView`, `PlanEditorView`,
  `PlanItemRowView`, `PlanItemEditorView`, `PlanPreviewView` (relative `H:MM`
  timeline). Empty state, validation messages, accessibility identifiers, and
  keyboard shortcuts (⌘N new, ⌘↩ start).
- `AppSection` — added `.plans` between Templates and Configurations.
- "Create Plan" entry points from `TemplateDetailView`/`TemplateListView` and
  `ConfigurationListView` (read-only; the source is never modified — ADR-030).

### Changed — engine plan rename (ADR-031)
- The engine value type `SessionPlan` → **`IntervalPlan`** (`Timer/IntervalPlan.swift`),
  freeing the `SessionPlan` name for the planner model. The Timer setup preview view
  `SessionPlanPreview` → `IntervalPlanPreview`. Pure rename; no behaviour change.

### Tests
- Added `SessionPlanGeneratorTests`, `SessionPlanValidationTests`,
  `SessionPlanRepositoryTests`, `SessionPlanExecutionTests` (execution, multi-config,
  the four independence guarantees, recovery). **184 tests pass** (138 pre-existing +
  46 new); zero warnings. Renamed `SessionPlanTests` → `IntervalPlanTests`.

### Verified
- Build succeeds; full suite green. App launched: the V5 schema opens cleanly, the
  Configuration→Plan generation, editor, save, detail preview, Start→Timer (running
  the plan's frozen values), pause, stop, and History recording were confirmed in the
  GUI.

## [Milestone 4 — Task Templates] — 2026-08-13

Adds Task Templates: reusable task definitions (a template name, a task name, a
referenced Pomodoro configuration, and a default session count) that start sessions
efficiently through the **existing** setup/coordinator/engine path. A template is a
reusable starting point, never a `FocusSession` and never a historical record — it
is independent of the sessions it starts. No later-milestone features (Calendar,
EventKit, notifications, menu bar, Liquid Glass, session planner, statistics,
widgets, App Intents, iCloud) were implemented; the timer engine remains
SwiftData-free and unchanged.

### Added — Model & schema
- `Models/TaskTemplate.swift` — `@Model` (id, name, taskName, configuration
  reference, defaultTotalSessions, isDefault, createdAt/updatedAt) with
  `hasConfiguration`/`displayConfigurationName`. See ADR-021.
- `PomodoroConfiguration` — added the `taskTemplates` inverse relationship
  (delete rule **nullify**; ADR-024).
- `TimeFrameSchema` — added `TimeFrameSchemaV4` (current, adds `TaskTemplate`);
  incompatible older on-disk stores are rebuilt (ADR-016/019/021).

### Added — Persistence & validation (`Services/Persistence/`)
- `TaskTemplateRepository` — create / read / update / delete / duplicate /
  set-default / clear-default, with by-id configuration resolution.
- `TaskTemplateValidation` — `TaskTemplateDraft` + structured
  `TaskTemplateValidationError` (name required, task required, configuration
  required, session count 1…24).
- `PersistenceError` — added `invalidTemplate([TaskTemplateValidationError])`.

### Added — Coordinator & start seam
- `SessionCoordinator` — exposes a `templates` repository (alongside
  `configurations`/`sessions`).
- `SessionSetupPrefill` — value that carries a template's starting values into the
  Timer setup screen; Start then runs the existing
  `startSession(configuration:taskName:totalSessions:)` (no second start path;
  ADR-023/025).

### Added — UI (`time_frame/Views/Templates/`)
- `TemplateListView`, `TemplateRowView`, `TemplateDetailView`, `TemplateEditorView`
  — sidebar area, list, detail (Start / Edit / Duplicate / Delete), create/edit
  sheet with inline validation, empty state, and a "Configuration unavailable"
  state (text + icon, never colour alone) with a Choose-Configuration action.
- `AppSection` — added the `templates` case (Today / Timer / **Templates** /
  Configurations / History / Settings).
- `ContentView` / `TimerView` / `SessionSetupView` — thread the template prefill to
  the setup screen; the per-run session count is prefilled and editable without
  mutating the template.
- `ConfigurationListView` — the delete confirmation now also reports how many task
  templates reference the configuration (ADR-024).
- Accessibility identifiers on key template controls (`template.new`,
  `template.save`, `template.detail.start`, …).

### Added — Documentation
- `docs/13-TASK-TEMPLATES.md` — concept, model, lifecycle, validation, the
  template → session flow, deletion behaviour, independence, and future
  compatibility.
- `docs/DECISIONS.md` — ADR-021 … ADR-025.
- Updated `01-ARCHITECTURE.md`, `02-DATA-MODEL.md`, `10-TESTING-PLAN.md`,
  `CLAUDE.md`.

### Added — Tests (`time_frameTests/`)
- `TaskTemplateValidationTests` (9), `TaskTemplateRepositoryTests` (14),
  `Milestone4ApplicationTests` (12) — model, template → session workflow, per-run
  override isolation, template/config edit & delete independence, and the
  template-started session lifecycle. Added `makeTemplateRepository` to
  `PersistenceTestSupport`.
- **138 tests total (103 existing + 35 new), all passing. No existing test was
  weakened or removed.**

### Verification
- `xcodebuild … build` → `** BUILD SUCCEEDED **`, no warnings.
- `xcodebuild … test` → 138/138 passing (parallel and serial).

## [Milestone 3 — Core Time Frame Experience] — 2026-08-13

Turns the functional foundation into the first usable application: a native macOS
sidebar app with a real timer, configuration management, session setup, read-only
history, and keyboard shortcuts. Functional UI only — no Liquid Glass, Calendar,
notifications, menu bar, templates, planner, widgets, App Intents, or statistics
(all remain deferred). The timer engine remains SwiftData-free and the single
source of truth; no per-second persistence was introduced.

### Added — UI (`time_frame/Views/`)
- Navigation: `AppSection` + a `NavigationSplitView` root in `ContentView`
  (Today / Timer / Configurations / History / Settings).
- Timer: `TimerView` (orchestrator), `TimerDisplay` (TimelineView-driven
  countdown), `TimerControls`, `SessionProgressView`, `SessionSetupView`,
  `SessionPlanPreview`, `CompletionView`. Shows task, configuration, phase,
  remaining, session N-of-M, next-up; renders idle/running/paused/completed and
  restored/interrupted recovery states.
- Configurations: `ConfigurationListView`, `ConfigurationRowView`,
  `ConfigurationEditorView` — create / edit / duplicate / set-default / delete
  (with a confirmation that explains history is preserved), using the existing
  `ConfigurationValidation` (friendly messages, no raw errors).
- History: `HistoryListView` (grouped by day) + `HistoryDetailView`, read-only,
  derived entirely from persisted intervals and the frozen configuration name.
- Today: `TodayView` dashboard (active-session card, today's focus totals).
- Settings: `SettingsView` (default-configuration picker, keyboard-shortcut
  reference).
- Components/support: `EmptyStateView`, `StatusPresentation`,
  `ConfigurationSummaryView`, `TimeFormatting`.

### Added — Application logic & recovery surfacing
- `SessionSetupDraft` — pure setup value (task required, session-count override,
  plan-preview generation).
- `PomodoroConfigurationSnapshot.overriding(totalSessions:)` — per-run count
  override that never mutates the saved configuration.
- `SessionCoordinator` — `startSession(…, totalSessions:)`, observable
  `recoveryOutcome`/`interruptedSession`, `acknowledgeRecovery()`, and
  `prepareForNewSession()` (reset after a finished run).

### Changed — Model & schema
- `FocusSession` — added `configurationName` (frozen at start) and
  `displayConfigurationName`, plus history-derived helpers
  (`completedFocusCount`, `plannedFocusCount`, `completedFocusDuration`,
  `startDay`). See ADR-019.
- `SessionRepository.createSession` — captures the configuration name snapshot.
- `TimeFrameSchema` — added `TimeFrameSchemaV3` (current); incompatible older
  on-disk stores are rebuilt (ADR-016/019).
- `time_frameApp` — window sizing (`defaultSize`, `windowResizability`);
  `ContentView` replaced the minimal harness with the sidebar app.

### Added — Documentation
- `docs/12-CORE-UI.md` — navigation, UI architecture, state flow, setup/config/
  history workflows, keyboard shortcuts, accessibility.
- `docs/DECISIONS.md` — ADR-017 … ADR-020.
- Updated `01-ARCHITECTURE.md`, `10-TESTING-PLAN.md`.

### Added — Tests (`time_frameTests/`)
- `SessionSetupDraftTests` (6) — task validation, count override, plan preview,
  snapshot override.
- `Milestone3ApplicationTests` (12) — count override vs. configuration
  immutability, configuration-name snapshot (rename/delete), history-derived
  values, edit-while-running isolation, start-new-session reset, and
  restored/interrupted recovery outcomes.
- **103 tests total (85 existing + 18 new), all passing. No existing test was
  weakened or removed.**

### Verification
- `xcodebuild … build` → `** BUILD SUCCEEDED **`, no warnings.
- `xcodebuild … test` → `** TEST SUCCEEDED **`, 103/103 passing.
- Launched the built app and manually verified the primary workflow end-to-end:
  setup (task + configuration + count + plan preview) → Start (⌘↩) → running
  countdown with progress and next-up → Pause (frozen) → Stop → the session
  appears in History grouped under Today.

## [Milestone 2 — Persistence & Session Lifecycle] — 2026-08-13

Connects the Milestone 1 timer/domain architecture to durable SwiftData
persistence and establishes a reliable, recoverable session lifecycle. The timer
engine remains pure (no SwiftData). No later-milestone features were implemented.

### Added — Domain vocabulary & recovery seam (`Timer/`)
- `SessionStatus` — persisted session lifecycle (planned / running / paused /
  completed / cancelled / interrupted), distinct from the engine's `TimerState`.
- `IntervalStatus` — persisted interval lifecycle (pending / running / paused /
  completed / skipped / cancelled).
- `TimerEngineSnapshot` — pure value describing engine state for recovery.
- `TimerEngine` — added `restore(from:)` and read-only anchor accessors
  (`currentIntervalStart`, `currentIntervalEnd`). Still imports no SwiftData.

### Added — Persistence services (`Services/Persistence/`)
- `ConfigurationRepository` — create / read / update / delete / duplicate /
  set-default / idempotent seeding.
- `SessionRepository` — session + interval creation, recoverable-session fetch,
  and single-save reconciliation (`applySync`); `IntervalSync` / `SessionSync`.
- `ConfigurationValidation` — `ConfigurationDraft`, structured
  `ConfigurationValidationError`, and `ConfigurationLimits`.
- `PersistenceError` — structured, observable failures.
- `AppLog` — `os.Logger` channels (identifiers/counts only, never user content).

### Changed — Coordinator, models, schema, app
- `SessionCoordinator` — now orchestrates persistence: mirrors every lifecycle
  transition into SwiftData through the repositories, performs app-relaunch
  `recover()`, and reconciles on `NSWorkspace.didWakeNotification`. Added
  `startSession`, `pause/resume/stop/skip/restart` (persisting), `tick()`, and an
  `autoTick` flag so tests drive it deterministically.
- `PomodoroConfiguration` — added `isDefault`.
- `FocusSession` — `status` is now `SessionStatus`; added `pausedAt` and a
  `currentInterval` helper.
- `SessionInterval` — added `status: IntervalStatus`, `targetEndAt`,
  `remainingAtPause`; replaced the bare `isCompleted`/`outcome` pair.
- `TimeFrameSchema` — added `TimeFrameSchemaV2` (current) + `TimeFrameSchemaLatest`;
  `PersistenceController` rebuilds an incompatible legacy on-disk store (ADR-016).
- `time_frameApp` — creates the shared coordinator, seeds (idempotent), and
  recovers a previously live session at launch.
- `ContentView` — drives the persisting coordinator (start/pause/resume/stop) from
  the default configuration; still intentionally minimal.

### Added — Documentation
- `docs/04-SESSION-LIFECYCLE.md` — states, persistence lifecycle, recovery,
  termination, sleep/wake, timestamp authority, configuration, error handling.
- `docs/DECISIONS.md` — ADR-011 … ADR-016.
- Updated `01-ARCHITECTURE.md`, `02-DATA-MODEL.md`, `03-TIMER-ENGINE.md`,
  `10-TESTING-PLAN.md`.

### Added — Tests (`time_frameTests/`)
- `TimerEngineRestoreTests` (5), `ConfigurationValidationTests` (7),
  `ConfigurationRepositoryTests` (11), `SessionLifecycleTests` (8),
  `SessionRecoveryTests` (7), `OnDiskRelaunchTests` (1), plus
  `PersistenceTestSupport`.
- **85 tests total (46 existing + 39 new), all passing.**

### Verification
- `xcodebuild … clean build test` → `** BUILD SUCCEEDED **`, no warnings.
- 85/85 tests passing (parallel and serial). The app launches (container +
  seeding + recovery run at init without crashing).

## [Milestone 1 — Foundation] — 2026-08-13

The production-grade technical foundation: documentation, architecture, the
SwiftData domain model, and a reliable, deterministic timer engine with tests.
No later-milestone features (Calendar, notifications, menu bar, Liquid Glass UI,
etc.) were implemented.

### Added — Documentation
- `CLAUDE.md` — project constitution (principles, workflow, phase discipline).
- `docs/00-PRODUCT-REQUIREMENTS.md` — feature set and explicit V1 boundaries.
- `docs/01-ARCHITECTURE.md` — layered architecture and key decisions.
- `docs/02-DATA-MODEL.md` — SwiftData model, relationships, delete rules.
- `docs/03-TIMER-ENGINE.md` — state machine, accuracy model, controls.
- `docs/10-TESTING-PLAN.md` — deterministic testing strategy and coverage.
- `docs/DECISIONS.md` — architecture decision record (ADR-001 … ADR-010).
- `docs/CHANGELOG.md` — this file.

### Added — Domain / Timer engine (`time_frame/time_frame/Timer/`)
- `TimerPhase` — focus / shortBreak / longBreak.
- `TimerState` — idle / running / paused / completed / cancelled.
- `TimeSource` — `TimeProviding` protocol + `SystemTimeSource` (injectable clock).
- `PomodoroConfigurationSnapshot` — validated value the engine runs from.
- `SessionPlan` / `PlannedInterval` — configuration-driven sequence generation
  with short/long-break logic.
- `IntervalRecord` / `IntervalOutcome` — in-memory interval history.
- `TimerEngine` — authoritative, timestamp-based state machine with
  start/pause/resume/stop/skip/restart/reset/load and `synchronize()`.
- `SessionCoordinator` — production heartbeat driver (`@MainActor`, cancellable
  `Task`).

### Added — Data model (`time_frame/time_frame/Models/`)
- `PomodoroConfiguration`, `FocusSession`, `SessionInterval` `@Model` types with
  explicit relationships and delete rules (cascade for intervals, nullify for
  configuration).

### Added — Persistence (`time_frame/time_frame/Services/Persistence/`)
- `TimeFrameSchemaV1` (`VersionedSchema`) + `TimeFrameMigrationPlan`.
- `PersistenceController` — container factory (on-disk / in-memory) and default
  configuration seeding.

### Added — Tests (`time_frame/time_frameTests/`)
- New `time_frameTests` unit-test target (Swift Testing), shared scheme.
- `MockTimeSource`, `TestSupport`, and suites covering configuration, plan
  generation, state transitions, controls, sequence/authoritative-clock
  behaviour, edge cases, and persistence.
- **46 tests, all passing.**

### Changed
- `time_frameApp.swift` — builds and injects the SwiftData `ModelContainer` (with
  an in-memory fallback) and seeds the default configuration at launch.
- `ContentView.swift` — replaced the template with a minimal, intentionally
  unstyled harness that drives the engine end-to-end (phase, remaining time,
  state, controls). The polished UI remains a later milestone.

### Project
- Added the `time_frameTests` target and a shared `time_frame.xcscheme` to
  `time_frame.xcodeproj`. Deployment target remains macOS 27; bundle identifier
  and automatic signing unchanged.

### Verification
- `xcodebuild … build` → `** BUILD SUCCEEDED **` (no warnings).
- `xcodebuild … test` → `** TEST SUCCEEDED **`, 46/46 tests passing.
- The app launches (exercised as the test host, initializing on-disk SwiftData
  and seeding the default configuration).
