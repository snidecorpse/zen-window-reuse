# SPDX-License-Identifier: MPL-2.0
# Runs the production installer against a deliberately non-runnable synthetic
# installation in a separate PowerShell process. Never use this with real Zen.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$FixtureRoot,
    [ValidateSet('prepare', 'apply', 'restore', 'check')][string]$Operation = 'prepare',
    [string]$RestoreBackup
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try {
    # Explicitly use this host's bundled module, even when PowerShell 5.1 was
    # spawned by Node inside a PowerShell 7 environment with another module path.
    Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility') -ErrorAction Stop
    $FixtureRoot = (Resolve-Path -LiteralPath $FixtureRoot).ProviderPath
    $marker = Join-Path $FixtureRoot 'SYNTHETIC-TEST-FIXTURE'
    $install = Join-Path $FixtureRoot 'install'
    if (!(Test-Path -LiteralPath $marker) -or [IO.File]::ReadAllText($marker) -cne 'zen-window-reuse tests only' -or
        [IO.File]::ReadAllText((Join-Path $install 'zen.exe')) -cne 'ZEN SYNTHETIC TEST EXECUTABLE - NOT RUNNABLE') {
        throw 'Not a synthetic test installation. The process guard must never be mocked for a real browser.'
    }
    # Scope both the profile metadata and Get-Process mock to this child process.
    # This allows fixture tests while real Zen is open, without terminating it or
    # exposing any real installation/profile to the tested writes.
    $env:APPDATA = Join-Path $FixtureRoot 'appdata'
    function global:Get-Process {
        param([string]$Name, $ErrorAction)
        if ($Name -ne 'zen') { throw 'Unexpected process query in fixture installer.' }
        return
    }
    $arguments = @{
        ZenPath = $install
        ProfilePath = (Join-Path $FixtureRoot 'profile')
        OutputDirectory = (Join-Path $FixtureRoot 'artifacts')
    }
    switch ($Operation) {
        'prepare' { $arguments.PrepareOnly = $true }
        'restore' {
            if (!$RestoreBackup) { throw 'RestoreBackup is required for a restore fixture.' }
            $resolvedBackup = (Resolve-Path -LiteralPath $RestoreBackup).ProviderPath
            $artifactPrefix = (Join-Path $FixtureRoot 'artifacts') + [IO.Path]::DirectorySeparatorChar
            if (!$resolvedBackup.StartsWith($artifactPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Restore backup must stay inside the fixture.' }
            $arguments.RestoreBackup = $resolvedBackup
        }
        'check' { $arguments.Check = $true }
    }
    & (Join-Path $PSScriptRoot '..\Patch-ZenWindowReuse.ps1') @arguments
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
