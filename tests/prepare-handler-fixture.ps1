# SPDX-License-Identifier: MPL-2.0
# Produces a small patched handler using the actual installer in preview mode.
[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$testsDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (!$OutputPath) { $OutputPath = Join-Path $testsDirectory '..\.work\handler-fixture\BrowserContentHandler.patched.sys.mjs' }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
. (Join-Path $testsDirectory 'FixtureSupport.ps1')
$root = Join-Path (Join-Path $testsDirectory '..\.work') ('handler-fixture-' + [guid]::NewGuid().ToString('N'))
$fixture = New-ZenInstallerFixture -Root $root
$hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$output = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testsDirectory 'Invoke-FixtureInstaller.ps1') -FixtureRoot $fixture.Root -Operation prepare 2>&1
if ($LASTEXITCODE -ne 0) { throw "Fixture preparation failed: $output" }
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $fixture.Artifacts 'BrowserContentHandler.patched.sys.mjs') -Destination $OutputPath -Force
Write-Output $OutputPath
