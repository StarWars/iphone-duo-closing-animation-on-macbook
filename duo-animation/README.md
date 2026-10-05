# Duo Lid source project

For app installation, usage, permissions, privacy, and credits, start with the [repository README](../README.md). The installable prototype is in [downloads](../downloads/), and visual/test evidence is in [qa/REPORT.md](qa/REPORT.md).

## Build in Xcode

Requirements: macOS 14+, a Metal-capable Mac, and Xcode with Swift 6.2 or later and a macOS SDK. Open **DuoLid.xcodeproj**, choose **DuoLid → My Mac**, and Run. No third-party runtime packages are needed.

The included project is generated from `project.yml`. If changing that specification, run `xcodegen generate` from this folder; otherwise XcodeGen is unnecessary. `Sources/Effect/Glass.metal.txt` is shader source compiled once by the system Metal driver. The optional standalone Xcode Metal Toolchain is not required.

## Command-line build and test

Run these from this `duo-animation/` folder:

```sh
xcodebuild -project DuoLid.xcodeproj -scheme DuoLid -configuration Release -derivedDataPath build build 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO
xcodebuild -project DuoLid.xcodeproj -scheme DuoLid -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build test ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
'build/Build/Products/Release/DuoLid.app/Contents/MacOS/DuoLid' --verify "$PWD/build/qa"
```

For an Intel test host, change both the destination architecture and `ARCHS` to `x86_64`. The verification process needs normal GPU access. It uses generated sample/calibration images, opens neither the sensor nor screen capture, and does not request system privacy permissions. It saves PNGs, a 120-frame reversible sample, a 240-frame fast sequence, and a 1080-frame slow sequence with one-degree changes every two seconds. Both sensor simulations present at 60 Hz and include CSV traces, holds and reopening. The slow export uses the same settled-angle draw pausing as the app.

The universal Release build uses ad-hoc signing, hardened runtime, and no additional entitlements. It is not notarized or App Sandbox-enabled. See the root README for the reasoning and limitations; do not add Accessibility or administrator access as a hardware workaround.

To rebuild the downloadable ZIP from a fresh staging directory:

```sh
bash scripts/package.sh
```

The script verifies signing, both architectures, the bundle ID and bundled legal files, then updates `downloads/Duo-Lid-Prototype.zip` and `SHA256SUMS`. It packages INSTALL, ATTRIBUTIONS, LICENSE and NOTICE alongside the app. It does not notarize or install the app. Temporary staging stays under the ignored build folder.

## Components

Release 0.7.1 adds `Sources/App/AppBrand.swift` for the directly loaded bundle icon, headline, LinkedIn image/link and native About panel. Both preview source-selection actions request a redraw after replacing textures, including while the angle is unchanged and rendering is paused.

Release 0.7.2 makes all image/session-reset preview updates invalidate paused drawing and renders a blank background when textures have been cleared. GPU verification covers the cleared-texture path. The current generated evidence is in [qa/current](qa/current/); [qa/REPORT.md](qa/REPORT.md) records the fresh build, 31 XCTest tests and GPU checks.

The app menu exposes **About Duo Lid…**; the header and About panel link to Michal Stawarz's LinkedIn profile. `project.yml` also packages the repository's `NOTICE` and Apache-2.0 `LICENSE` as app resources. Both accompany the app in the prototype ZIP.

Release 0.7.0 pairs the moving-lid preview with physical rotation compensation. A fixed-eye ray intersection moves the preview panel around stationary desktop coordinates; the overlay applies its inverse, projecting each physical panel pixel onto the same reference plane. Both use actual angular travel from the trigger, while blur/fade retain the normalized trigger-to-10° interval.

App artwork is in [App/Artwork](App/Artwork/README.md). The macOS icon set is in `App/Assets.xcassets/AppIcon.appiconset`; `project.yml` selects it as the primary app icon. The asset catalog compiles into `AppIcon.icns` and `Assets.car`; the preview and About panel load the bundled icon directly.

| Path | Responsibility |
| --- | --- |
| `Sources/App/` | AppKit controls, menu bar, nonactivating overlay, pause routes and lifecycle safety |
| `Sources/Lid/` | Actor-confined read-only IOKit sensor access, validated reports, motion state and filtering |
| `Sources/Capture/` | Explicit permission gating and memory-only ScreenCaptureKit snapshots |
| `Sources/Effect/` | Original sample desktop, Metal perspective plane and MPS variable-blur ladder |
| `Sources/Verification/` | Sample-only GPU/image checks and QA exports |
| `Tests/` | Gesture, damping, report-decoding, hold/reversal, cadence and background-state checks |

The app runs as an accessory app (`LSUIElement`) with a menu-bar status item and no Dock icon. The preview opens for initial setup; subsequent launches stay hidden, and closing/minimizing the preview stops its demo without disabling the desktop effect. `BackgroundState` separates the locally persisted enabled choice from temporary suspension. Independent sleep, display sleep, session and lock flags must all clear before resuming; a wake cannot clear a lock. Automatic rearming requires an active console session, an open valid lid (raw angle at or above the selected trigger, at most 180°), a fresh reading, previously granted Screen Recording access, a registered pause shortcut and the built-in display. Sensor failures retry with a five-second backoff. Near closure and the 30-second gesture limit wait for reopening; manual Pause, overlay click, sample/desktop-preview actions and manual sensor disconnect clear the enabled choice. Capture generation checks remain in force.

The menu's optional **Launch at login** uses `SMAppService.mainApp` from the Apple ServiceManagement framework. Registration/unregistration happens only on that explicit menu action and reports the system's real status, including required approval; registration is limited to installed copies in system/user Applications. No helper, LaunchAgent file, daemon or extra privacy permission is added. Quit keeps the enabled preference for the next launch; Pause turns it off until enabled again. Trigger angle, Depth, Softness, Shade and the first-run setup flag also persist in UserDefaults; images and angle history do not. XCTest hosts skip normal app startup so tests cannot restore the user's background capture preference.

`LidTrigger` validates a whole-degree 30–140° setting, defaulting to 90°. The preview provides number entry, one-degree stepping and Reset. The gesture reference, filter's open seed, automatic arming gate, capture approach band and status labels all use that setting. Reconfiguration invalidates pending captures and clears the old overlay while preserving the enabled choice; a new gesture waits for reopening to the new trigger. Geometry uses actual angular travel from the reference, scaled by Depth. Only blur/fade normalize `(reference - angle) * 80 / (reference - 10)` to reach black near physical 10°. The sample demo uses the configured trigger too. Tests cover custom thresholds, holds/reversals, near closure, changing the reference and background rearming; GPU checks cover identity at/above the trigger, equal compensation for equal angular travel, and final black across the trigger range.

The preview and desktop shader share eye coordinates `(0, 1.35, 1.8)` in reference-screen-height units and complementary ray/plane mappings. The preview moves the physical frame around fixed screenshot coordinates. The overlay stretches its panel pixels to compensate real lid motion; the apparent image stays on the reference plane, with natural occlusion rather than fitting the whole screenshot into a shrinking shape. At the trigger the transform is identity, and the hinge remains fixed. Blur/shade use physical panel coordinates. GPU verification independently projects desktop landmarks onto the physical lid and checks visible samples at four angles, alongside stationary preview and custom-trigger checks. Zero Depth disables compensation.

Desktop mode prewarms a single snapshot within the ten-degree approach band above the trigger, not continuously. The reference and snapshot stay fixed through partial reversals. Raw sensor readings gate strict below-trigger activation and immediate removal at the trigger. Sensor ingestion and frame sampling are separate: a new target cannot consume time spent idle on the previous one. The analytically integrated critically damped filter adapts its response to distinct report changes. One-degree steps use 30% of the observed seconds per degree, clamped to 65–550 ms; the first isolated step uses 400 ms. Larger steps use 65 ms immediately, and rapid one-degree changes also return to that response. Reversals discard opposing momentum without integrating further in the old direction. No angle is extrapolated beyond a measurement. A slow held target can take about 2.5 seconds to settle; settled holds stop drawing. Open readings keep a fresh trigger-angle seed while views are idle. Capture generations and cancellation checks discard delayed frames after pause or session changes. Sensor handles stay on their actor; UI and rendering state stay on the main actor.

Rendering uses a seven-level, progressively filtered/downsampled blur pyramid with identical normalized padded coordinates. The unblurred level remains full-resolution; successive levels are half-sized and use small MPS Gaussian kernels. Padding is cleared on the GPU, not with a large CPU zero buffer. Live views use MetalKit's preferred 60 Hz loop, cap drawable width at 1600, suspend the preview behind an active overlay, and pause drawing after a hold settles. Polling uses clock deadlines so HID read time does not accumulate cadence drift. There are no third-party runtime packages.

See the [laptop-only acceptance checklist](qa/REPORT.md#laptop-only-acceptance-checklist) before treating the hardware integration as validated. The only privacy permission requested by the app is optional Screen Recording for real-desktop pixels.
