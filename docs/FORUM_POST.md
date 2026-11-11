# Windows workaround: focus the existing Zen window when launching from Start/Search

I wanted launching Zen again from Windows Start/Search to bring my existing browser window forward. I put together an unofficial, reversible workaround for that behavior:

**Source and instructions: https://github.com/snidecorpse/zen-window-reuse**

When Zen is already running and you launch it again without a URL, the patched handler focuses an existing suitable main window and restores it if minimized. A cold launch still opens Zen normally. Explicit new-window and private-window commands keep working, including Ctrl+N. Ordinary launches keep normal and private windows separate.

The project includes a readable source diff and a PowerShell script. The script finds the installed handler, backs up the original archive, changes that handler, rebuilds the archive, and verifies every unchanged entry. It also invalidates Zen's browser code cache for the next launch. That last step mattered in testing: replacing the archive alone left Zen using the cached original code.

To try it:

1. Download the repository and read the script and instructions.
2. Fully exit Zen. Open PowerShell in the downloaded folder, using Administrator PowerShell for a `Program Files` installation.
3. Run `.\Patch-ZenWindowReuse.ps1 -PrepareOnly` to prepare and inspect it, then `.\Patch-ZenWindowReuse.ps1` to apply it.
4. Open Zen normally, then launch it again from Windows Search. The existing window should come forward.

The script reports the backup location and includes a restore command. Zen updates can replace the patch, so reapply it against the updated installation. If an update changes the handler beyond the recognized layout, the script stops for review.

Tested locally with **Zen 1.24.1b on Windows**. Repeated launches were verified in the running browser after a cold cache reset. The package includes 29 automated cases: 13 handler tests with browser-service mocks, 10 cache-invalidation fixtures, and 6 complete installer lifecycle cases. PowerShell fixtures pass in PowerShell 7 and Windows PowerShell 5.1. Other Zen versions and operating systems have not been validated.

The workaround already has an optional `about:config` Boolean, `zen.window-reuse-on-launch`: create it and set it to `false` to disable reuse. This is a preference added by this patch, not an existing stock-Zen setting.

External links use separate, existing preferences; the README explains how to open them in a selected tab of an existing window, including across Windows virtual desktops.

I'd like to propose a native, opt-in Settings checkbox such as **“Focus an existing window when Zen is launched again.”** The repository includes a contribution proposal and a source-change draft for discussion. A native option would avoid patching the installed archive after updates.

Feedback on the behavior and the upstream approach would be welcome. Please include the Zen version, Windows version, launch method, and whether the issue occurs with a normal, minimized, or other-desktop window.
