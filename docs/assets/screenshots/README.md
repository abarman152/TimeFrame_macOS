# Screenshot Inventory

Every image in this directory is a real, unretouched screenshot of Time Frame running on an
Apple simulator. Nothing here is a mockup, a render, or a composite. Where a surface could not be
captured in this environment, it is listed in "Not captured" below rather than substituted with an
illustration.

Captured on 2026-09-06 by driving the app on a booted simulator (`xcrun simctl io … screenshot`),
with taps issued through the simulator control tool.

## Capture environment

| Property | Value |
|---|---|
| iPhone simulator | iPhone 17 Pro, iOS 26 runtime |
| iPad simulator | iPad Pro 11-inch (M5) |
| Build configuration | Debug |
| Status bar | Normalised via `simctl status_bar override` (09:41, full signal, charged) |
| Data | Real app data produced by using the app in the simulator; see "About the data" |

The status bar override is the standard Apple practice for product screenshots. It changes only the
system status bar, never the application's own interface.

## About the data

The history, Today and Statistics figures are genuine output from sessions actually run in the
simulator. They were not seeded or edited.

One session was started the previous evening and left running. On the next launch, Time Frame's
recovery reconciled it against the authoritative timeline and fast-forwarded through every interval
whose planned end had passed, completing the session. That is the documented relaunch behaviour, and
it is why the Statistics screen shows four completed focus intervals totalling 1h 40m.

## iOS (iPhone)

| Screenshot | Surface | What it shows | Environment |
|---|---|---|---|
| `ios-timer-idle.png` | Timer | Idle state with the seeded "Classic Pomodoro" configuration and its start control | iPhone simulator |
| `ios-timer-running.png` | Timer | A running focus interval: phase, countdown, session position, Pause / Skip / Stop | iPhone simulator |
| `ios-timer-paused.png` | Timer | The same session paused: countdown frozen, controls become Resume / Restart / Stop | iPhone simulator |
| `ios-today.png` | Today | Today's focus time, completed sessions, focus intervals, break time, best focus day | iPhone simulator |
| `ios-history.png` | History | Recorded sessions with their frozen configuration name and final status | iPhone simulator |
| `ios-statistics.png` | Statistics | Period picker (Today / This Week / This Month) and the derived focus metrics | iPhone simulator |
| `ios-settings.png` | Settings | Notifications, Live Activity, iCloud and About sections | iPhone simulator |
| `ios-notification-permission.png` | Settings | The in-app notification permission request, before system authorisation | iPhone simulator |
| `ios-live-activity-lockscreen.png` | Live Activity | The Lock Screen Live Activity: phase, session position, countdown, and the Pause / Skip / Stop controls | iPhone simulator |

## iPadOS

No iPad screenshot was obtained. The iPad simulator did not finish booting within the time available,
so the only capture produced showed the boot logo rather than the application; it was discarded rather
than shipped under a misleading name.

iPadOS runs the same universal iOS target as iPhone, and its layout is exercised by the iPad test
suite, but that is source and test coverage — not a screenshot.

## Not captured in this environment

These surfaces exist in the product and are covered by source and tests, but no screenshot was
produced. No placeholder or mockup has been substituted for any of them.

| Surface | Why not captured |
|---|---|
| macOS application (Timer, Templates, Plans, Configurations, Today, History, Statistics, Settings, menu bar) | `screencapture` is refused on this machine — the automation process has not been granted Screen Recording permission. In Milestone 29 every one of these screens *was* rendered and inspected on screen in both Light and Dark Mode, but the surface that produced those frames exposes no path the repository can read, so no image file could be written. Nothing has been substituted for them. See the [macOS inventory](macos/README.md). |
| macOS widget | Same Screen Recording restriction. |
| iOS Home Screen widget (with live data) | The widget was added to the Home Screen and its gallery entry was confirmed, but it renders only its placeholder. This build is unsigned, so the App Group entitlement is not embedded and the shared projection the widget reads is unavailable. This is a limitation of an unsigned local build, not of the widget. |
| iOS Lock Screen accessory widgets | Require the same App Group projection as above. |
| Control Center controls | Require a provisioned build to appear in the Control Center gallery. |
| Dynamic Island (compact and expanded) | The Live Activity was observed in the Dynamic Island during capture, but a clean, correctly cropped screenshot of it was not obtained before the session ended. |
| Configuration creation and editing | These screens exist on macOS only; see the macOS row above. iOS has no configuration editor. |

## Verification status of these screenshots

- Screenshot verified: every row in the iOS table above.
- Simulator verified, not screenshot verified: the Live Activity appearing in the Dynamic Island.
- Physical device required: notification banner delivery, StandBy, real Dynamic Island interaction,
  and VoiceOver behaviour.
- Not performed: any capture on macOS that produced a file. The macOS screens were visually verified
  in the running application (Milestone 29) but could not be written to disk here.

## Reproducing these screenshots

```bash
xcrun simctl boot "iPhone 17 Pro"
xcodebuild -project time_frame/time_frame.xcodeproj -scheme TimeFrameiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build
xcrun simctl install booted <path-to>/TimeFrameiOS.app
xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100
xcrun simctl launch booted abirbarman.com.time-frame
xcrun simctl io booted screenshot ios-timer-idle.png
```

To capture the widget and Control Center surfaces, build with your own signing team so the App Group
entitlement is embedded.
