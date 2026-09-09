<div align="center">
  <img src="assets/app-icon.png" alt="Time Frame" width="88">
  <h1>Time Frame Documentation</h1>
</div>

The index for everything written about Time Frame. Start with the User Guide if you want to use the
app, or the Developer Overview if you want to work on it.

---

## Start here

| Document | For |
|---|---|
| [macOS User Guide](35-MACOS-USER-GUIDE.md) | Using Time Frame on the Mac: every screen and setting, which feature to use when, workday workflows, troubleshooting and an FAQ |
| [User Guide (cross-platform)](35-USER-GUIDE.md) | Using Time Frame across macOS, iPhone and iPad, illustrated with iPhone screenshots |
| [Developer Overview](36-DEVELOPER-OVERVIEW.md) | Orientation for a new developer: layering, targets, concurrency model, invariants |
| [Product Requirements](00-PRODUCT-REQUIREMENTS.md) | What the product is, and what is deliberately out of scope |
| [Architecture](01-ARCHITECTURE.md) | The full architecture |
| [Decisions](DECISIONS.md) | Every architectural decision record, with reasoning |
| [Changelog](CHANGELOG.md) | What changed, milestone by milestone |

## User documentation

- [macOS User Guide](35-MACOS-USER-GUIDE.md) — the Mac-specific manual
  - [Quick start](35-MACOS-USER-GUIDE.md#2-quick-start)
  - [Choosing the right feature](35-MACOS-USER-GUIDE.md#3-choosing-the-right-feature)
  - [Timer configurations](35-MACOS-USER-GUIDE.md#11-timer-configurations)
  - [The menu bar](35-MACOS-USER-GUIDE.md#18-the-menu-bar)
  - [Keyboard shortcuts](35-MACOS-USER-GUIDE.md#23-keyboard-shortcuts)
  - [A workday with Time Frame](35-MACOS-USER-GUIDE.md#24-a-workday-with-time-frame)
  - [Troubleshooting](35-MACOS-USER-GUIDE.md#25-troubleshooting)
  - [Feature reference](35-MACOS-USER-GUIDE.md#30-feature-reference)
- [User Guide (cross-platform)](35-USER-GUIDE.md)
  - [Getting started](35-USER-GUIDE.md#3-getting-started)
  - [Understanding the timer](35-USER-GUIDE.md#4-understanding-the-timer)
  - [Settings](35-USER-GUIDE.md#14-settings)
  - [Accessibility](35-USER-GUIDE.md#15-accessibility)
  - [Data and privacy](35-USER-GUIDE.md#17-data-and-privacy)
  - [Troubleshooting](35-USER-GUIDE.md#18-troubleshooting)
  - [FAQ](35-USER-GUIDE.md#19-faq)
  - [Known limitations](35-USER-GUIDE.md#21-known-limitations)
- [Screenshot inventory (iPhone)](assets/screenshots/README.md)
- [Screenshot inventory (macOS)](assets/screenshots/macos/README.md) — what was captured, in what environment, and
  what could not be captured

## Developer documentation

### Foundations

| Document | Subject |
|---|---|
| [Developer Overview](36-DEVELOPER-OVERVIEW.md) | Orientation and invariants |
| [Architecture](01-ARCHITECTURE.md) | Layering and module boundaries |
| [Data Model](02-DATA-MODEL.md) | SwiftData models, schema V6, frozen historical identity |
| [Timer Engine](03-TIMER-ENGINE.md) | The state machine and its timestamp-authoritative timing |
| [Session Lifecycle](04-SESSION-LIFECYCLE.md) | States, transitions, persistence and recovery |
| [Testing Plan](10-TESTING-PLAN.md) | Test strategy and coverage |

### Application features

| Document | Subject |
|---|---|
| [Core UI](12-CORE-UI.md) | The macOS application surfaces |
| [Task Templates](13-TASK-TEMPLATES.md) | Reusable task presets |
| [Session Planner](14-SESSION-PLANNER.md) | Multi-configuration session plans |
| [Statistics](19-STATISTICS.md) | The read-only analytics projection |
| [Liquid Glass Design](18-LIQUID-GLASS-DESIGN.md) | The presentation-layer design system |
| [Menu Bar](17-MENU-BAR.md) | The macOS status-item surface |
| [Open at Login and Window Management](41-M32-LOGIN-ITEM-AND-WINDOW-MANAGEMENT.md) | The single main window, Dock reopen, and the login item |

### Platform integrations

| Document | Subject |
|---|---|
| [Calendar Integration](15-CALENDAR-INTEGRATION.md) | EventKit, isolated behind a service |
| [Notifications](16-NOTIFICATIONS.md) | Local notifications on macOS and iOS |
| [WidgetKit](20-WIDGETKIT.md) | The widget projection and App Group |
| [Configurable Widgets](23-CONFIGURABLE-WIDGETS.md) | `AppIntentConfiguration` and display modes |
| [Interactive Widgets](24-INTERACTIVE-WIDGETS.md) | Widget buttons and the command seam |
| [App Intents](21-APP-INTENTS.md) | Siri, Shortcuts and the intent layer |
| [Live Activities](25-LIVE-ACTIVITIES.md) | The platform-neutral live-session core |
| [iOS Companion and Live Activities](27-IOS-COMPANION-LIVE-ACTIVITIES.md) | The iOS app and its ActivityKit implementation |
| [iOS Widgets and Notifications](29-IOS-WIDGETS-NOTIFICATIONS.md) | iOS Home Screen widgets and the shared notification stack |
| [Lock Screen and StandBy](30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md) | Accessory widget families |
| [Control Center Controls](31-CONTROL-CENTER-CONTROLS.md) | The adaptive, start and stop controls |
| [Configurable Control Center](32-CONFIGURABLE-CONTROL-CENTER.md) | The quick-start control and its picker |

### Data, sync and release

| Document | Subject |
|---|---|
| [iCloud and CloudKit](22-ICLOUD-CLOUDKIT.md) | The sync transport and why it is disabled |
| [CloudKit Device Validation](28-CLOUDKIT-DEVICE-VALIDATION.md) | The capability seam and cross-device validation |
| [Production Readiness](26-PRODUCTION-READINESS.md) | The source-boundary audit as a release gate |
| [Stability and Reliability](34-M26-STABILITY-AND-RELIABILITY.md) | The freeze investigation and the concurrency rules that came out of it |
| [Menu Bar UX, Quick Start and Icons](37-M28-MENU-BAR-QUICK-START-ICONS.md) | The popover hierarchy, pinning, and the icon catalog |
| [App Store material](appstore/) | Marketing copy and privacy nutrition labels |

## Milestones, in order

| Milestone | Document |
|---|---|
| Core UI | [12-CORE-UI.md](12-CORE-UI.md) |
| Task Templates | [13-TASK-TEMPLATES.md](13-TASK-TEMPLATES.md) |
| Session Planner | [14-SESSION-PLANNER.md](14-SESSION-PLANNER.md) |
| Calendar Integration | [15-CALENDAR-INTEGRATION.md](15-CALENDAR-INTEGRATION.md) |
| Notifications | [16-NOTIFICATIONS.md](16-NOTIFICATIONS.md) |
| Menu Bar | [17-MENU-BAR.md](17-MENU-BAR.md) |
| Liquid Glass Design | [18-LIQUID-GLASS-DESIGN.md](18-LIQUID-GLASS-DESIGN.md) |
| Statistics | [19-STATISTICS.md](19-STATISTICS.md) |
| WidgetKit | [20-WIDGETKIT.md](20-WIDGETKIT.md) |
| App Intents | [21-APP-INTENTS.md](21-APP-INTENTS.md) |
| iCloud and CloudKit | [22-ICLOUD-CLOUDKIT.md](22-ICLOUD-CLOUDKIT.md) |
| Configurable Widgets | [23-CONFIGURABLE-WIDGETS.md](23-CONFIGURABLE-WIDGETS.md) |
| Interactive Widgets | [24-INTERACTIVE-WIDGETS.md](24-INTERACTIVE-WIDGETS.md) |
| Live Activities feasibility | [25-LIVE-ACTIVITIES.md](25-LIVE-ACTIVITIES.md) |
| Production Readiness | [26-PRODUCTION-READINESS.md](26-PRODUCTION-READINESS.md) |
| iOS Companion and Live Activities | [27-IOS-COMPANION-LIVE-ACTIVITIES.md](27-IOS-COMPANION-LIVE-ACTIVITIES.md) |
| CloudKit Device Validation | [28-CLOUDKIT-DEVICE-VALIDATION.md](28-CLOUDKIT-DEVICE-VALIDATION.md) |
| iOS Widgets and Notifications | [29-IOS-WIDGETS-NOTIFICATIONS.md](29-IOS-WIDGETS-NOTIFICATIONS.md) |
| Lock Screen and StandBy | [30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md](30-IOS-LOCKSCREEN-STANDBY-WIDGETS.md) |
| Control Center Controls | [31-CONTROL-CENTER-CONTROLS.md](31-CONTROL-CENTER-CONTROLS.md) |
| Configurable Control Center | [32-CONFIGURABLE-CONTROL-CENTER.md](32-CONFIGURABLE-CONTROL-CENTER.md) |
| Product Identity and UX Validation | [33-M24-ON-DEVICE-UX-VALIDATION.md](33-M24-ON-DEVICE-UX-VALIDATION.md) |
| Stability and Reliability | [34-M26-STABILITY-AND-RELIABILITY.md](34-M26-STABILITY-AND-RELIABILITY.md) |
| User Guide (cross-platform) | [35-USER-GUIDE.md](35-USER-GUIDE.md) |
| macOS User Guide | [35-MACOS-USER-GUIDE.md](35-MACOS-USER-GUIDE.md) |
| Developer Overview | [36-DEVELOPER-OVERVIEW.md](36-DEVELOPER-OVERVIEW.md) |
| Menu Bar UX, Quick Start and Icons | [37-M28-MENU-BAR-QUICK-START-ICONS.md](37-M28-MENU-BAR-QUICK-START-ICONS.md) |
| macOS Interface Redesign | [38-M29-MACOS-UI-REDESIGN.md](38-M29-MACOS-UI-REDESIGN.md) |
| Design System Consolidation | [39-M30-DESIGN-SYSTEM-CONSOLIDATION.md](39-M30-DESIGN-SYSTEM-CONSOLIDATION.md) |
| Data Safety and Recovery | [40-M31-DATA-SAFETY-AND-RECOVERY.md](40-M31-DATA-SAFETY-AND-RECOVERY.md) |
| Open at Login and Window Management | [41-M32-LOGIN-ITEM-AND-WINDOW-MANAGEMENT.md](41-M32-LOGIN-ITEM-AND-WINDOW-MANAGEMENT.md) |

Historical milestone documents describe the state of the project at the time they were written. They
are kept as written rather than rewritten to match the present.

## Conventions

**"Time Frame"** is the product name in all user-facing text. `time_frame` is an internal target and
module identifier and appears only in technical contexts.

Technical names — `TimerEngine`, `SessionCoordinator`, `WidgetProjection`, `AppIntentSessionActions` —
are used when discussing architecture, not in user documentation.
