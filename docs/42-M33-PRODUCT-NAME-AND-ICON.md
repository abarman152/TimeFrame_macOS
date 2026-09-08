# Milestone 33 — Product Name and Icon Identity

An identity milestone. The user-facing product name is **Time Frame** everywhere the system
shows it; every internal identifier is unchanged.

No feature was added, no architecture moved, and the SwiftData schema stays **V7**.

## The defect

Milestone 24 set `INFOPLIST_KEY_CFBundleDisplayName = "Time Frame"` and added tests that
asserted it. Those tests passed. The application menu still read:

```
  Apple    time_frame    Edit    View    Window    Help
```

The bold title immediately right of the Apple menu is arguably the most-seen element of a Mac
app's identity, and it comes from **`CFBundleName`** — not `CFBundleDisplayName`. Nothing set
it, so it fell back to the generated default of `PRODUCT_NAME`, which was `$(TARGET_NAME)`:
`time_frame`.

What made this survive a milestone specifically about naming is that the menu *items* were
already right:

```
About Time Frame    Hide Time Frame    Quit Time Frame
```

Those use the display name. So every string a reviewer or a test would naturally reach for was
correct. The one that was wrong was the one nobody had named.

### Two fixes that do not work

Recorded so they are not retried:

| Attempt | Result |
| --- | --- |
| `INFOPLIST_KEY_CFBundleName = "Time Frame"` | **Not honoured.** Built `CFBundleName` unchanged. |
| `CFBundleName` written into `time_frame-Info.plist` | **No-op.** With `GENERATE_INFOPLIST_FILE = YES` the generated value wins over the file. |

Both were verified against the built product, not assumed.

## What changed

### macOS

```
PRODUCT_NAME        = "Time Frame"     (was "$(TARGET_NAME)")
PRODUCT_MODULE_NAME = time_frame       (new — pins the Swift module)
TEST_HOST           = "$(BUILT_PRODUCTS_DIR)/Time Frame.app/Contents/MacOS/Time Frame"
```

`PRODUCT_NAME` is the only lever that moves `CFBundleName`. It also renames the bundle and the
executable, so the Dock, Finder, Force Quit and Activity Monitor all show the product name.

The module pin is what makes this safe. The Swift module name defaults to `PRODUCT_NAME`;
without pinning it, the module becomes `Time Frame` and every `@testable import time_frame` in
the test suite stops compiling. `TEST_HOST` follows the product name and was updated in both
configurations.

### iOS

The iOS target generates no `Info.plist`, so the keys are stated in the file:

```xml
<key>CFBundleDisplayName</key> <string>Time Frame</string>
<key>CFBundleName</key>        <string>Time Frame</string>   <!-- was $(PRODUCT_NAME) -->
<key>CFBundleIconName</key>    <string>AppIcon</string>       <!-- new -->
```

`CFBundleIconName` matters beyond tidiness: because `GENERATE_INFOPLIST_FILE = NO`, actool's
injected keys are not merged, so the icon compiled fine into `Assets.car` while nothing
declared it. That passes a normal build and fails App Store validation.

## Verified against the built products, not the source

| Check | macOS | iOS |
| --- | --- | --- |
| Bundle on disk | `Time Frame.app` | `TimeFrameiOS.app` (internal; not user-visible) |
| `CFBundleDisplayName` | Time Frame | Time Frame |
| `CFBundleName` | Time Frame | Time Frame |
| `CFBundleExecutable` | Time Frame | TimeFrameiOS |
| `CFBundleIdentifier` | `abirbarman.com.time-frame` (unchanged) | `abirbarman.com.time-frame` (unchanged) |
| `CFBundleIconName` | AppIcon | AppIcon |
| `AppIcon` in `Assets.car` | present | present |
| Icon files emitted | `AppIcon.icns` | `AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png` |

The macOS menu bar was then read from the running app through the accessibility API:

```
Apple, Time Frame, Edit, View, Window, Help
About Time Frame / Hide Time Frame / Quit Time Frame
```

## The icon — reshaped for macOS

Milestone 24 used **one identical full-bleed file on both platforms**. That is correct for iOS
and wrong for macOS, and it is why the Mac icon rendered as a hard black square, visibly larger
and squarer than its neighbours.

macOS does **not** mask app icons. The artwork must carry its own rounded shape with
transparent padding; whatever the PNG contains is what is drawn. iOS is the opposite — full
bleed, no alpha, system-masked. The same file cannot satisfy both.

The macOS artwork was therefore re-shaped to Apple's macOS icon grid. The mark, its colours and
its proportions are unchanged — only the frame around it:

| | Value |
| --- | --- |
| Canvas | 1024 × 1024 |
| Rounded body | 1024 × 1024 — fills the tile |
| Transparent margin | none |
| Corner radius | 230.4 px (0.225 × side, Apple's continuous-corner proportion) |
| Alpha | required, for the rounded corners (was `hasAlpha: no`) |

Apple's macOS grid nominally uses an 824 body inside the 1024 canvas — an ~80% mark that
matches Finder, Safari and Mail. That was tried first and rejected on sight: beside
document-shaped icons like TextEdit it reads noticeably small. The body therefore fills the
canvas, keeping the same corner proportion so it is still a rounded macOS icon rather than the
hard square it started as.

The body size is a single argument to the reshape tool, so this is one number to revisit:
`reshape source.png out.png 824` restores Apple's grid, and anything between works.

The reshape was done with a small CoreGraphics tool (`reshape.swift`) that clips the source
square into the rounded body on a transparent canvas; the ten macOS sizes are then downscaled
from that one master, so every slot keeps identical proportions. The previous icon set was
backed up before replacement.

The **iOS** master is untouched: it was already correct at full bleed.

### Verified after compilation

`AppIcon.icns` extracted from the built app: every slot reports `alpha=yes`, and the 256 px
rendition shows the rounded body with transparent corners. `Assets.car` carries 11 `AppIcon`
renditions and `CFBundleIconName` is `AppIcon`.

### Unchanged from Milestone 24 and re-verified, not regenerated:

- **macOS** — `time_frame/Assets.xcassets/AppIcon.appiconset/`, the full raster ladder from the
  1024 master: 16, 32, 128, 256, 512 at 1x and 2x. Every file's dimensions and alpha were checked.
- **iOS** — `TimeFrameiOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, a single
  1024 × 1024 universal slot.
- **One artwork, both appearances.** Neither `Contents.json` contains an `appearances` key, so
  there is no Light/Dark split and no tinted variant. Exactly one `AppIcon.appiconset` exists
  per platform catalog.

## Internal identifiers deliberately unchanged

| | Value |
| --- | --- |
| Bundle identifier | `abirbarman.com.time-frame` |
| App Group | `group.abirbarman.com.time-frame` |
| URL scheme | `timeframe://` |
| Swift module | `time_frame` |
| Xcode project | `time_frame.xcodeproj` |
| Target names | `time_frame`, `TimeFrameiOS`, `TimeFrameWidgets`, … |
| Source directories | `time_frame/`, `Core/`, `Shared/`, … |
| SwiftData schema | V7 |

Changing any of these would break signing, the App Group, deep links, widgets, App Intents or
persistence, and none of them is user-facing.

## Tests

`ProductionReadinessM33Tests` — 8 tests in 2 suites, asserting the keys M24's suite did not:

| Suite | Asserts |
| --- | --- |
| `M33ProductNameTests` | `PRODUCT_NAME` is "Time Frame"; the ineffective `INFOPLIST_KEY_CFBundleName` is not left as misleading config; the module is pinned; `TEST_HOST` follows the product with no stale reference; iOS states both name keys and neither falls back to `$(PRODUCT_NAME)`; iOS declares `CFBundleIconName` |
| `M33IdentityRegressionTests` | Bundle identifier, App Group and URL scheme unmoved; the `time_frame/` directory and `.xcodeproj` not renamed |

Milestone 24's identity and icon suites are unchanged and still pass — they were incomplete,
not wrong.

## Verification

| Check | Result |
| --- | --- |
| macOS Debug build | succeeded, 0 compiler warnings |
| macOS Release build (signed) | succeeded, 0 compiler warnings |
| macOS test suite | 1071 tests in 218 suites passed |
| iOS Debug build | succeeded, 0 compiler warnings |
| iOS Release build | succeeded, 0 compiler warnings |
| iPhone 17 Pro test suite | 105 tests passed |
| iPad Pro 13-inch (M5) test suite | 105 tests passed |
| Menu bar title | read from the running app: "Time Frame" |

## Known limitations

- **The built bundle name changed**, so a previously installed `time_frame.app` is not replaced
  by a new build. Both can coexist in `/Applications`; the old one should be removed by hand
  once, after which only `Time Frame.app` remains.
- **The iOS bundle is still `TimeFrameiOS.app`.** Its `PRODUCT_NAME` was left alone because the
  bundle filename is not user-visible on iOS — the Home Screen uses `CFBundleDisplayName`,
  which is correct. Renaming it would require moving `TEST_HOST` for the iOS test target for no
  user-facing gain.
- **The iOS name and icon were not seen on a Home Screen.** The iPhone and iPad test suites do
  run on simulators, but they are unit tests — they never launch the app's springboard
  presentation. The iOS `CFBundleDisplayName`, `CFBundleName` and `CFBundleIconName` were read
  from the built bundle's `Info.plist`, and `AppIcon` was confirmed present in the compiled
  `Assets.car`; neither the icon nor the name was visually checked on a device or simulator
  Home Screen.
- **No screenshots were captured.** The menu-bar verification was done through the accessibility
  API, which returns text, not images.
