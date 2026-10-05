# Publication QA — 5 October 2026

## Current build

**Duo Lid 0.7.2, build 13** · `pl.appbeat.DuoLid` · macOS 14 minimum.
Verified on Apple M1 Pro, macOS 26.6.2, Xcode 27.0.
The Release contains arm64 and x86_64; execution was tested on arm64.

The source is suitable to share as an **experimental open-source prototype**. This is not a production, notarized or App Store release. The remaining hands-on checks below are not covered by the automated results.

## Automated checks

| Check | Result |
| --- | --- |
| Universal Release, Swift 6 strict concurrency | Passed |
| XCTest | 32 passed: 17 motion/report/filter, 8 background-policy, 6 trigger, 1 paused-preview redraw test |
| Cleared desktop textures | Every pixel replaced with the blank background |
| Stationary desktop compensation | 25/20/15/10 visible landmarks at 89°/75°/60°/44°; maximum channel error 0 |
| Stationary preview and moving lid frame | Passed at all four angles |
| Hinge, open state and partial reversal | Passed; hinge mean channel error 0.000; identical output on reversal |
| Custom triggers 30°, 75°, 110°, 140° | Identity at/above trigger; equal actual travel gives equal compensation; black by 10° |
| Blur propagation | Far-side contrast 12/255 versus hinge 255/255 at moderate closure; bottom contrast 1/255 at 20° |
| Very slow integer readings | One degree per two seconds: maximum frame step 0.03062°; fractional movement in 119/120 frames |
| Repository content | Targeted credential-pattern scan found no matches; PNG metadata contained no GPS tags |
| Release resources | App icon, shader, LICENSE and NOTICE included |
| Extracted ZIP | Universal slices, required identity/version, strict signature and checksum verified |

The final package also includes byte-identical LICENSE, NOTICE and EULA.md copies inside the app and archive. The tray-menu action for opening the terms compiled in the final universal build; actual menu delivery remains a hands-on check. The end-user terms are a draft for legal review and do not guarantee protection against claims.

The cleanup fixed a paused-preview edge case: changing/resetting the image now invalidates the view even when the angle is unchanged. If sample restoration fails after a session reset, cleared textures render a blank drawable rather than retaining the old captured image. The GPU check exercises that blank rendering path.

A targeted scan is not a comprehensive security audit. No live desktop capture, sensor movement, login registration or new privacy permission was used in this run.

The scan also covered 164 unique blobs in reachable Git history, with no targeted credential signatures. Historical commits still contain old recording filenames/workstation paths in an earlier QA report; those references have been removed from the current documentation. No personal recordings were found in Git history. History was not rewritten during this cleanup.

## Current generated samples

All samples below use the app's locally drawn desktop and calibration patterns. Neither videos shared by the creator nor real desktop captures are published.

- [Open preview](current/preview-90.png), [75°](current/preview-75.png), [60°](current/preview-60.png), [44°](current/preview-44.png), [10°](current/preview-10.png).
- [Physical display pixels at 60°](current/screen-60.png): intentionally distorted to compensate the real lid's rotation.
- [Unblurred compensation grid](current/plane-calibration-60.png) and [blur reaching the bottom](current/blur-bottom-calibration.png).
- [Fast sample fold](current/sample-fold.mp4): 4 seconds, 60 Hz presentation, simulated 12 Hz whole-degree reports, hold and reopening.
- [Slow sample fold](current/sample-slow-fold.mp4): 18 seconds, 60 Hz, one-degree changes every two seconds, holds and partial reopening.
- [Fast trace](current/simulated-sensor-angles.csv) and [slow trace](current/simulated-slow-sensor-angles.csv): generated values, not hardware telemetry.

Videos contain no audio. Historical renders were removed from the current checkout and archived locally under the ignored build folder; previous revisions remain in Git history. See [CHANGELOG.md](../../CHANGELOG.md) for the development summary.

## Laptop-only acceptance checklist

1. Quit old copies, install 0.7.2 in Applications and open Settings and preview from the menu bar. Confirm the custom icon, headline, About credit/version and LinkedIn link. Switch desktop/sample at a held slider position; the new image should appear when ready without touching the slider.
2. Physically verify `⌃⌥⌘D` both in Duo Lid and with another app focused. Connect the sensor and enable above the selected trigger. Check strictly below-trigger activation and immediate raw-trigger removal, holds, partial reversals and very slow closure.
3. At Depth 1 and a consistent viewing position, compare held-angle desktop landmarks with the stationary preview. Parts of the image should become naturally occluded. Check blur toward the hinge and disappearance during deep closure. Whole-degree input, filter delay and the approximate eye prevent a guarantee of perfect real-world stationarity.
4. Try lower/higher reachable triggers, a slow approach through the ten-degree prewarm band and fast closure that skips it. Open Settings before prewarming if it should appear in the snapshot. Verify inclusion of normal Duo Lid windows and exclusion of the effect overlay.
5. Change the trigger during enabled operation and pending capture. The old overlay/capture must clear; reopening to the selected trigger must allow a new gesture. Manual Pause must remain off.
6. Check permission denial/revocation, pending capture followed by Pause, display changes, fullscreen/Spaces, sleep/wake, lock/unlock and session switching. No old screenshot should remain after suspension. The 30-second cap and 8° near-closure stop must clear the overlay.
7. Register Launch at login explicitly and check macOS approval/status and an actual login launch. Automatic restoration requires an active session, existing permission and a fresh open-lid reading. Manual Pause must survive wake/relaunch.
8. Inspect energy use with the preview closed and the angle held. Test an Intel host and other MacBook models before extending compatibility claims.

## Distribution limits

The downloadable app is ad-hoc signed with hardened runtime. It is not Developer ID-signed, notarized or App Sandbox-enabled. Gatekeeper may block downloaded copies; source builds are available. A production download needs signing/notarization work and the hands-on coverage above. App Store distribution has not been validated.

## Reproduce

Use the [developer README](../README.md) for build, XCTest and sample-only `--verify` commands.
Local audit evidence is excluded from Git: `build/release-public-audit.log`, `build/tests-public-audit.log`, `build/verification-public-audit.log`, `build/repository-audit-inventory.json`, `build/qa-public-audit/` and `build/package-check-public/`.

Manual preview regression: after starting and stopping continuous rendering, explicit paused redraws present each requested angle immediately without restarting the render loop. All 32 XCTest tests passed in `build/tests-manual-preview.log`.
