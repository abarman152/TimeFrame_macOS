# Milestone 32 — Open at Login and Single-Window Management

**Status:** implemented
**ADRs:** [ADR-111](DECISIONS.md#adr-111--time-frame-has-one-main-window-and-one-pathway-to-it), [ADR-112](DECISIONS.md#adr-112--the-login-item-is-registered-with-smappservice-and-the-system-is-the-source-of-truth)
**Schema:** V7 (unchanged)

Two related pieces of macOS application behaviour that had never been stated: *when does Time
Frame start*, and *how many windows does it have*.

---

## 1. The problem

### Duplicate windows

Time Frame's main scene was a `WindowGroup`:

```swift
WindowGroup(id: MainWindow.id) { ContentView(...) }
```

A `WindowGroup` is, by definition, a group: SwiftUI may present more than one window from it,
`openWindow(id:)` **creates a new one on every call**, and the system adds a File ▸ New Window
command. Four separate surfaces each held that capability and each wrote their own version of the
same three lines:

```swift
navigation.request(section)
NSApplication.shared.activate(ignoringOtherApps: true)
openWindow(id: MainWindow.id)          // ← a new window, every time
```

`MenuBarGearMenu`, `MenuBarOpenSectionButton`, the popover's `MenuBarStartButton` — and a Dock
reopen, which nothing handled at all. There was no policy anywhere; there were four copies of an
action. A fifth surface would have arrived the same way.

The Dock case was worse than a duplicate. With no `applicationShouldHandleReopen`, the default
machinery treats "no **visible** window" as "no window" — and a window is not visible when it is
minimized, or when the application is hidden. Clicking the Dock icon with the window sitting in
the Dock produced a *second* window while the first stayed minimized.

### No Open at Login

There was no setting, and no login item.

---

## 2. What was built

### One window, expressed by the scene type

The main scene is now a single-instance `Window`:

```swift
Window("Time Frame", id: MainWindow.id) { … }
```

SwiftUI cannot present a second one. This is the load-bearing part of the fix: the guarantee is
architectural, not defensive. There is no File ▸ New Window (the app has no File menu at all), and
no code path — existing or future — can produce a duplicate.

### One pathway

Everything that can ask for the window goes through one place:

```
gear menu ─┐
Start fallback ─┤
Quick Start empty state ─┼──► showMainWindow(section?) ──► MainWindowPresenter
Dock reopen ─┘                                                    │
                                              MainWindowPolicy ◄──┤ (pure decision)
                                              AppKitMainWindowHost ◄┘ (AppKit steps)
```

| File | Role |
|---|---|
| `Services/Window/MainWindowPolicy.swift` | The pure decision. No AppKit, no SwiftUI, no state. |
| `Services/Window/MainWindowPresenter.swift` | The one policy, shared by every surface. Owns no window. |
| `Services/Window/AppKitMainWindowHost.swift` | Finds the `NSWindow` and performs the steps. Decides nothing. |
| `Services/Window/MainWindowPresentation.swift` | Captures `openWindow` once per scene and republishes it as `\.showMainWindow`. |
| `Services/Window/TimeFrameAppDelegate.swift` | Answers `applicationShouldHandleReopen`. Owns the presenter. |

A view now reads:

```swift
@Environment(\.showMainWindow) private var showMainWindow
…
Button("Settings") { showMainWindow(.settings) }
```

It knows nothing about windows. `openWindow` appears in exactly one file in the whole codebase,
and an audit fails the build if a second one appears.

### The decision

`MainWindowPolicy.action(for:applicationIsHidden:creationIsPending:)` is a pure function over a
snapshot read fresh from the live window on **every** request:

| Live state | Action |
|---|---|
| No window | `createWindow` |
| On screen | `reuseExisting(unhide: false, deminiaturize: false)` |
| Minimized | `reuseExisting(unhide: false, deminiaturize: true)` |
| Application hidden | `reuseExisting(unhide: true, deminiaturize: false)` |
| Minimized *and* hidden | `reuseExisting(unhide: true, deminiaturize: true)` |
| No window, create already in flight | `coalesced` |

There is deliberately **no** `windowIsOpen` boolean. A boolean is wrong the moment the user closes,
minimizes, or hides the window, or SwiftUI rebuilds the scene — and being wrong is exactly what
produced the second window. The window's own state is the only state consulted, and the host holds
its `NSWindow` **weakly** and deregisters on `NSWindow.willCloseNotification`, so a closed window
leaves nothing behind to focus.

### The creation race

Two requests in the same run-loop turn both see "no window". The first issues a create and marks it
pending; every request until the end of that turn is `coalesced`. The mark is released by a one-shot
main-actor continuation and by the window registering itself — never by a timer and never by a poll,
so a create that somehow never lands is retried by the next request rather than ignored forever.

### The Dock

```swift
func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    let action = windowPresenter.showMainWindow()
    …
}
```

`hasVisibleWindows` is not consulted. The presenter reads the real window state, so a minimized or
hidden window is restored rather than duplicated. `false` is returned when the reopen was fully
handled; `true` only when there is genuinely no window and no opener, so AppKit can run its own
reopen for the single `Window` scene.

### Closing the window must not quit the app

This one was found by measurement, not by reading. Under `WindowGroup`, SwiftUI kept the process
alive when the last window closed — which is what let the menu bar, and a running Pomodoro, survive
a ⌘W. **A single-instance `Window` does not.** Both builds were launched and their windows closed:
the old one stayed running, the new one terminated.

`applicationShouldTerminateAfterLastWindowClosed` therefore returns `false`, restoring the
documented behaviour exactly. Quitting stays where it always was: ⌘Q and the popover's Quit item.

### What focusing a window does *not* do

Nothing. It activates the app, deminiaturizes if needed, and calls `makeKeyAndOrderFront` — the
ordinary macOS focus appearance, with no artificial flash or custom highlight. It does not touch
the sidebar selection (unless a section was explicitly requested), the scroll position, the setup
fields, the engine, or the session. `MainWindowTimerSafetyTests` drives a real `SessionCoordinator`
and asserts that four window requests leave the session id, engine state, phase, remaining time and
interval count unchanged, with no second `FocusSession` recorded.

---

## 3. Open at Login

### The API

`SMAppService.mainApp` — the modern ServiceManagement login item. The app registers *itself*; there
is no helper bundle, no `SMLoginItemSetEnabled`, and no `LSSharedFileList`. An audit fails the build
if a deprecated mechanism appears.

`LoginItemService.swift` is the **only** file that imports ServiceManagement, mirroring
`EventKitCalendarService` and `UserNotificationService`.

### The system is the source of truth

The one rule that matters: a setting that reads "on" while nothing is registered is worse than no
setting, because the user only finds out at the next login.

So nothing about the login item is persisted. There is no `UserDefaults` key and no `@AppStorage`.
`LoginItemCoordinator.isEnabled` is derived from `LoginItemStatus`, which is read back from
`SMAppService` on launch, whenever Settings appears, and **after every change**:

```swift
// Whatever happened, the system's answer wins.
status = service.currentStatus()
```

| System status | Toggle | Why |
|---|---|---|
| `.enabled` | on | registered and approved |
| `.notRegistered` / `.notFound` | off | not registered |
| `.requiresApproval` | **off**, with an explanation | it will not launch until the user approves it in System Settings |
| unknown | off, reported unavailable | never guessed |

A refused registration leaves the switch **off** and states why. A refused removal leaves it **on**.
The registration awaiting approval offers "Open Login Items Settings" rather than retrying.

### Failure handling

`LoginItemError` is a closed set (`registrationFailed`, `unregistrationFailed`, `requiresApproval`,
`unavailable`), each with a description and a remedy. A raw `SMAppService` error is never shown.
One attempt per user action: `guard !isChanging else { return }` and no scheduling primitive
anywhere in the coordinator, so a failure can never become a retry loop.

`register()`/`unregister()` are `nonisolated async`, so ServiceManagement runs off the main actor
and a slow response cannot block the UI. Under the XCTest host the app injects
`UnavailableLoginItemService`, so the suite can never register the developer's build as a login
item — the same hermeticity rule as ADR-077.

### The setting

Settings ▸ General, as a native `Toggle` in the existing grouped `Form`:

```
General
    Open at Login                                              [ ● ]
    Automatically open Time Frame when you log in to your Mac.
```

Accessibility label "Open Time Frame at Login"; the on/off value and its changes are announced by
the native control. A failure appears as a `TFNoticeBanner` whose words carry the meaning, with the
System Settings action beside it when that is the remedy.

---

## 4. Files

**Added**

```
time_frame/Services/Window/MainWindowPolicy.swift
time_frame/Services/Window/MainWindowPresenter.swift
time_frame/Services/Window/AppKitMainWindowHost.swift
time_frame/Services/Window/MainWindowPresentation.swift
time_frame/Services/Window/TimeFrameAppDelegate.swift
time_frame/Services/Login/LoginItemService.swift
time_frame/Services/Login/LoginItemCoordinator.swift
time_frame/Views/Settings/LoginItemSettingsSection.swift
time_frameTests/MainWindowPresentationTests.swift
time_frameTests/LoginItemTests.swift
time_frameTests/ProductionReadinessM32Tests.swift
```

**Changed**

```
time_frame/time_frameApp.swift                       WindowGroup → Window; delegate; login coordinator
time_frame/ContentView.swift                         carries the login coordinator
time_frame/Views/Settings/SettingsView.swift         General section; refresh on appear
time_frame/Views/MenuBar/MenuBarGearMenu.swift       showMainWindow
time_frame/Views/MenuBar/MenuBarOpenSectionButton.swift
time_frame/Views/MenuBar/TimeFrameMenuBarView.swift  showMainWindow; no AppNavigation plumbing
time_frame/Views/MenuBar/MenuBarQuickStartView.swift
Core/Services/Persistence/AppLog.swift               appLifecycle log channel
```

The menu bar no longer takes an `AppNavigation` at all — the seam moved behind `showMainWindow`.

---

## 5. Verification

### Automated

macOS suite: **1063 tests in 216 suites passed** (baseline 998 in 211). Debug build, Release build
and the iOS build all succeed with **0 compiler warnings**.

`ProductionReadinessM32Tests` fails the build if:

- a `WindowGroup` appears in production source;
- `openWindow` appears outside `MainWindowPresentation.swift`;
- window ordering (`makeKeyAndOrderFront`, `orderFront`, `deminiaturize`, `unhide`) appears outside
  the AppKit host;
- an application activator appears outside the host and `NotificationCoordinator`;
- a menu bar view opens or activates anything itself;
- the reopen handler branches on `hasVisibleWindows`;
- closing the window is allowed to quit the app;
- a boolean caches window state, or the host holds its window strongly;
- the policy imports AppKit, or the window layer gains a clock, a store, or a domain type;
- ServiceManagement is imported by more than one file, or a deprecated login-item API is used;
- the login item is persisted in `UserDefaults`, or a change stops re-reading the system;
- the login-item coordinator gains a retry loop;
- more than one `TimerEngine`, `SessionCoordinator`, app delegate, or presenter exists.

### Manual — window behaviour

Performed by launching the Release build with an isolated store
(`TIMEFRAME_STORE_DIRECTORY`), driving reopen through LaunchServices (the Dock-click path) and
minimize/hide/close through the accessibility API, and counting windows via `CGWindowList` and the
process's accessibility window list:

| Step | Standard windows |
|---|---|
| Launch | 1 |
| 4 × reopen | 1 |
| Minimize, then reopen | 1 (restored, `AXMinimized` false) |
| Hide application, then reopen | 1 |
| Close the window | 0 — **process still alive** |
| 3 × reopen after close | 1 |

One process throughout. The application has no File menu, so no New Window command exists.

### Not verified

- **Launch at login was not tested by logging out and back in.** The registration API and its
  states are covered by tests over the service seam; the physical login was not performed.
- **`SMAppService` registration itself was not exercised against the real login-item database.**
  Doing so would register a development build on the developer's Mac. The smoke-test build is
  ad-hoc signed, where registration is expected to fail — which is the case the UI reports honestly.
- **No screenshots.** Screen capture is unavailable in the environment where these docs were
  written, and none has been fabricated (see the macOS screenshots note in `README.md`).
- The Settings toggle was **not** confirmed on screen: this app's SwiftUI content exposes an empty
  accessibility tree to System Events, so the control could not be located. Its presence, wording,
  identifier and accessibility label are asserted by source audit instead.

---

## 6. Consequences

- Users lose the ability to open a second window of Time Frame. That was never a supported
  workflow, and the window is a single-selection sidebar app.
- Saved window frames move from the `main-AppWindow-1` key to `main`, so the window's remembered
  size and position reset once on first launch after upgrading.
- The window layer is macOS-only and lives in the macOS app target. `Core/` is untouched by it, and
  the iOS companion is unaffected.
- The schema stays **V7**. No model, repository, engine, coordinator, widget, intent, notification
  or CloudKit behaviour changed.
