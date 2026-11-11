# Add an opt-in setting to reuse a window on Windows relaunch

Windows users who open Zen again through Search can receive another main window while a suitable one is already open. This adds a default-off Startup setting that instead restores and focuses the existing window for argument-free remote launches.

The change registers `zen.window-reuse-on-launch`, adds a localized `moz-checkbox` using the existing Settings infrastructure, and extends the command-line handler through Zen's engine patch. The control and behavior are Windows-only. It preserves cold start, explicit new/private-window commands, kiosk mode, normal/private separation, and existing external-link/space routing.

Validation completed for this draft:

- Outer patch applies cleanly to Zen `87271fe282e577d8047f5bb4a38d855eee0e3967`.
- Modified inner patches apply to Mozilla `FIREFOX_160_0_RELEASE` source files.
- JavaScript syntax checks and `git diff --check` pass.

Before submitting this PR, replace this paragraph with actual Zen build, browser-test, and manual verification results. A full build and rendered Settings verification have not yet been performed. Add a link to the accepted feature discussion and the browser tests covering the cases in `upstream/README.md`. Do not report the separate installed-archive workaround's tests as source-build test results.
