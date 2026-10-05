# Changelog

## 0.7.2 — publication cleanup

- Update the lid-position slider and degree value on every sample-fold frame.
- Explicitly redraw paused manual previews so the fold slider works after disconnecting the sensor and disabling the desktop effect.
- Refresh paused previews on image/session resets, including blank rendering after captured textures are cleared.
- Bundle Apache-2.0 LICENSE, creator NOTICE and end-user terms/risk notice accessible from the tray menu; preserve mandatory legal rights.
- Replace historical QA assets with current generated samples and a concise validation report; remove private recording names and workstation paths from current documentation.
- Revalidate the universal build, all 32 XCTest tests, sample-only GPU checks and package.

## 0.7.1 — branding and preview refresh

- Load the custom app icon directly in the preview header and About popup.
- Add About Duo Lid to the menu bar and a clickable LinkedIn button beside the headline.
- Refresh desktop/sample image selections without changing the lid position.

## 0.7.0 — stationary desktop compensation

- Use complementary preview/overlay ray mappings so the physical lid moves around a stationary reference plane.
- Base geometry on actual lid travel; keep blur/fade normalized to the selected trigger.

## 0.6 — configurable trigger and artwork

- Add a saved 30–140° whole-degree trigger, default 90°, with stepping and reset.
- Add the MacBook app icon, include normal Duo Lid windows in captures and restore the moving-lid preview.

## 0.5 — menu-bar operation

- Keep the app available with optional launch at login and saved preferences.
- Suspend on sleep/lock/session changes; rearm only with existing permission and a fresh open-lid reading. Manual Pause remains off.

## 0.4.1 — slow-motion smoothing

- Blend sparse whole-degree readings over fractional frames without prediction.
- Separate sensor ingestion from frame sampling and avoid snapping after paused drawing.

## 0.3–0.4 — visual exploration

- Explore fixed-content occlusion and complete-content perspective fitting. These historical projection models were superseded by 0.7.0.

## 0.2 — initial handoff

- Use a raw below-90° trigger, progressive blur toward the hinge, snapshot prewarming and a downsampled Metal/MPS blur pyramid.
- Add generated calibration samples, motion tests and GPU verification.
