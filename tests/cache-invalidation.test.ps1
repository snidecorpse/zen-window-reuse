# SPDX-License-Identifier: MPL-2.0
# Fixture-only tests. Does not read or modify any real browser profile.
[CmdletBinding()]
param([Alias('HelperPath')][string]$FunctionsPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testsDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if (!$FunctionsPath) { $FunctionsPath = Join-Path $testsDirectory '..\Patch-ZenWindowReuse.ps1' }
$functionSource = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $FunctionsPath).ProviderPath)
$beginMarker = '# BEGIN CACHE INVALIDATION FUNCTIONS'
$endMarker = '# END CACHE INVALIDATION FUNCTIONS'
$begin = $functionSource.IndexOf($beginMarker, [StringComparison]::Ordinal)
$end = $functionSource.IndexOf($endMarker, [StringComparison]::Ordinal)
if ($begin -lt 0 -or $end -le $begin) { throw 'Cache function region missing from FunctionsPath.' }
. ([scriptblock]::Create($functionSource.Substring($begin + $beginMarker.Length, $end - $begin - $beginMarker.Length)))
$testRoot = Join-Path (Join-Path $testsDirectory '..\.work') ('cache-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$script:passed = 0
$utf8 = New-Object Text.UTF8Encoding($false, $true)
function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) { throw "$Message`nExpected: $Expected`nActual: $Actual" }
}
function Assert-True($Actual, [string]$Message) { if (!$Actual) { throw $Message } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:passed++
    Write-Output "PASS: $Name"
}
function New-FixtureProfile([string]$Name, [AllowNull()]$Compatibility, [Text.Encoding]$Encoding = $utf8) {
    $path = [IO.Path]::GetFullPath((Join-Path $testRoot $Name))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $path 'prefs.js'), '// fixture only', $utf8)
    if ($null -ne $Compatibility) { [IO.File]::WriteAllText((Join-Path $path 'compatibility.ini'), $Compatibility, $Encoding) }
    $path
}
function Get-FixtureHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

Test-Case 'discovers relative, absolute, and install-default profiles; deduplicates and excludes background tasks' {
    $root = Join-Path $testRoot 'metadata'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $alpha = New-FixtureProfile 'metadata\Profiles\alpha' "[Compatibility]`r`nLastVersion=1`r`n"
    $beta = New-FixtureProfile 'metadata\Profiles\beta' "[Compatibility]`r`nLastVersion=2`r`n"
    $absolute = New-FixtureProfile 'custom absolute profile' "[Compatibility]`r`nLastVersion=3`r`n"
    $installOnly = New-FixtureProfile 'install-only' "[Compatibility]`r`nLastVersion=4`r`n"
    $background = New-FixtureProfile 'metadata\background-task' "[Compatibility]`r`nLastVersion=5`r`n"
    $profiles = "[Profile0]`r`nName=Main`r`nIsRelative=1`r`nPath=Profiles/alpha`r`n[Profile1]`r`nName=Custom`r`nIsRelative=0`r`nPath=$absolute`r`n[InstallABC]`r`nDefault=Profiles/alpha`r`n[BackgroundTasksProfiles]`r`nMozillaBackgroundTask=background-task`r`n"
    $installs = "[ABC]`r`nDefault=Profiles/beta`r`n[DEF]`r`nDefault=$installOnly`r`n[GHI]`r`nDefault=missing-profile`r`n"
    [IO.File]::WriteAllText((Join-Path $root 'profiles.ini'), $profiles, $utf8)
    [IO.File]::WriteAllText((Join-Path $root 'installs.ini'), $installs, $utf8)
    $found = @(Get-ZenProfileDirectories -ProfileRoot $root -AdditionalProfilePaths @($alpha.ToUpperInvariant()))
    Assert-Equal $found.Count 4 'Should find four distinct regular profiles'
    foreach ($path in @($alpha, $beta, $absolute, $installOnly)) { Assert-True ($found -contains $path) "Missing profile $path" }
    Assert-True (!($found -contains $background)) 'Background task profile must be excluded'
}
Test-Case 'adds marker only inside Compatibility and preserves CRLF and every other byte of text' {
    $before = "[Other]`r`nInvalidateCaches=0`r`n[Compatibility]`r`nLastVersion=1`r`nLastOSABI=WINNT_x86_64-msvc`r`n[After]`r`nKey=value`r`n"
    $profile = New-FixtureProfile 'preserve' $before
    $plan = @(Get-ZenCacheInvalidationPlan @($profile))
    $expected = $before.Replace("[Compatibility]`r`n", "[Compatibility]`r`nInvalidateCaches=1`r`n")
    Assert-Equal $plan[0].UpdatedText $expected 'Only the cache marker should be inserted'
    Assert-True $plan[0].NeedsWrite 'New marker must need writing'
    Assert-True (!$plan[0].Pending) 'No marker was pending before preparation'
}
Test-Case 'updates an existing zero marker without changing unrelated sections or newline style' {
    $before = "[Compatibility]`nLastVersion=1`nInvalidateCaches = 0`n[Other]`nInvalidateCaches=0`n"
    $profile = New-FixtureProfile 'update-zero' $before
    $plan = @(Get-ZenCacheInvalidationPlan @($profile))
    Assert-Equal $plan[0].UpdatedText ($before.Replace('InvalidateCaches = 0', 'InvalidateCaches = 1')) 'Only existing value should change'
}
Test-Case 'prepare-only writes preview and leaves profile unchanged' {
    $profile = New-FixtureProfile 'preview' "[Compatibility]`r`nLastVersion=1`r`n"
    $file = Join-Path $profile 'compatibility.ini'
    $hash = Get-FixtureHash $file
    $plan = @(Get-ZenCacheInvalidationPlan @($profile))
    $result = @(Invoke-ZenCacheInvalidation -Plan $plan -OutputDirectory (Join-Path $testRoot 'preview-output') -PrepareOnly)
    Assert-Equal (Get-FixtureHash $file) $hash 'Preview changed profile'
    Assert-Equal $result[0].Status 'Previewed' 'Expected preview status'
    Assert-True ([IO.File]::ReadAllText($result[0].Preview).Contains('InvalidateCaches=1')) 'Preview lacks marker'
}
Test-Case 'apply backs up exact bytes, writes marker, and repeated preparation is idempotent' {
    $profile = New-FixtureProfile 'apply' "[Compatibility]`r`nLastVersion=1`r`n"
    $file = Join-Path $profile 'compatibility.ini'
    $before = Get-FixtureHash $file
    $plan = @(Get-ZenCacheInvalidationPlan @($profile))
    $result = @(Invoke-ZenCacheInvalidation -Plan $plan -OutputDirectory (Join-Path $testRoot 'apply-output'))
    Assert-Equal $result[0].Status 'Invalidated' 'Apply must invalidate'
    Assert-Equal (Get-FixtureHash $result[0].Backup) $before 'Backup must preserve exact original bytes'
    Assert-Equal ([IO.File]::ReadAllText($file)) $plan[0].UpdatedText 'Installed marker differs from planned text'
    $again = @(Get-ZenCacheInvalidationPlan @($profile))
    Assert-True $again[0].Pending 'Marker should be reported pending'
    Assert-True (!$again[0].NeedsWrite) 'Second run must require no write'
    $after = Get-FixtureHash $file
    $repeat = @(Invoke-ZenCacheInvalidation -Plan $again -OutputDirectory (Join-Path $testRoot 'apply-output'))
    Assert-Equal $repeat[0].Status 'AlreadyPending' 'Repeated run must be skipped'
    Assert-Equal (Get-FixtureHash $file) $after 'Idempotent invocation changed bytes'
}
Test-Case 'refuses a stale plan rather than clobbering a concurrent profile change' {
    $profile = New-FixtureProfile 'concurrent' "[Compatibility]`r`nLastVersion=1`r`n"
    $file = Join-Path $profile 'compatibility.ini'
    $plan = @(Get-ZenCacheInvalidationPlan @($profile))
    [IO.File]::AppendAllText($file, "; concurrent edit`r`n", $utf8)
    $current = Get-FixtureHash $file
    $threw = $false
    try { Invoke-ZenCacheInvalidation -Plan $plan -OutputDirectory (Join-Path $testRoot 'stale-output') | Out-Null } catch { $threw = $true }
    Assert-True $threw 'Stale plan should fail'
    Assert-Equal (Get-FixtureHash $file) $current 'Stale plan overwrote concurrent edit'
}
Test-Case 'new profile with no compatibility file needs no marker or file creation' {
    $profile = New-FixtureProfile 'new-profile' $null
    $plan = @(Get-ZenCacheInvalidationPlan @($profile))
    $result = @(Invoke-ZenCacheInvalidation -Plan $plan -OutputDirectory (Join-Path $testRoot 'new-output'))
    Assert-Equal $result[0].Status 'NoCompatibilityFile' 'New profile should be skipped'
    Assert-True (!(Test-Path -LiteralPath (Join-Path $profile 'compatibility.ini'))) 'Should not create compatibility.ini for a new profile'
}
Test-Case 'preserves UTF-8 BOM and UTF-16 encodings during replacement' {
    foreach ($encoding in @((New-Object Text.UTF8Encoding($true, $true)), [Text.Encoding]::Unicode, [Text.Encoding]::BigEndianUnicode)) {
        $name = 'encoding-' + $encoding.CodePage + '-' + $encoding.GetPreamble().Length
        $profile = New-FixtureProfile $name "[Compatibility]`r`nLastVersion=1`r`n" $encoding
        $plan = @(Get-ZenCacheInvalidationPlan @($profile))
        Invoke-ZenCacheInvalidation -Plan $plan -OutputDirectory (Join-Path $testRoot 'encoding-output') | Out-Null
        $actual = [IO.File]::ReadAllBytes((Join-Path $profile 'compatibility.ini'))
        $preamble = $encoding.GetPreamble()
        for ($index = 0; $index -lt $preamble.Length; $index++) { Assert-Equal $actual[$index] $preamble[$index] 'Encoding BOM changed' }
        Assert-True ([IO.File]::ReadAllText((Join-Path $profile 'compatibility.ini'), $encoding).Contains('InvalidateCaches=1')) 'Encoded marker missing'
    }
}
Test-Case 'handles a Compatibility header with no final newline' {
    $profile = New-FixtureProfile 'no-newline' '[Compatibility]'
    $plan = @(Get-ZenCacheInvalidationPlan @($profile))
    Assert-Equal $plan[0].UpdatedText "[Compatibility]`r`nInvalidateCaches=1`r`n" 'Header must be separated from appended key'
}
Test-Case 'refuses ambiguous duplicate Compatibility sections without changing files' {
    $profile = New-FixtureProfile 'ambiguous' "[Compatibility]`nLastVersion=1`n[Compatibility]`nLastVersion=2`n"
    $file = Join-Path $profile 'compatibility.ini'
    $before = Get-FixtureHash $file
    $threw = $false
    try { Get-ZenCacheInvalidationPlan @($profile) | Out-Null } catch { $threw = $true }
    Assert-True $threw 'Repeated sections must fail safely'
    Assert-Equal (Get-FixtureHash $file) $before 'Ambiguous file was modified'
}
Write-Output "PASS: $script:passed cache-invalidation cases. Fixture directory: $testRoot"
