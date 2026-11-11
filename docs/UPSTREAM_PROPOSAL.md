# Proposal: focus an existing window when Zen is launched again

## Problem and requested option

On Windows, launching Zen from Start/Search while a browser window is already open can create another main window. Users who use Start/Search as an application switcher may expect it to bring their existing session forward.

Add an opt-in Settings checkbox:

> **Focus an existing window when Zen is launched again**
>
> When Zen is already running, launching it without a URL restores and focuses an existing browser window.

Proposed preference: `zen.window-reuse-on-launch`, default **`false`** upstream. The default preserves the established launch behavior. The Settings control should bind to the same preference, so changing it in `about:config` and changing the checkbox produce the same result.

The local workaround enables its behavior by default because installing it is an explicit choice. Its existing `about:config` preference demonstrates the toggle, but it does not add a native Settings checkbox to stock Zen.

## Behavior contract

| Situation | Expected behavior with the option enabled |
| --- | --- |
| First launch, no browser window available | Open Zen normally, including normal startup and session-restore behavior. |
| Relaunch with no URL and an eligible main window | Restore it if minimized, focus it, and create no additional main window or tab. |
| Existing eligible window on another Windows virtual desktop | Allow that window to be selected and focused. |
| Multiple eligible main windows | Follow Zen's most-recent suitable-window selection policy. |
| Only private windows open during ordinary browsing mode | Open a normal window; an ordinary launcher action should not surface a private session. |
| Permanent private browsing enabled | Reuse a suitable private window. |
| Explicit new, blank, or private window request | Preserve the explicit request. |
| Ctrl+N, a menu command, or another deliberate new-window action | Preserve normal behavior. |
| Kiosk launch or unhandled command-line arguments | Preserve the existing command-line behavior. |
| External URL | Keep the existing URL-routing path and its preferences. |
| Option disabled | Preserve existing launch behavior. |

An upstream implementation should also evaluate launches arriving while the first window is still loading. Reusing an eligible pending window may avoid duplicates from rapid repeated launches, provided the privacy and explicit-command rules remain intact.

## Implementation outline

The inherited [`BrowserContentHandler.sys.mjs`](https://github.com/mozilla-firefox/firefox/blob/main/browser/components/BrowserContentHandler.sys.mjs) contains the default no-URL command-line fallback. Zen maintains changes to that file through [`src/browser/components/BrowserContentHandler-sys-mjs.patch`](https://github.com/zen-browser/desktop/blob/dev/src/browser/components/BrowserContentHandler-sys-mjs.patch).

The working local patch adds a guarded reuse step inside that fallback, before the ordinary new-window call. It uses [`BrowserWindowTracker.getTopWindow`](https://github.com/mozilla-firefox/firefox/blob/main/browser/modules/BrowserWindowTracker.sys.mjs), supplies an explicit privacy filter, permits an inactive Windows workspace, restores a minimized window, and focuses it. The upstream change should use Zen's current source layout and preference/localization conventions rather than distributing an installed `omni.ja`.

The source contribution needs:

1. A registered default-off preference.
2. A localized Settings checkbox and explanatory text in an appropriate startup/window section.
3. The preference-gated handler change in Zen's source patch pipeline.
4. Tests covering the contract above, including actual OS relaunch behavior.

The local installer also changes `compatibility.ini` to invalidate cached browser code after modifying a release archive. A normal upstream build/update should use the build's existing cache lifecycle; the archive-installer workaround is not part of the proposed browser feature.

## External links are a separate preference decision

The proposed checkbox concerns launches without a URL. Existing Firefox-derived preferences already control external URLs:

| Preference | Value used by the optional workaround configuration |
| --- | --- |
| `browser.link.open_newwindow.override.external` | `3`: request a new tab in an existing window. |
| `browser.tabs.loadDivertedInBackground` | `false`: select the opened tab. |
| `widget.prefer_windows_on_current_virtual_desktop` | `false`: allow reuse across Windows virtual desktops. |

The new launch checkbox should not silently overwrite those preferences. Their definitions are in [Firefox's browser preferences](https://github.com/mozilla-firefox/firefox/blob/main/browser/app/profile/firefox.js) and [window-tracker implementation](https://github.com/mozilla-firefox/firefox/blob/main/browser/modules/BrowserWindowTracker.sys.mjs). Related Zen reports include [#13469](https://github.com/zen-browser/desktop/issues/13469) and [#15411](https://github.com/zen-browser/desktop/issues/15411).

## Validation and remaining work

The local workaround was tested with Zen **1.24.1b on Windows**. Live testing reproduced an extra window before cache invalidation; after a fully closed launch with `-purgecaches`, repeated bare executable launches reused the same window.

The repository's 13 handler tests execute the complete default command-line handler from a source fixture with browser-service mocks. Another 10 cache tests and 6 installer lifecycle tests exercise discovery, previews, backups, archive preservation, restoration, idempotence, concurrency, and unsupported input. These tests do not establish every native window/focus behavior or replace Zen's browser integration tests.

Before requesting an upstream merge, run Zen's required checks and test a built browser with both checkbox states. Include minimized and other-desktop windows, rapid relaunch during startup, explicit new/private windows, private-only sessions, external URLs, and normal cold startup. Confirm the Settings control, preference persistence, localization, and platform scope with maintainers.

## Suggested contribution route

Start an [Ideas discussion](https://github.com/zen-browser/desktop/discussions) describing the option and its behavior contract. Link the working local workaround and relevant existing reports, then confirm the desired default, Settings placement, and platform scope before expanding the implementation.

Follow [Zen's contribution guidance](https://docs.zen-browser.app/contribute) and [desktop build instructions](https://docs.zen-browser.app/contribute/desktop). Keep the eventual pull request focused on this optional launch behavior. The repository's upstream source draft is a starting point for review; its validation status should be stated explicitly when sharing it.
