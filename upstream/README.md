# Draft upstream Settings contribution

This directory contains a source contribution candidate for Zen, separate from the installed-browser workaround in the repository root. It adds a real, localized **Startup** checkbox:

> Focus an existing window when Zen is launched again

The checkbox is Windows-only and **off by default**. Its Boolean preference is `zen.window-reuse-on-launch`. Turning it on makes a remote launch with no remaining arguments restore and focus an existing suitable main window. Cold launch, explicit new/private-window commands, kiosk mode, and URL routing keep their existing behavior. An ordinary launch does not select a private window unless permanent private browsing is enabled.

This is a draft for maintainer review, not a built or released Zen feature. The root installer enables its workaround by default and provides an `about:config` toggle; this upstream proposal preserves stock behavior until the user opts in through Settings. Applying this patch to Zen source does not change the installed browser.

## Pinned source and files

The candidate is based on [`zen-browser/desktop` commit `87271fe282e577d8047f5bb4a38d855eee0e3967`](https://github.com/zen-browser/desktop/commit/87271fe282e577d8047f5bb4a38d855eee0e3967), retrieved from `dev` on November 11, 2026. That checkout declares Firefox `160.0` as its engine version in `surfer.json`.

[`zen-window-reuse-setting.patch`](zen-window-reuse-setting.patch) changes:

| Zen repository file | Change |
| --- | --- |
| `prefs/zen/windows.yaml` | Add the default-off Windows preference. |
| `src/browser/components/BrowserContentHandler-sys-mjs.patch` | Add the conditional restore/focus branch to the engine patch. |
| `src/browser/components/preferences/main-js.patch` | Add a `moz-checkbox` to the existing Startup settings group. |
| `src/browser/components/preferences/zen-settings.js` | Register the preference and checkbox binding; expose it only on Windows. |
| `locales/en-US/browser/browser/preferences/zen-preferences.ftl` | Add the English Fluent label for translation through Zen's normal localization workflow. |

Zen stores many Firefox modifications as **patch files inside its source repository**. This candidate is therefore an outer patch that changes Zen's existing inner engine patches. The root [`BrowserContentHandler.patch`](../BrowserContentHandler.patch) is a readable diff for the installed `1.24.1b` handler; it is not a substitute for this upstream patch.

## Apply in a development checkout

Start with a clean checkout. Follow [Zen's build guidelines](https://docs.zen-browser.app/guides/building) and the [repository contribution guide](https://github.com/zen-browser/desktop/blob/87271fe282e577d8047f5bb4a38d855eee0e3967/docs/contribute.md) for your platform and toolchain. These commands only prepare the source change:

```powershell
git clone https://github.com/zen-browser/desktop.git zen-desktop
Set-Location zen-desktop
git switch --detach 87271fe282e577d8047f5bb4a38d855eee0e3967
git switch -c feature/windows-reuse-window-on-launch

# Replace this with the patch's absolute path from this repository.
$patchPath = 'C:\path\to\zen-reuse-window\upstream\zen-window-reuse-setting.patch'
git apply --check $patchPath
git apply $patchPath
git diff --check
git diff
```

Zen's `npm run import` includes preference generation (`ffprefs`) and imports the source/engine patches. Complete the official development setup before importing and building. The source package's `npm run build` and `npm run build:ui` commands invoke Surfer. Use the official build guide instead of treating this repository as a complete Zen toolchain installer.

For a real contribution, rebase onto the latest `dev` after discussing the feature. Regenerate the inner patches through Zen's supported import/export workflow when rebasing. The pinned patch is reproducible; it is not a promise that it will apply unchanged to a future branch tip.

## Verification completed here

- The outer patch passes `git apply --check` against a clean checkout at the pinned Zen commit, and reverses cleanly.
- Both modified inner engine patches pass `git apply --check` against the corresponding files from Mozilla's official [`FIREFOX_160_0_RELEASE`](https://github.com/mozilla-firefox/firefox/tree/FIREFOX_160_0_RELEASE) source tag.
- The resulting `BrowserContentHandler.sys.mjs` and modified `zen-settings.js` pass `node --check`.
- `git diff --check` passes in the patched Zen checkout.

**Not yet verified:** a complete Zen build, the rendered Settings checkbox, browser-chrome tests, cross-desktop/minimized integration in that build, and behavior with enterprise policy or unusual profiles. The root workaround's passing tests and successful `1.24.1b` relaunch test do not establish those results for this newer source candidate. Add focused browser tests and complete the matrix below before asking maintainers to merge it.

## Browser test matrix before a PR

| Case | Expected result |
| --- | --- |
| Fresh profile, option off | Existing stock relaunch behavior. |
| Windows Startup checkbox on/off | Preference changes immediately and persists across restart. |
| Toggle on, ordinary window open, bare executable/Search launch | Existing suitable window focuses; window count stays constant. |
| Suitable window minimized | Same window restores and focuses. |
| Window on another virtual desktop | Existing suitable window is reused rather than duplicated. |
| No window open | A normal browser window opens. |
| Only a private window open in ordinary mode | A normal window opens; private session is not surfaced. |
| Permanent private browsing | Suitable private window can be reused. |
| Explicit New Window, `--new-window URL`, `--blank-window`, or private-window command | Explicit action still works. |
| Kiosk launch | Kiosk behavior is unchanged. |
| External URL | Existing external-link routing preferences and space routing remain authoritative. |
| Linux/macOS | Checkbox hidden and command-line behavior unchanged. |
| Localization/accessibility | Fluent label resolves, keyboard focus works, screen-reader name is present, settings search can find the option. |

## Discuss, then contribute

Use [Zen Discussions → Ideas](https://github.com/zen-browser/desktop/discussions/categories/ideas) to agree on the behavior, label, placement, Windows scope, and default. Related context: [Windows multi-desktop behavior #13469](https://github.com/zen-browser/desktop/issues/13469). Then open a feature branch in your fork and submit a PR targeting `dev` once the build and tests are ready.

Ready-to-edit drafts are in [DISCUSSION_DRAFT.md](DISCUSSION_DRAFT.md) and [PR_DRAFT.md](PR_DRAFT.md). Neither has been submitted. The optional setting is intentionally separate from the external-link preferences documented in the root README.
