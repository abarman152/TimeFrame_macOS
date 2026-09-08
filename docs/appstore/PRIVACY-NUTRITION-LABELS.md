# Time Frame — App Store Privacy ("Nutrition Label") Answers

These are the answers to enter in **App Store Connect → App Privacy**, and they
match the on-device `PrivacyInfo.xcprivacy` manifests exactly. Keep the two in
sync: if one changes, change the other.

> **Why "no data collected":** Apple defines *collection* as transmitting data
> off the device or giving a third party access to it. Time Frame stores
> everything locally (SwiftData store + UserDefaults) and transmits nothing.
> iCloud/CloudKit mirroring exists in the codebase but is **disabled in the
> shipping build** (personal Apple team; `CloudKitCapability.entitledInThisBuild
> == false`). There is no analytics/advertising SDK and no network client.

## Data Collection

**"Do you or your third-party partners collect data from this app?"**

→ **No, we do not collect data from this app.**

That single answer produces the "Data Not Collected" label. No data-type,
purpose, linkage, or tracking questions follow.

## Tracking

- **Does this app track users?** → **No.**
- `NSPrivacyTracking` in the manifest is `false`; `NSPrivacyTrackingDomains` is
  empty. There is no `ATTrackingManager` / IDFA usage anywhere in the codebase.

## Required-Reason API Declarations (already in the manifests)

Not shown to users, but reviewed by App Review and must be present:

| API category | Reason code | Where |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` (app-only) + `1C8F.1` (App Group) | app targets (macOS + iOS) |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `1C8F.1` (App Group) | widget/extension targets |

No other required-reason categories apply — verified by source scan: no
`systemUptime`/`mach_absolute_time` in shipping code (the injected clock is
`Date`-based; `ContinuousClock` appears only in tests), no file-timestamp APIs,
no disk-space APIs.

## Privacy Policy

App Store requires a reachable **Privacy Policy URL** even when no data is
collected. A minimal, accurate policy suffices. Draft text:

```
Time Frame does not collect, transmit, or share any personal data. All of your
timers, sessions, statistics, and preferences are stored only on your device
(and, if you enable it in a future update, in your own private iCloud account —
never accessible to us). Time Frame contains no analytics, no advertising, and
no third-party tracking. We have no servers and receive no information about how
you use the app.

Contact: <your support email>
Last updated: <date>
```

## When CloudKit sync is enabled later (paid team)

If/when the paid-team CloudKit pass ships and sync is turned on, the privacy
posture changes and **all four** of these must be revisited together:

1. Update each `PrivacyInfo.xcprivacy` if any new required-reason API is added.
2. In App Store Connect, data stored in the user's **private** CloudKit database
   generally still qualifies as *not collected by the developer* (you have no
   access to it), but re-confirm against Apple's current guidance for the exact
   data types (e.g. "Productivity" content, "Identifiers").
3. Update the Privacy Policy to describe iCloud storage.
4. Update marketing copy only once sync is actually verified on two devices.
