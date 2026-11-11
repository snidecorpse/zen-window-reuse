# SPDX-License-Identifier: MPL-2.0
# The source anchor below is from Mozilla/Zen BrowserContentHandler.sys.mjs.
# This Source Code Form is subject to the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, obtain one at
# https://mozilla.org/MPL/2.0/.
<#
.SYNOPSIS
Focus an existing Zen window when Zen is launched again without arguments.
.DESCRIPTION
Requires Windows PowerShell 5.1 or PowerShell 7. Close Zen before applying.
Uses built-in .NET ZIP support; downloads and third-party tools are not needed.
Backups and verified candidates are saved beside this script in artifacts/.
Program Files installations require an elevated PowerShell for installation.
#>
[CmdletBinding()]
param(
    [string]$ZenPath,
    [switch]$PrepareOnly,
    [switch]$Check,
    [string]$RestoreBackup,
    [switch]$ConfigureExternalLinks,
    [string]$ProfilePath,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'artifacts')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$marker = '// zen-reuse-window patch v1 (MPL-2.0)'

function Get-Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Assert-ZenClosed {
    if (@(Get-Process -Name zen -ErrorAction SilentlyContinue).Count) {
        throw 'Close Zen normally before applying or restoring. This script never terminates your browser.'
    }
}
function Read-Entry($Entry) {
    $stream = $Entry.Open()
    $reader = New-Object IO.StreamReader($stream, $utf8, $true)
    try { $reader.ReadToEnd() } finally { $reader.Dispose() }
}
function Get-EntryHash($Entry) {
    $stream = $Entry.Open()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($stream)) } finally { $sha.Dispose(); $stream.Dispose() }
}
function Save-Backup([string]$Path, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        if ((Get-Hash $Path) -ne (Get-Hash $Destination)) { throw "Existing backup differs: $Destination" }
    } else { Copy-Item -LiteralPath $Path -Destination $Destination }
}
# SPDX-License-Identifier: MPL-2.0
# Cache helpers for the Zen window-reuse installer. These functions do not
# terminate Zen. The caller must keep Zen closed while applying a plan.
# BEGIN CACHE INVALIDATION FUNCTIONS

function Read-ZenIniSections {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $sections = New-Object 'System.Collections.Generic.List[object]'
    $section = $null
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $section = [pscustomobject]@{ Name = $Matches[1]; Values = @{} }
            $sections.Add($section)
        } elseif ($section -and $line -match '^\s*([^;#][^=]*?)\s*=\s*(.*?)\s*$') {
            $section.Values[$Matches[1]] = $Matches[2]
        }
    }
    $sections.ToArray()
}

function Get-ZenProfileDirectories {
    [CmdletBinding()]
    param(
        [string]$ProfileRoot = (Join-Path $env:APPDATA 'zen'),
        [string[]]$AdditionalProfilePaths = @()
    )
    $paths = New-Object 'System.Collections.Generic.List[string]'
    $profileIni = Join-Path $ProfileRoot 'profiles.ini'
    if (Test-Path -LiteralPath $profileIni -PathType Leaf) {
        foreach ($section in @(Read-ZenIniSections $profileIni)) {
            if ($section.Name -cmatch '^Profile\d+$' -and $section.Values.ContainsKey('Path')) {
                $path = [string]$section.Values['Path']
                if ($section.Values['IsRelative'] -eq '1') {
                    $path = Join-Path $ProfileRoot $path
                } elseif (![IO.Path]::IsPathRooted($path)) {
                    # Missing IsRelative is not an instruction to escape the root.
                    $path = Join-Path $ProfileRoot $path
                }
                $paths.Add($path)
            } elseif ($section.Name -cmatch '^Install[^\]]+$' -and $section.Values.ContainsKey('Default')) {
                $path = [string]$section.Values['Default']
                if (![IO.Path]::IsPathRooted($path)) { $path = Join-Path $ProfileRoot $path }
                $paths.Add($path)
            }
        }
    }
    $installIni = Join-Path $ProfileRoot 'installs.ini'
    if (Test-Path -LiteralPath $installIni -PathType Leaf) {
        foreach ($section in @(Read-ZenIniSections $installIni)) {
            if ($section.Values.ContainsKey('Default')) {
                $path = [string]$section.Values['Default']
                if (![IO.Path]::IsPathRooted($path)) { $path = Join-Path $ProfileRoot $path }
                $paths.Add($path)
            }
        }
    }
    foreach ($path in $AdditionalProfilePaths) { if ($path) { $paths.Add($path) } }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $paths) {
        if (!(Test-Path -LiteralPath $path -PathType Container)) { continue }
        $resolved = (Resolve-Path -LiteralPath $path).ProviderPath.TrimEnd('\', '/')
        # prefs.js identifies a real initialized browser profile; do not modify
        # arbitrary directories referenced by an incomplete metadata entry.
        if ((Test-Path -LiteralPath (Join-Path $resolved 'prefs.js') -PathType Leaf) -and $seen.Add($resolved)) {
            $resolved
        }
    }
}

function Get-ZenTextEncoding {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 255 -and $Bytes[1] -eq 254) { return [Text.Encoding]::Unicode }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 254 -and $Bytes[1] -eq 255) { return [Text.Encoding]::BigEndianUnicode }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 239 -and $Bytes[1] -eq 187 -and $Bytes[2] -eq 191) {
        return (New-Object Text.UTF8Encoding($true, $true))
    }
    New-Object Text.UTF8Encoding($false, $true)
}

function Get-ZenCacheInvalidationPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ProfilePaths)
    foreach ($profile in $ProfilePaths) {
        $path = Join-Path $profile 'compatibility.ini'
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
            [pscustomobject]@{ ProfilePath = $profile; Path = $path; Exists = $false; Pending = $false; NeedsWrite = $false; OriginalText = $null; UpdatedText = $null; Encoding = $null; SourceSHA256 = $null }
            continue
        }
        $bytes = [IO.File]::ReadAllBytes($path)
        $encoding = Get-ZenTextEncoding $bytes
        $text = [IO.File]::ReadAllText($path, $encoding)
        $headers = [regex]::Matches($text, '(?m)^\[Compatibility\][ \t]*(?:\r\n|\n|\r|$)')
        if ($headers.Count -ne 1) { throw "Expected one [Compatibility] section in $path; file left unchanged." }
        $header = $headers[0]
        $bodyStart = $header.Index + $header.Length
        $nextSection = [regex]::Match($text.Substring($bodyStart), '(?m)^\[[^\r\n]+\][ \t]*(?:\r\n|\n|\r|$)')
        $bodyEnd = if ($nextSection.Success) { $bodyStart + $nextSection.Index } else { $text.Length }
        $body = $text.Substring($bodyStart, $bodyEnd - $bodyStart)
        $keys = [regex]::Matches($body, '(?m)^(InvalidateCaches[ \t]*=[ \t]*)([^\r\n]*)(\r\n|\n|\r|$)')
        if ($keys.Count -gt 1) { throw "Repeated InvalidateCaches keys in $path; file left unchanged." }
        $pending = $keys.Count -eq 1 -and $keys[0].Groups[2].Value.Trim() -ceq '1'
        $updated = $text
        if (!$pending) {
            if ($keys.Count -eq 1) {
                $value = $keys[0].Groups[2]
                $start = $bodyStart + $value.Index
                $updated = $text.Substring(0, $start) + '1' + $text.Substring($start + $value.Length)
            } else {
                $eolMatch = [regex]::Match($text, '\r\n|\n|\r')
                $eol = if ($eolMatch.Success) { $eolMatch.Value } else { "`r`n" }
                $prefix = $text.Substring(0, $bodyStart)
                if (!$prefix.EndsWith("`n") -and !$prefix.EndsWith("`r")) { $prefix += $eol }
                $updated = $prefix + 'InvalidateCaches=1' + $eol + $text.Substring($bodyStart)
            }
        }
        [pscustomobject]@{
            ProfilePath = $profile; Path = $path; Exists = $true; Pending = $pending;
            NeedsWrite = !$pending; OriginalText = $text; UpdatedText = $updated;
            Encoding = $encoding; SourceSHA256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}

function Get-ZenPathDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).ToLowerInvariant())
        ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant().Substring(0, 20)
    } finally { $sha.Dispose() }
}

function Invoke-ZenCacheInvalidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Plan,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [switch]$PrepareOnly,
        [scriptblock]$BeforeWrite
    )
    foreach ($item in $Plan) {
        if (!$item.Exists -or !$item.NeedsWrite) {
            [pscustomobject]@{ ProfilePath = $item.ProfilePath; Status = $(if ($item.Pending) { 'AlreadyPending' } else { 'NoCompatibilityFile' }); Backup = $null; Preview = $null }
            continue
        }
        $digest = Get-ZenPathDigest $item.Path
        if ($PrepareOnly) {
            $previewDirectory = Join-Path $OutputDirectory 'cache-previews'
            New-Item -ItemType Directory -Path $previewDirectory -Force | Out-Null
            $preview = Join-Path $previewDirectory ("compatibility.$digest.ini")
            [IO.File]::WriteAllText($preview, $item.UpdatedText, $item.Encoding)
            [pscustomobject]@{ ProfilePath = $item.ProfilePath; Status = 'Previewed'; Backup = $null; Preview = $preview }
            continue
        }
        if ($BeforeWrite) { & $BeforeWrite }
        if (!(Test-Path -LiteralPath $item.Path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $item.SourceSHA256) {
            throw "Profile changed after cache preparation: $($item.Path). Run the script again."
        }
        $backupDirectory = Join-Path $OutputDirectory 'cache-backups'
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        $backup = Join-Path $backupDirectory ("compatibility.$digest.$($item.SourceSHA256).ini")
        if (Test-Path -LiteralPath $backup) {
            if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -cne $item.SourceSHA256) {
                throw "Existing cache-marker backup differs: $backup"
            }
        } else { Copy-Item -LiteralPath $item.Path -Destination $backup }
        $stage = $item.Path + '.zen-reuse-' + [guid]::NewGuid().ToString('N') + '.tmp'
        $replaceBackup = $stage + '.original'
        try {
            [IO.File]::WriteAllText($stage, $item.UpdatedText, $item.Encoding)
            $expectedHash = (Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash
            if ($BeforeWrite) { & $BeforeWrite }
            if ((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $item.SourceSHA256) {
                throw "Profile changed before cache-marker replacement: $($item.Path)."
            }
            # A non-null local backup path works in Windows PowerShell 5.1 and
            # PowerShell 7, while keeping the replacement on the same volume.
            [IO.File]::Replace($stage, $item.Path, $replaceBackup)
            if ((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -cne $expectedHash) {
                throw "Cache-marker checksum mismatch; original retained at $replaceBackup"
            }
            Remove-Item -LiteralPath $replaceBackup
        } finally {
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage }
        }
        [pscustomobject]@{ ProfilePath = $item.ProfilePath; Status = 'Invalidated'; Backup = $backup; Preview = $null }
    }
}
# END CACHE INVALIDATION FUNCTIONS

function Install-Archive([string]$Candidate, [string]$Target, [string]$ExpectedHash) {
    Assert-ZenClosed
    if ((Get-Hash $Target) -ne $ExpectedHash) { throw 'Zen changed during preparation. Run the script again.' }
    $stage = Join-Path (Split-Path -Parent $Target) ('omni.ja.zen-reuse-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $replaceBackup = $stage + '.original'
    try {
        Copy-Item -LiteralPath $Candidate -Destination $stage
        if ((Get-Hash $stage) -ne (Get-Hash $Candidate)) { throw 'Staged archive checksum mismatch.' }
        Assert-ZenClosed
        if ((Get-Hash $Target) -ne $ExpectedHash) { throw 'Zen updated before installation; refusing to overwrite it.' }
        # Stage beside the destination, then replace atomically on the same volume.
        # A real backup path avoids PowerShell 5.1 coercing a null string to "".
        [IO.File]::Replace($stage, $Target, $replaceBackup)
        if ((Get-Hash $Target) -ne (Get-Hash $Candidate)) { throw "Installed checksum mismatch. Replacement backup: $replaceBackup" }
        Remove-Item -LiteralPath $replaceBackup
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage }
    }
}

if (!$ZenPath) {
    $candidates = @()
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\zen.exe', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\zen.exe')) {
        $registration = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($registration -and $registration.PSObject.Properties['(default)']) { $candidates += $registration.'(default)' }
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ($base) {
            $candidates += (Join-Path $base 'Zen Browser\zen.exe')
            $candidates += (Join-Path $base 'Zen\zen.exe')
            $candidates += (Join-Path $base 'Programs\Zen Browser\zen.exe')
        }
    }
    $ZenPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (!$ZenPath) { throw 'Zen not found. Supply -ZenPath with the installation directory or zen.exe path.' }
}
$ZenPath = (Resolve-Path -LiteralPath $ZenPath).ProviderPath
$install = if (Test-Path -LiteralPath $ZenPath -PathType Container) { $ZenPath } else { Split-Path -Parent $ZenPath }
$exe = Join-Path $install 'zen.exe'
if (!(Test-Path -LiteralPath $exe -PathType Leaf)) { throw "No zen.exe in $install" }

$handlerMatches = @()
foreach ($path in @((Join-Path $install 'omni.ja'), (Join-Path $install 'browser\omni.ja'))) {
    if (!(Test-Path -LiteralPath $path)) { continue }
    $archive = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match '(^|/)(?:ns)?BrowserContentHandler\.sys\.mjs$') {
                $handlerMatches += [pscustomobject]@{ Path = $path; Entry = $entry.FullName; Source = (Read-Entry $entry) }
            }
        }
    } finally { $archive.Dispose() }
}
if ($handlerMatches.Count -ne 1) { throw "Expected exactly one launch handler, found $($handlerMatches.Count). No installed files changed." }
$target = $handlerMatches[0].Path
$entryName = $handlerMatches[0].Entry
$source = $handlerMatches[0].Source
$originalHash = Get-Hash $target
$version = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
if ($ProfilePath) {
    $ProfilePath = (Resolve-Path -LiteralPath $ProfilePath).ProviderPath
    if (!(Test-Path -LiteralPath (Join-Path $ProfilePath 'prefs.js'))) { throw 'ProfilePath must contain prefs.js.' }
}
$cacheProfiles = @(Get-ZenProfileDirectories -AdditionalProfilePaths @($ProfilePath))
$cachePlan = @(Get-ZenCacheInvalidationPlan -ProfilePaths $cacheProfiles)
if ($Check) {
    [pscustomobject]@{ Version = $version; Archive = $target; Entry = $entryName; Patched = $source.Contains($marker); SHA256 = $originalHash; CacheProfiles = $cacheProfiles.Count; CacheInvalidationsPending = @($cachePlan | Where-Object Pending).Count }
    return
}
if ($RestoreBackup -and ($PrepareOnly -or $ConfigureExternalLinks)) { throw '-RestoreBackup cannot be combined with preparation or profile changes.' }
if (!$PrepareOnly) { Assert-ZenClosed }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

if ($RestoreBackup) {
    $RestoreBackup = (Resolve-Path -LiteralPath $RestoreBackup).ProviderPath
    $restoreZip = [IO.Compression.ZipFile]::OpenRead($RestoreBackup)
    try {
        $restoreEntry = $restoreZip.GetEntry($entryName)
        if (!$restoreEntry -or (Read-Entry $restoreEntry).Contains($marker)) { throw 'Not an unpatched backup containing this handler.' }
    } finally { $restoreZip.Dispose() }
    # Only allow the exact original associated with the installed candidate.
    $backupHash = Get-Hash $RestoreBackup
    $manifestPath = Join-Path $OutputDirectory ("patch-$backupHash.json")
    if (!(Test-Path -LiteralPath $manifestPath)) { throw 'Matching patch manifest missing. Use the original artifacts directory with -OutputDirectory.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.SourceSHA256 -ne $backupHash -or $manifest.PatchedSHA256 -ne $originalHash -or $manifest.Version -ne $version) {
        throw 'Backup does not match this patched build. Refusing to restore an older version over a Zen update.'
    }
    Install-Archive $RestoreBackup $target $originalHash
    Invoke-ZenCacheInvalidation -Plan $cachePlan -OutputDirectory $OutputDirectory -BeforeWrite ${function:Assert-ZenClosed} | ForEach-Object {
        Write-Output "Browser code cache: $($_.Status) ($($_.ProfilePath))"
    }
    Write-Output "Restored $target"
    return
}

# Validate the external-link destination before doing any installed writes.
$profileFile = $null
if ($ConfigureExternalLinks) {
    if (!$ProfilePath) { throw '-ConfigureExternalLinks requires an explicit -ProfilePath (the Root Directory shown in about:profiles).' }
    $ProfilePath = (Resolve-Path -LiteralPath $ProfilePath).ProviderPath
    if (!(Test-Path -LiteralPath (Join-Path $ProfilePath 'prefs.js'))) { throw 'ProfilePath must contain prefs.js.' }
    $profileFile = Join-Path $ProfilePath 'user.js'
}

if ($source.Contains($marker)) {
    Write-Output "Already patched: $target"
} else {
    # Match the complete known fallback. A changed upstream handler requires review.
    $anchor = @'
    } else if (!cmdLine.preventDefault) {
      if (
        AppConstants.platform == "win" &&
        cmdLine.state != Ci.nsICommandLine.STATE_INITIAL_LAUNCH &&
        lazy.WindowsUIUtils.inWin10TabletMode
'@
    $normalized = $source.Replace("`r`n", "`n")
    $anchor = $anchor.Replace("`r`n", "`n")
    if ([regex]::Matches($normalized, [regex]::Escape($anchor)).Count -ne 1) {
        throw 'Unsupported handler layout. No installed files changed; review the new Zen source before updating this patch.'
    }
    if ($normalized -notmatch '\bgKiosk\b' -or $normalized -notmatch '\bpermanentPrivateBrowsing\b') { throw 'Required handler APIs missing; refusing to patch.' }
    $insertion = @'
    } else if (!cmdLine.preventDefault) {
      // zen-reuse-window patch v1 (MPL-2.0)
      if (
        cmdLine.state != Ci.nsICommandLine.STATE_INITIAL_LAUNCH &&
        cmdLine.length == 0 &&
        !gKiosk &&
        Services.prefs.getBoolPref("zen.window-reuse-on-launch", true)
      ) {
        let win = lazy.BrowserWindowTracker.getTopWindow({
          private: lazy.PrivateBrowsingUtils.permanentPrivateBrowsing,
          allowFromInactiveWorkspace: true,
        });
        if (win) {
          if (win.windowState == win.STATE_MINIMIZED) {
            win.restore();
          }
          win.focus();
          return;
        }
      }
      if (
        AppConstants.platform == "win" &&
        cmdLine.state != Ci.nsICommandLine.STATE_INITIAL_LAUNCH &&
        lazy.WindowsUIUtils.inWin10TabletMode
'@
    $patched = $normalized.Replace($anchor, $insertion.Replace("`r`n", "`n"))
    if ($source.Contains("`r`n")) { $patched = $patched.Replace("`n", "`r`n") }
    $candidate = Join-Path $OutputDirectory ("omni.patched.$originalHash.ja")
    $backup = Join-Path $OutputDirectory ("omni.original.$originalHash.ja")
    Save-Backup $target $backup
    $stage = Join-Path $OutputDirectory ('build-' + [guid]::NewGuid().ToString('N') + '.ja')
    $inputZip = [IO.Compression.ZipFile]::OpenRead($backup)
    $outputZip = [IO.Compression.ZipFile]::Open($stage, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($entry in $inputZip.Entries) {
            if (!$names.Add($entry.FullName)) { throw "Duplicate ZIP entry: $($entry.FullName)" }
            $copy = $outputZip.CreateEntry($entry.FullName, [IO.Compression.CompressionLevel]::Optimal)
            $copy.LastWriteTime = $entry.LastWriteTime
            $copy.ExternalAttributes = $entry.ExternalAttributes
            $outStream = $copy.Open()
            try {
                if ($entry.FullName -eq $entryName) {
                    $bytes = $utf8.GetBytes($patched)
                    $outStream.Write($bytes, 0, $bytes.Length)
                } else {
                    $inStream = $entry.Open()
                    try { $inStream.CopyTo($outStream) } finally { $inStream.Dispose() }
                }
            } finally { $outStream.Dispose() }
        }
    } finally { $outputZip.Dispose(); $inputZip.Dispose() }
    $oldZip = [IO.Compression.ZipFile]::OpenRead($backup)
    $newZip = [IO.Compression.ZipFile]::OpenRead($stage)
    try {
        if ($oldZip.Entries.Count -ne $newZip.Entries.Count) { throw 'Archive entry count mismatch.' }
        foreach ($entry in $oldZip.Entries) {
            $newEntry = $newZip.GetEntry($entry.FullName)
            if (!$newEntry) { throw "Missing ZIP entry: $($entry.FullName)" }
            if ($entry.FullName -eq $entryName) {
                if ((Read-Entry $newEntry) -cne $patched) { throw 'Patched handler verification failed.' }
            } elseif ((Get-EntryHash $entry) -cne (Get-EntryHash $newEntry)) {
                throw "Content changed unexpectedly: $($entry.FullName)"
            }
        }
    } finally { $newZip.Dispose(); $oldZip.Dispose() }
    Move-Item -LiteralPath $stage -Destination $candidate -Force
    $manifest = [ordered]@{ Version = $version; Archive = $target; Entry = $entryName; SourceSHA256 = $originalHash; PatchedSHA256 = (Get-Hash $candidate); Backup = $backup; Candidate = $candidate; EntriesVerified = $names.Count; PreparedUTC = [DateTime]::UtcNow.ToString('o') }
    [IO.File]::WriteAllText((Join-Path $OutputDirectory "patch-$originalHash.json"), ($manifest | ConvertTo-Json), $utf8)
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'BrowserContentHandler.original.sys.mjs'), $source, $utf8)
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'BrowserContentHandler.patched.sys.mjs'), $patched, $utf8)
    Write-Output "Verified $($names.Count) entries. Backup: $backup"
    if ($PrepareOnly) { Write-Output "Prepared only: $candidate" } else {
        Install-Archive $candidate $target $originalHash
        Write-Output "Installed: $target"
    }
}

if ($ConfigureExternalLinks) {
    $begin = '// BEGIN zen-reuse-window external links'
    $end = '// END zen-reuse-window external links'
    $existing = if (Test-Path -LiteralPath $profileFile) { [IO.File]::ReadAllText($profileFile, $utf8) } else { '' }
    $managed = @'
// BEGIN zen-reuse-window external links
user_pref("browser.link.open_newwindow.override.external", 3);
user_pref("widget.prefer_windows_on_current_virtual_desktop", false);
user_pref("browser.tabs.loadDivertedInBackground", false);
// END zen-reuse-window external links
'@
    $pattern = '(?ms)^' + [regex]::Escape($begin) + '\r?\n.*?^' + [regex]::Escape($end) + '(?:\r?\n)?'
    if (($existing.Contains($begin) -or $existing.Contains($end)) -and [regex]::Matches($existing, $pattern).Count -ne 1) {
        throw 'Malformed or repeated managed preferences block; user.js left unchanged.'
    }
    $updated = [regex]::Replace($existing, $pattern, '').TrimEnd() + "`r`n" + $managed.Replace("`r`n", "`n").Replace("`n", "`r`n") + "`r`n"
    if ($PrepareOnly) {
        [IO.File]::WriteAllText((Join-Path $OutputDirectory 'user.js.preview'), $updated, $utf8)
        Write-Output 'External-link user.js preview prepared; profile unchanged.'
    } else {
        Assert-ZenClosed
        if (Test-Path -LiteralPath $profileFile) {
            Save-Backup $profileFile (Join-Path $OutputDirectory ('user.js.original.' + (Get-Hash $profileFile)))
        }
        [IO.File]::WriteAllText($profileFile, $updated, $utf8)
        Write-Output "Configured external links in $profileFile"
    }
}
Invoke-ZenCacheInvalidation -Plan $cachePlan -OutputDirectory $OutputDirectory -PrepareOnly:$PrepareOnly -BeforeWrite ${function:Assert-ZenClosed} | ForEach-Object {
    Write-Output "Browser code cache: $($_.Status) ($($_.ProfilePath))"
}
if (!$cacheProfiles.Count) {
    Write-Warning 'No initialized Zen profiles were found. For an existing portable/custom profile, rerun with -ProfilePath pointing to its root directory, or launch Zen once with -purgecaches after fully exiting it.'
}
if ($PrepareOnly) {
    Write-Output 'Preparation complete; the installation and profiles are unchanged.'
} else {
    Write-Output 'The browser code cache will refresh on the next normal launch. Updates can replace the patch; rerun this script after closing Zen.'
}
