# Troubleshooting

Run commands from the directory containing `Patch-ZenWindowReuse.ps1`. Use Administrator PowerShell when applying or restoring an installation under `Program Files`.

## The patch is installed, but launching Zen still creates a window

Check the installed archive:

```powershell
.\Patch-ZenWindowReuse.ps1 -Check
```

`Patched: True` means the recognized patch is present on disk. It does not prove that an already running Zen process loaded that code.

Fully exit every Zen window and ensure no `zen.exe` processes remain. Rerun the script while Zen is closed. An already-patched run still queues browser code-cache invalidation for registered profiles. Then open Zen normally and repeat the launch test.

For a one-time cache reset, launch the executable from your own installation with `-purgecaches` after fully exiting Zen. For a standard installation:

```powershell
& 'C:\Program Files\Zen Browser\zen.exe' -purgecaches
```

Passing this flag while Zen is already running forwards the request to that process; it does not reload its already loaded browser code. This was the cause of the initial local test failure.

`CacheInvalidationsPending` in `-Check` reports queued `compatibility.ini` markers. Zen consumes those markers during its next successful cold startup, so zero pending markers afterward is normal.

## The script says Zen is still running

Exit Zen normally and check Task Manager for remaining Zen processes. The installer deliberately does not terminate the browser. Finish any browser work before closing it, then rerun the script.

`-Check` is read-only, and `-PrepareOnly` can prepare artifacts while Zen is running. Applying and restoring require a closed browser.

## A Zen update removed the behavior

Close Zen and run the script again against the updated installation. Each unmodified archive gets a separate backup named by its SHA-256 hash.

Do not restore a previous version's `omni.ja` into a newer Zen installation. The restore command checks the manifest and installed archive hash and refuses that mismatch.

If the script reports **Unsupported handler layout**, or finds zero or multiple candidate handlers, keep the new Zen version and review the updated source before changing the patch. The script stops rather than guessing at a replacement location.

## Zen is installed somewhere else, or uses a portable profile

Supply the installation directory or executable path:

```powershell
.\Patch-ZenWindowReuse.ps1 -ZenPath 'D:\Apps\Zen Browser'
```

For a portable or unregistered profile, also supply its root directory so its browser code cache is invalidated:

```powershell
.\Patch-ZenWindowReuse.ps1 -ZenPath 'D:\Apps\Zen Browser' -ProfilePath 'D:\Browser Profiles\Zen'
```

Find the profile's **Root Directory** in `about:profiles` before exiting Zen. The selected directory must contain `prefs.js`.

## Disable reuse without restoring the archive

In `about:config`, create a **Boolean** preference named `zen.window-reuse-on-launch` and set it to `false`. Set it to `true` to enable reuse again. The patched handler reads it on each relevant launch.

This preference belongs to the workaround. Creating it in unmodified stock Zen does not add the feature. It is also separate from the proposed native Settings checkbox.

## External links still open differently

The no-URL launch patch and external-link preferences are separate. Confirm the values described in the [README](../README.md#external-links-and-windows-virtual-desktops) in the profile that actually opens the link.

The optional `-ConfigureExternalLinks -ProfilePath ...` command writes a managed block to that profile's `user.js`. Those values are reapplied at startup. To undo them, close Zen, remove the block between `BEGIN zen-reuse-window external links` and `END zen-reuse-window external links`, then restart Zen and reset the three preferences in `about:config` if desired. Restoring the browser archive does not remove this profile configuration.

The patch also preserves explicit new-window requests, kiosk launches, and privacy boundaries. An ordinary launch may open a normal window when only private windows exist.

## Restore the original archive

Keep the script's `artifacts` directory, including both the matching original archive and its `patch-<hash>.json` manifest. Close Zen, then use the exact backup path printed when the patch was applied:

```powershell
.\Patch-ZenWindowReuse.ps1 -RestoreBackup 'D:\saved\artifacts\omni.original.<hash>.ja'
```

If the artifacts were moved, also pass their directory:

```powershell
.\Patch-ZenWindowReuse.ps1 -RestoreBackup 'D:\saved\artifacts\omni.original.<hash>.ja' -OutputDirectory 'D:\saved\artifacts'
```

The restore operation checks the build and hashes, replaces the archive, and queues code-cache invalidation. It does not roll back optional external-link preferences in `user.js`.

## PowerShell blocks a downloaded script

Read the script first. If your local execution policy blocks it, use a policy-approved method for running local scripts; an organization's policy may require a signed script. Avoid changing the machine-wide policy just for this workaround. The script requires Windows PowerShell 5.1 or PowerShell 7 and built-in .NET ZIP support.

## Report a problem

Include your Zen version, Windows version, PowerShell version, launch method, exact error, and the output of `-Check`. Say whether the target window was minimized, private, or on another virtual desktop. Remove personal paths from logs before posting. Share the source diff and diagnostic text rather than browser profiles or complete `omni.ja` archives.
