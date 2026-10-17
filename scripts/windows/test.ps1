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
    # One batch: the filters and the skips together (the comma makes the whole list a single element).
    $batches = @(, (@($Filter | ForEach-Object { @('--filter', $_) }) + $skips))
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
    # Runs swift with the arguments, writing its output to the console and the log; its exit status is left in
    # $script:code (a function's return value would collect the output too), and $script:busy says whether it reported
    # a file another process held.
    function Invoke-Swift([string[]] $arguments) {
        $script:busy = $false
        & swift @arguments 2>&1 | ForEach-Object {
            $line = "$_"
            Write-Host $line
            if ($line -match 'being used by another process') { $script:busy = $true }
            if ($Log) { Add-Content -LiteralPath $Log -Value $line -Encoding utf8 }
        }
        $script:code = $LASTEXITCODE
    }
    # The tests are built once, before any batch runs. Swift Build on Windows can fail to touch a test bundle whose
    # Info.plist another of its tasks still holds open ("being used by another process", DECISIONS.md D-032): only then
    # is the build tried again, up to three times in all, and no test runs without one.
    $build = @('build', '--build-tests') + $(if ($ScratchPath) { @('--scratch-path', $ScratchPath) } else { @() })
    $status = 1
    foreach ($attempt in 1..3) {
        Invoke-Swift $build
        $status = $script:code
        if ($status -eq 0 -or -not $script:busy) { break }
        Write-Host "swift build --build-tests hit a file in use (attempt $attempt of 3)"
    }
    if ($status -eq 0) {
        foreach ($batch in $batches) {
            Invoke-Swift ($common + @('--skip-build') + $batch)
            if ($script:code -ne 0) { $status = $script:code }
        }
    }
} finally {
    $env:APPDATA = $realRoaming
    $env:LOCALAPPDATA = $realLocal
    Pop-Location
    & (Join-Path $here 'remove-test-preferences.ps1') -Since $started
    Remove-Item -Recurse -Force $profileRoot -ErrorAction SilentlyContinue
}
exit $status
