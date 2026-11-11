# SPDX-License-Identifier: MPL-2.0
# End-to-end tests use tiny synthetic archives, fake non-runnable zen.exe files,
# and isolated profiles. They do not launch Zen or touch a real installation.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $testsDirectory 'FixtureSupport.ps1')
$testRoot = Join-Path (Join-Path $testsDirectory '..\.work') ('installer-tests-' + [guid]::NewGuid().ToString('N'))
$hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$script:passed = 0
function Assert-Equal($Actual, $Expected, [string]$Message) { if ($Actual -cne $Expected) { throw $Message } }
function Assert-True($Actual, [string]$Message) { if (!$Actual) { throw $Message } }
function Get-TestHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Invoke-TestInstaller($Fixture, [string]$Operation, [string]$Backup, [switch]$ExpectFailure) {
    $argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $testsDirectory 'Invoke-FixtureInstaller.ps1'), '-FixtureRoot', $Fixture.Root, '-Operation', $Operation)
    if ($Backup) { $argsList += @('-RestoreBackup', $Backup) }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = & $hostExe @argsList 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $previousPreference }
    if ($ExpectFailure) { Assert-True ($code -ne 0) "Expected failure, got success: $output" } elseif ($code -ne 0) { throw "Fixture installer failed: $output" }
}
function Test-Case([string]$Name, [scriptblock]$Body) { & $Body; $script:passed++; Write-Output "PASS: $Name" }
$fixture = New-ZenInstallerFixture -Root (Join-Path $testRoot 'valid')
$originalHash = Get-TestHash $fixture.Archive
$originalCompatibility = Get-TestHash $fixture.Compatibility
$originalEntries = Get-FixtureZipContents $fixture.Archive
$entryName = 'moz-src/browser/components/BrowserContentHandler.sys.mjs'
Test-Case 'prepare verifies the archive and previews the cache marker without changing installed files' {
    Invoke-TestInstaller $fixture 'prepare'
    Assert-Equal (Get-TestHash $fixture.Archive) $originalHash 'Prepare modified the archive.'
    Assert-Equal (Get-TestHash $fixture.Compatibility) $originalCompatibility 'Prepare modified the profile.'
    Assert-True (Test-Path -LiteralPath (Join-Path $fixture.Artifacts 'BrowserContentHandler.patched.sys.mjs')) 'Prepared handler missing.'
}
Test-Case 'apply changes only the handler, preserves hidden/binary/nested entries, and invalidates browser code cache' {
    Invoke-TestInstaller $fixture 'apply'
    $newEntries = Get-FixtureZipContents $fixture.Archive
    Assert-Equal $newEntries.Count $originalEntries.Count 'Entry count changed.'
    foreach ($name in $originalEntries.Keys) {
        Assert-True $newEntries.ContainsKey($name) "Missing ZIP path $name"
        if ($name -ne $entryName) { Assert-Equal $newEntries[$name] $originalEntries[$name] "Unrelated ZIP content changed: $name" }
    }
    $handler = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($newEntries[$entryName]))
    Assert-True $handler.Contains('// zen-reuse-window patch v1 (MPL-2.0)') 'Installed marker missing.'
    Assert-True ([IO.File]::ReadAllText($fixture.Compatibility).Contains('InvalidateCaches=1')) 'Cache invalidation missing.'
    $backup = Get-ChildItem -LiteralPath $fixture.Artifacts -Filter 'omni.original.*.ja' | Select-Object -First 1
    Assert-Equal (Get-TestHash $backup.FullName) $originalHash 'Original backup is not byte-identical.'
}
$patchedHash = Get-TestHash $fixture.Archive
Test-Case 'reapply is idempotent and repairs a consumed cache marker' {
    [IO.File]::WriteAllText($fixture.Compatibility, [IO.File]::ReadAllText($fixture.Compatibility).Replace('InvalidateCaches=1', 'InvalidateCaches=0'))
    Invoke-TestInstaller $fixture 'apply'
    Assert-Equal (Get-TestHash $fixture.Archive) $patchedHash 'Reapply changed the patched archive.'
    Assert-True ([IO.File]::ReadAllText($fixture.Compatibility).Contains('InvalidateCaches=1')) 'Reapply did not repair cache invalidation.'
}
Test-Case 'restore returns the exact original archive and invalidates caches for original code' {
    [IO.File]::WriteAllText($fixture.Compatibility, [IO.File]::ReadAllText($fixture.Compatibility).Replace('InvalidateCaches=1', 'InvalidateCaches=0'))
    $backup = Get-ChildItem -LiteralPath $fixture.Artifacts -Filter 'omni.original.*.ja' | Select-Object -First 1
    Invoke-TestInstaller $fixture 'restore' $backup.FullName
    Assert-Equal (Get-TestHash $fixture.Archive) $originalHash 'Restore is not byte-identical to original.'
    Assert-True ([IO.File]::ReadAllText($fixture.Compatibility).Contains('InvalidateCaches=1')) 'Restore did not invalidate cache.'
}
Test-Case 'an unsupported future source layout fails closed without touching archive or profile' {
    $source = [IO.File]::ReadAllText((Join-Path $testsDirectory 'fixtures\BrowserContentHandler.original.sys.mjs')).Replace('lazy.WindowsUIUtils.inWin10TabletMode', 'upstream.changedTabletMode')
    $unknown = New-ZenInstallerFixture -Root (Join-Path $testRoot 'unsupported') -HandlerSource $source
    $beforeArchive = Get-TestHash $unknown.Archive
    $beforeCompatibility = Get-TestHash $unknown.Compatibility
    Invoke-TestInstaller $unknown 'apply' -ExpectFailure
    Assert-Equal (Get-TestHash $unknown.Archive) $beforeArchive 'Unsupported layout modified archive.'
    Assert-Equal (Get-TestHash $unknown.Compatibility) $beforeCompatibility 'Unsupported layout modified profile.'
}
Test-Case 'a backup cannot overwrite a subsequently changed browser archive' {
    $changed = New-ZenInstallerFixture -Root (Join-Path $testRoot 'changed-build')
    Invoke-TestInstaller $changed 'apply'
    $backup = Get-ChildItem -LiteralPath $changed.Artifacts -Filter 'omni.original.*.ja' | Select-Object -First 1
    $zip = [IO.Compression.ZipFile]::Open($changed.Archive, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $zip.CreateEntry('updated-build-marker.txt')
        $stream = $entry.Open()
        try { $stream.WriteByte(1) } finally { $stream.Dispose() }
    } finally { $zip.Dispose() }
    $changedHash = Get-TestHash $changed.Archive
    Invoke-TestInstaller $changed 'restore' $backup.FullName -ExpectFailure
    Assert-Equal (Get-TestHash $changed.Archive) $changedHash 'Stale backup overwrote a changed build.'
}
Write-Output "PASS: $script:passed installer lifecycle cases. Synthetic files: $testRoot"
