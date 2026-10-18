<#
.SYNOPSIS
  Gate G5's smoke test (docs/windows-port/PROGRESS.md): the Windows shell started with the engine's demo data draws the
  island at rest, open with its requests, and as the usage panel into PNG files (`AgentHUD --snapshot`), and ends with
  status 0 within 30 seconds.

.DESCRIPTION
  Builds windows\AgentHUD in Release (warnings as errors), runs it against -Engine in a temporary profile (the demo
  writes only its own settings.demo.json, D-021), and checks snapshot.txt: each picture present, not blank, and of a
  plausible size. Telemetry is off as in test-dotnet.ps1 (D-042).

.EXAMPLE
  scripts\windows\smoke-shell.ps1 -Engine "$env:LOCALAPPDATA\agenthud-dev\build\out\Products\Release-windows-x86_64\agenthud-engine.exe"
#>
param(
    [Parameter(Mandatory = $true)] [string] $Engine,
    [string] $Out = ""
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:TESTINGPLATFORM_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'

if (-not (Test-Path -LiteralPath $Engine)) { throw "no engine at $Engine" }
& dotnet build (Join-Path $root 'windows\AgentHUD\AgentHUD.csproj') -c Release
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed with $LASTEXITCODE" }
$shell = Join-Path $root 'windows\AgentHUD\bin\Release\net10.0-windows\AgentHUD.exe'

if (-not $Out) { $Out = Join-Path ([IO.Path]::GetTempPath()) ("agenthud-snapshot-" + [Guid]::NewGuid().ToString('N')) }
$profileRoot = Join-Path ([IO.Path]::GetTempPath()) ("agenthud-smokeprofile-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $profileRoot 'Roaming'), (Join-Path $profileRoot 'Local') | Out-Null
$realRoaming = $env:APPDATA; $realLocal = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $profileRoot 'Roaming'
    $env:LOCALAPPDATA = Join-Path $profileRoot 'Local'
    $started = Get-Date
    $process = Start-Process -FilePath $shell -PassThru -ArgumentList @('--snapshot', "`"$Out`"", '--engine', "`"$Engine`"", '--language', 'en')
    if (-not $process.WaitForExit(30000)) {
        Stop-Process -Id $process.Id -Force
        throw 'the shell did not end within 30 s'
    }
    $seconds = [int]((Get-Date) - $started).TotalSeconds
    if ($process.ExitCode -ne 0) { throw "the shell ended with status $($process.ExitCode)" }
} finally {
    $env:APPDATA = $realRoaming; $env:LOCALAPPDATA = $realLocal
    Remove-Item -Recurse -Force $profileRoot -ErrorAction SilentlyContinue
}

# Each picture: present, drawn, at least as large as the island's least extent at 2x, at most a display's.
$expected = @{ 'island-rest' = @(120, 40); 'island-open' = @(600, 200); 'island-usage' = @(600, 400) }
$report = Get-Content -LiteralPath (Join-Path $Out 'snapshot.txt')
$failures = @()
foreach ($name in $expected.Keys) {
    $line = $report | Where-Object { $_ -like "$name *" }
    if (-not $line) { $failures += "$name missing"; continue }
    if ($line -notmatch '^\S+ (\d+)x(\d+)$') { $failures += "$name $($line.Split(' ', 2)[1])"; continue }
    $width = [int]$Matches[1]; $height = [int]$Matches[2]
    if ($width -lt $expected[$name][0] -or $height -lt $expected[$name][1] -or $width -gt 4000 -or $height -gt 8000) {
        $failures += "$name ${width}x$height is not a plausible size"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Out "$name.png"))) { $failures += "$name.png missing" }
}
if ($failures) { throw ("snapshot: " + ($failures -join '; ')) }
Write-Host "Shell smoke test: $($expected.Count) pictures in $Out, status 0 after $seconds s."
