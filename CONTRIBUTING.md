# Contributing to Duo Lid

Duo Lid is an experimental native macOS app. See [README.md](README.md) for usage and limitations and [duo-animation/README.md](duo-animation/README.md) for build/test commands.

## Report a problem

Open a GitHub issue with the app version, macOS version, Mac model, trigger angle and reproduction steps. State whether the problem occurs in the generated preview, sensor preview or real desktop overlay. A sample-only reproduction is especially helpful.

Share recordings or screenshots only after checking for personal desktop content. The app does not automatically send diagnostics or collect telemetry.

## Make a change

1. Build the checked-in Xcode project; XcodeGen is needed only after changing `duo-animation/project.yml`.
2. Keep Swift 6 strict concurrency, macOS 14 compatibility and bundle ID `pl.appbeat.DuoLid`.
3. Preserve raw trigger removal, pause controls, capture cancellation and sleep/lock safeguards. Avoid unrelated permissions and runtime packages.
4. Run relevant XCTest checks. For rendering changes, also run sample-only GPU verification; document any hardware-only cases not exercised.
5. Keep preview/overlay geometry consistent and state smoothing or capture-latency tradeoffs.
6. Include a short description of the behavior changed and validation performed.

Published QA images/videos must come from the generated sample/calibration desktop. Keep personal/reference recordings, build products and local logs out of Git. Retain [LICENSE](LICENSE) and [NOTICE](NOTICE) when redistributing the project.
