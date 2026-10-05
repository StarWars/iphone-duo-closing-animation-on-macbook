# Install Duo Lid 0.7.2

**Your desktop stays. Your lid moves.** This build includes the custom app icon, **About Duo Lid…** in the menu bar, and a LinkedIn button beside the headline. About credits Michal Stawarz, 2026, with a LinkedIn feedback link; the app's copyright and NOTICE credit appbeat.pl. Image selections and session resets refresh the paused preview immediately, and cleared desktop textures render a blank background.

The desktop overlay now compensates physical lid rotation using the same stationary reference plane as the window preview. Parts of the desktop become occluded during closure instead of being resized to fit the panel.

Desktop snapshots now include visible Duo Lid settings/preview windows. Only the effect overlay is excluded to prevent feedback. Open Settings and preview before entering the capture approach range to include it in the prewarmed snapshot.

This experimental macOS 14+ prototype supports Apple Silicon and Intel. Physical lid tracking requires a MacBook with a readable supported sensor. Manual preview works on other Metal-capable Macs.

App bundle identifier: `pl.appbeat.DuoLid`. Replace any earlier copy with the app from this archive; changing the repository does not update an already-installed app.

This build includes the new MacBook app icon with the closing effect on its screen, including all macOS icon sizes and the 1024-pixel master.

1. Extract the archive and move **Duo Lid.app** to **Applications**.
2. Open it and try **Play a fold** or the **Lid position** slider. First launch starts with the desktop effect off and asks for no privacy permissions.
3. On a MacBook, click **Connect lid sensor**. Check the live preview and physically test **Control–Option–Command–D (`⌃⌥⌘D`)** before enabling the desktop effect.
4. Only if that works, select **Enable desktop lid effect**. Allow **Screen Recording** in System Settings if you want the real-desktop effect. Relaunch if macOS requires it, then enable again if it is off.
5. Close the preview window. Duo Lid stays in the menu bar without a Dock icon. Click its MacBook icon for **Settings and preview…**, **Enable/Disable desktop effect**, **Pause desktop effect**, or **Quit Duo Lid**.
6. Select **Launch at login** in that menu to start automatically when you sign in. If approval is required, choose **Approve login item in System Settings…**. Deselect Launch at login to stop automatic launches.

The app remembers your enabled choice, trigger angle and appearance settings. Later launches run quietly in the menu bar. If enabled, it reconnects after launch, wake, unlock or a display/session change once the session is active, permission remains granted and a fresh sensor reading reaches your trigger angle. Automatic restoration does not request new privacy permission or prevent normal sleep. Pause stays off until you enable the effect again, including across wake and relaunch.

In **Settings and preview…**, set **Trigger angle** from **30° to 140°** in whole degrees. Type a value and press Return or leave the field, use the arrows for one-degree steps, or click **Reset** for the default 90°. Choose an angle your MacBook can reach. Changing it clears the old gesture and waits for reopening to the new angle before rearming.

Open to at least your selected trigger before enabling. The overlay starts strictly below that raw sensor reading and disappears when reopened to it. The snapshot is projected onto a stationary reference plane, with the bottom edge anchored at the hinge. The real lid supplies the movement; the overlay compensates it, matching the preview's geometry. Your viewing position affects the illusion. The effect progresses across the trigger-to-closure range and fades to black by approximately 10°. A single snapshot is prewarmed in the ten-degree band above the trigger (90–100° by default); very fast closing can still wait briefly for capture. The sensor reports whole degrees. Adaptive damping gives slow one-degree changes longer transitions while keeping faster motion responsive. After very slow motion stops, the visual transition can take about 2.5 seconds to settle; reopening to the raw trigger still removes the overlay immediately.

Click anywhere on an active overlay to pause without activating an app underneath. A continuous gesture automatically stops after 30 seconds and waits for reopening to the trigger before rearming. Quit releases the app's resources; it preserves the enabled choice for the next launch. To uninstall, turn off Launch at login, quit and move the app to the Trash.

The app does not collect personal information, analytics, or telemetry and does not make network requests. Desktop snapshots and lid readings are processed locally for rendering; screenshots are not saved or uploaded. No Accessibility, Input Monitoring, microphone, camera, Full Disk Access, or administrator access is requested.

This is an **ad-hoc-signed, hardened-runtime prototype**, not a Developer ID-signed or notarized release. Gatekeeper may block a downloaded copy. Prefer a local source build if you do not want to approve an unnotarized binary. If you trust the source and deliberately choose to open it, use [Apple's per-app approval guidance](https://support.apple.com/en-us/102445). Do not disable Gatekeeper, remove quarantine attributes, or ignore malware/damaged-app warnings.

The universal build, all 32 XCTest tests and sample-only GPU checks passed on an M1 Pro. The generated QA demos are not real-desktop recordings. Physical compensation, custom triggers on actual hardware, login, wake/unlock, permissioned restoration and global shortcut delivery still need hands-on validation. See the complete installation, privacy, compatibility, attribution, and source-build documentation at:

[StarWars/iphone-duo-closing-animation-on-macbook](https://github.com/StarWars/iphone-duo-closing-animation-on-macbook)

Before running the prototype, read [EULA.md](EULA.md). Save your work, keep backups and test in a non-critical environment. It is experimental software supplied without warranties to the extent permitted by law; liability exclusions do not override mandatory rights. The menu-bar **Licence and risk notice…** action opens the bundled terms.

The app is inspired by iPhone DUO's animation. See `ATTRIBUTIONS.md`, `LICENSE` and `NOTICE` included in this archive. `LICENSE`, `NOTICE` and `EULA.md` are also bundled inside the app.
