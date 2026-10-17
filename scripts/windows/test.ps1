<#
.SYNOPSIS
  Runs the Swift tests on Windows the way gate G3 asks (docs/windows-port/PROGRESS.md).

.DESCRIPTION
  - APPDATA and LOCALAPPDATA point at a fresh temporary profile, so the code under test keeps its files there
    (DECISIONS.md D-021);
  - the tests in skipped-tests.txt are skipped, each registered in SKIPPED_TESTS.md;
  - afterwards the preference files swift-corelibs-foundation writes into the real %LOCALAPPDATA% for the tests'
    UserDefaults suites are removed (remove-test-preferences.ps1).
  Output goes to -Log as well as the console; the exit status is swift test's.

.EXAMPLE
  scripts\windows\test.ps1 -ScratchPath "$env:LOCALAPPDATA\agenthud-dev\build" -Log "$env:TEMP\g3.log"
#>
param(
    [string] $ScratchPath = "",
    [string] $Log = "",
    [string[]] $Filter = @()
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
$started = (Get-Date).AddSeconds(-1)

$realLocal = $env:LOCALAPPDATA
$realRoaming = $env:APPDATA
$profileRoot = Join-Path ([IO.Path]::GetTempPath()) ("agenthud-testprofile-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $profileRoot 'Roaming'), (Join-Path $profileRoot 'Local') | Out-Null

$common = @('test')
if ($ScratchPath) { $common += @('--scratch-path', $ScratchPath) }
$skips = @()
foreach ($pattern in Get-Content (Join-Path $here 'skipped-tests.txt')) {
    $pattern = $pattern.Trim()
    if ($pattern -and -not $pattern.StartsWith('#')) { $skips += @('--skip', $pattern) }
}
# With --skip, swift test names every selected test on the runner's command line, which on Windows must stay under
# 32,767 characters: the Core tests run in batches by the first letters of their classes (Support's have no skips).
if ($Filter.Count -gt 0) {
    $batches = @(, ($Filter | ForEach-Object { @('--filter', $_) }) + $skips)
} else {
    $batches = @(, @('--filter', 'AgentHUDSupportTests'))
    foreach ($letters in '[AB]', 'C[a-n]', 'C[o-z]', '[D-H]', '[I-O]', 'P[a-h]', 'P[i-z]', '[Q-T]', '[U-Z]') {
        $batches += , (@('--filter', "AgentHUDCoreTests\.$letters") + $skips)
    }
}

Push-Location $root
try {
    $env:APPDATA = Join-Path $profileRoot 'Roaming'
    $env:LOCALAPPDATA = Join-Path $profileRoot 'Local'
    # swift writes its progress to standard error, which Windows PowerShell would otherwise turn into a stopping error.
    $ErrorActionPreference = 'Continue'
    if ($Log) { Set-Content -LiteralPath $Log -Value '' -Encoding utf8 }
    $status = 0
    $first = $true
    foreach ($batch in $batches) {
        # The first batch builds; the others reuse its build.
        $arguments = $common + $(if ($first) { @() } else { @('--skip-build') }) + $batch
        $first = $false
        if ($Log) {
            & swift @arguments 2>&1 | ForEach-Object {
                $line = "$_"
                $line
                Add-Content -LiteralPath $Log -Value $line -Encoding utf8
            }
        } else {
            & swift @arguments
        }
        if ($LASTEXITCODE -ne 0) { $status = $LASTEXITCODE }
    }
} finally {
    $env:APPDATA = $realRoaming
    $env:LOCALAPPDATA = $realLocal
    Pop-Location
    & (Join-Path $here 'remove-test-preferences.ps1') -Since $started
    Remove-Item -Recurse -Force $profileRoot -ErrorAction SilentlyContinue
}
exit $status
