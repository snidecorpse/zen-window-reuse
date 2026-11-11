# Tests

The tests run on Windows with Windows PowerShell 5.1 or PowerShell 7 and Node.js 24. They work from a clean clone: no Zen installation, browser download, administrator access, or existing `artifacts/` directory is needed.

From the repository directory, run:

```powershell
# Windows PowerShell 5.1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\cache-invalidation.test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\installer-lifecycle.test.ps1
$env:ZEN_POWERSHELL = 'powershell.exe'
node --test .\tests\launch-handler.test.cjs

# PowerShell 7
pwsh -NoProfile -File .\tests\cache-invalidation.test.ps1
pwsh -NoProfile -File .\tests\installer-lifecycle.test.ps1
$env:ZEN_POWERSHELL = 'pwsh'
node --test .\tests\launch-handler.test.cjs
```

`ZEN_POWERSHELL` chooses the PowerShell host that prepares the Node tests' handler fixture. If omitted, the tests use `powershell.exe`. The preparation invokes the actual installer with `-PrepareOnly` against a small synthetic archive; no manual preparation step is required. Generated files stay under the ignored `.work/` directory.

## Coverage

There are 29 cases:

| Suite | Cases | What it checks |
| --- | ---: | --- |
| `launch-handler.test.cjs` | 13 | Executes the complete patched default command-line handler with mocked browser services. Covers cold starts, relaunch focus, minimized restoration, privacy selection, kiosk mode, disabled preference, previously handled actions, remaining flags, and URL routing. |
| `cache-invalidation.test.ps1` | 10 | Profile discovery, background-task exclusion, preservation of unrelated text and encoding, previews, backups, repeat application, concurrent changes, and malformed compatibility files. |
| `installer-lifecycle.test.ps1` | 6 | Runs the production installer through prepare, apply, repeat-apply, and exact-byte restore; verifies binary/hidden/nested ZIP entries, cache invalidation, and refusal of unknown layouts or stale backups. |

These tests do not replace live browser checks. Before announcing support for a new Zen version, test relaunches, minimized windows, virtual desktops, external links, explicit new windows, and private browsing in that version.

## Synthetic installation safeguards

`Invoke-FixtureInstaller.ps1` is a test-only child-process wrapper. It accepts only a directory carrying the test marker and a fake, non-runnable `zen.exe` with the expected fixture contents. It isolates `APPDATA` inside that fixture and mocks only the installer's `Get-Process -Name zen` query for the child process's lifetime. This lets the tests run while a real Zen window is open without terminating it or exposing its installation or profiles to test writes.

The production script's process guard is unchanged. Do not use the test wrapper with a real browser installation.

## Fixture provenance and license

`fixtures/BrowserContentHandler.original.sys.mjs` contains the complete `dch_handle` implementation extracted from Zen `1.24.1b`, build `20261106124806`, SourceStamp `b12eaefbca65b376950e1eb7ae84d3574022ba66`. The surrounding module wrapper is synthetic; the fixture's header records that distinction. The original packaged path was `moz-src/browser/components/BrowserContentHandler.sys.mjs`, from [Zen's source repository](https://github.com/zen-browser/desktop).

The fixture and test code carry MPL-2.0 notices. See the repository's [license](../LICENSE). No browser executable, packaged archive, user profile, browsing data, or patched binary is distributed.

The inactive [GitHub Actions template](../ci/windows-tests.yml) defines a Windows PowerShell 5.1/PowerShell 7 matrix and a PowerShell syntax check. See [activation instructions](../docs/CI_SETUP.md). Hosted CI has not run; the results above are local checks.
