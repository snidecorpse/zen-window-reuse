# Zen Window Reuse

Launch Zen again from Windows Start/Search and bring your existing window forward without opening another main window.

This unofficial, reversible Windows workaround is tested with **Zen 1.24.1b**. It restores minimized windows, permits reuse across Windows virtual desktops, and preserves cold startup, Ctrl+N, explicit new/private windows, and URL dispatch.

The workaround already has an [about:config toggle](#toggle-the-behavior). The repository also includes a [native Settings proposal](docs/UPSTREAM_PROPOSAL.md) and an [upstream source draft](upstream/README.md) for a default-off checkbox.

## Quick start

Requires Windows PowerShell 5.1 or PowerShell 7 and an installed Zen Browser. No Python, archive utility, extension, or downloaded runtime is needed.

1. [Download the source ZIP](https://github.com/snidecorpse/zen-window-reuse/archive/refs/heads/main.zip) or clone this repository, then extract it.
2. Fully exit Zen, including all windows. Open PowerShell in the project directory. Use **Administrator PowerShell** for a `Program Files` installation.
3. Review the script, prepare the patch, then apply it:

```powershell
# Read-only status.
.\Patch-ZenWindowReuse.ps1 -Check

# Build a verified candidate and previews; leave Zen and profiles unchanged.
.\Patch-ZenWindowReuse.ps1 -PrepareOnly

# Keep a matching backup, install, and queue browser code-cache refresh.
.\Patch-ZenWindowReuse.ps1
```

Open Zen normally, then launch it again from Windows Search. The same suitable window should come forward. Minimize it and repeat to check restoration. **Ctrl+N still opens a new window.**

If PowerShell blocks a downloaded script, review it and use a method permitted by your local policy; see [troubleshooting](docs/TROUBLESHOOTING.md#powershell-blocks-a-downloaded-script).

## Toggle the behavior

In `about:config`, search for **`zen.window-reuse-on-launch`**. If absent, create it as a **Boolean**. Set it to `false` to disable reuse or `true` to enable it.

This unofficial preference defaults to enabled when absent because installing the workaround is an explicit choice. It has no effect in stock Zen. The [upstream draft](upstream/README.md) instead registers a default-off preference and adds a localized Settings checkbox.

## Updates and rollback

After a Zen update, fully close Zen and rerun the script. Keep browser updates enabled. A changed or ambiguous handler layout stops for review rather than guessing where to patch.

Keep `artifacts/`, which contains the original archive, verified candidate, and matching manifest. To restore, close Zen and use the exact backup path reported by the installer:

```powershell
.\Patch-ZenWindowReuse.ps1 -RestoreBackup 'D:\saved\artifacts\omni.original.<hash>.ja'
```

If artifacts were moved, add `-OutputDirectory 'D:\saved\artifacts'`. Restoration checks the build and archive hashes and refreshes the code cache. It refuses a backup from an older/different installed build. [Full rollback instructions](docs/TROUBLESHOOTING.md#restore-the-original-archive).

## Custom installations and profiles

`-ZenPath` accepts an installation directory or executable path. For a portable/unregistered profile, also supply its **Root Directory** from `about:profiles`:

```powershell
.\Patch-ZenWindowReuse.ps1 -ZenPath 'D:\Apps\Zen Browser' -ProfilePath 'D:\Browser Profiles\Zen'
```

Registered initialized profiles are discovered automatically. A supplied profile must contain `prefs.js`. If elevating with a different Windows account, explicitly supply the intended profile.

## External links and Windows virtual desktops

The handler patch concerns launches **without a URL**. External links use separate existing preferences:

| Preference | Value | Behavior |
| --- | --- | --- |
| `browser.link.open_newwindow.override.external` | `3` | Request a new tab in an existing window. |
| `browser.tabs.loadDivertedInBackground` | `false` | Select the opened tab. |
| `widget.prefer_windows_on_current_virtual_desktop` | `false` | Allow reuse across Windows virtual desktops. |

Set them in `about:config`, or close Zen and optionally add them to the selected profile's `user.js`:

```powershell
.\Patch-ZenWindowReuse.ps1 -ConfigureExternalLinks -ProfilePath 'D:\Browser Profiles\Zen'
```

This also applies/checks the launch patch. `user.js` reapplies its values at startup. Archive restoration does not remove these optional preferences; see [undo instructions](docs/TROUBLESHOOTING.md#external-links-still-open-differently).

Sources: [Firefox preference definitions](https://github.com/mozilla-firefox/firefox/blob/main/browser/app/profile/firefox.js), [window tracker](https://github.com/mozilla-firefox/firefox/blob/main/browser/modules/BrowserWindowTracker.sys.mjs), and [Zen issue #15411](https://github.com/zen-browser/desktop/issues/15411). `browser.link.use_external_window` is not a real preference.

## What changes

- Finds the actual handler entry in either installed `omni.ja`; the tested build uses the top-level archive.
- Adds a preference-gated reuse step to the remote, argument-free fallback, with privacy filtering and minimized-window restoration.
- Rebuilds a clean ZIP with exact entry names and verifies every unchanged entry's decompressed SHA-256. Keeps build-specific backups and detects concurrent changes.
- Backs up profile `compatibility.ini` files and sets only `[Compatibility] InvalidateCaches=1`, using [Gecko's startup mechanism](https://github.com/mozilla-firefox/firefox/blob/main/toolkit/xre/nsAppRunner.cpp).

Cache invalidation is essential: replacing the archive alone can leave the original handler cached. Running `zen.exe -purgecaches` while Zen is already open does not reload its code. [Troubleshooting](docs/TROUBLESHOOTING.md) covers a one-time cold reset.

The script does not terminate Zen or publish browser data. It changes `user.js` only when `-ConfigureExternalLinks` is requested. See the readable [runtime diff](BrowserContentHandler.patch).

## Validation and limits

Manually verified on Windows with **Zen 1.24.1b**, build `20261106124806`: a bare relaunch reproduced the extra window before cache invalidation; after a cold cache reset, repeated launches reused the same window. Other versions require validation, even if structural matching succeeds. macOS/Linux are outside this installer's scope.

Automated tests use synthetic archives/profiles and browser-service mocks. They cover handler behavior, archive preservation, backup/restore, preparation, cache invalidation, and unsupported inputs. They do not replace native focus tests or a full Zen build. See [test commands](tests/README.md), the inactive [Windows CI template](ci/windows-tests.yml) and [activation instructions](docs/CI_SETUP.md), and the upstream draft's separate [validation status](upstream/README.md).

## Share or contribute

- [Forum post draft](docs/FORUM_POST.md): ready to adapt and post yourself.
- [Feature proposal](docs/UPSTREAM_PROPOSAL.md): behavior contract and rationale.
- [Upstream source package](upstream/README.md): a localized Settings implementation draft.
- [Contributing](CONTRIBUTING.md): test and compatibility expectations.

Start a Zen [Ideas discussion](https://github.com/zen-browser/desktop/discussions) and follow its [contribution guide](https://docs.zen-browser.app/contribute). A default-off checkbox preserves current behavior for other users. This project does not submit forum posts, Zen issues, or upstream pull requests automatically.

## License

[MPL-2.0](LICENSE). Source patches and fixtures inherit Mozilla/Zen notices; see [NOTICE](NOTICE). This independent project is not endorsed by Zen Browser or Mozilla. Share source and instructions, not a patched `omni.ja` or a browser profile.
