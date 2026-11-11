# SPDX-License-Identifier: MPL-2.0
# Synthetic installer fixtures only. These helpers never launch a browser.
function New-ZenInstallerFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Root, [string]$HandlerSource)
    $Root = [IO.Path]::GetFullPath($Root)
    $install = Join-Path $Root 'install'
    $profile = Join-Path $Root 'profile'
    $artifacts = Join-Path $Root 'artifacts'
    foreach ($directory in @($install, $profile, $artifacts, (Join-Path $Root 'appdata'))) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $Root 'SYNTHETIC-TEST-FIXTURE'), 'zen-window-reuse tests only', $encoding)
    [IO.File]::WriteAllText((Join-Path $install 'zen.exe'), 'ZEN SYNTHETIC TEST EXECUTABLE - NOT RUNNABLE', $encoding)
    [IO.File]::WriteAllText((Join-Path $profile 'prefs.js'), '// Synthetic profile only', $encoding)
    [IO.File]::WriteAllText((Join-Path $profile 'compatibility.ini'), "[Compatibility]`r`nLastVersion=fixture`r`nLastOSABI=fixture`r`n", $encoding)
    if (!$HandlerSource) {
        $HandlerSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures\BrowserContentHandler.original.sys.mjs'))
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open((Join-Path $install 'omni.ja'), [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in @('moz-src/browser/components/BrowserContentHandler.sys.mjs', '.hidden/sentinel.bin', 'nested/directory/sentinel.txt')) {
            $entry = $zip.CreateEntry($name)
            $entry.LastWriteTime = New-Object DateTimeOffset(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $stream = $entry.Open()
            try {
                $bytes = if ($name.EndsWith('.mjs')) { $encoding.GetBytes($HandlerSource) } elseif ($name.EndsWith('.bin')) { [byte[]]@(0, 255, 10, 0, 128, 34) } else { $encoding.GetBytes('Nested ZIP path must survive.') }
                $stream.Write($bytes, 0, $bytes.Length)
            } finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose() }
    [pscustomobject]@{ Root = $Root; Install = $install; Profile = $profile; Artifacts = $artifacts; Archive = (Join-Path $install 'omni.ja'); Compatibility = (Join-Path $profile 'compatibility.ini') }
}

function Get-FixtureZipContents {
    param([Parameter(Mandatory = $true)][string]$Path)
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $contents = @{}
        foreach ($entry in $zip.Entries) {
            $stream = $entry.Open()
            $memory = New-Object IO.MemoryStream
            try { $stream.CopyTo($memory); $contents[$entry.FullName] = [Convert]::ToBase64String($memory.ToArray()) } finally { $stream.Dispose(); $memory.Dispose() }
        }
        $contents
    } finally { $zip.Dispose() }
}
