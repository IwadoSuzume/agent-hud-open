<#
.SYNOPSIS
  Gate G5 (docs/windows-port/PROGRESS.md): builds windows\AgentHUD.sln in Release with warnings as errors and runs its
  tests, with every telemetry switch of the .NET CLI and the testing platform off (DECISIONS.md D-042), then checks the
  protocol fixtures against their schema (scripts\windows\check-protocol.py).

.EXAMPLE
  scripts\windows\test-dotnet.ps1
#>
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:TESTINGPLATFORM_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'

& dotnet test (Join-Path $root 'windows\AgentHUD.sln') -c Release
if ($LASTEXITCODE -ne 0) { throw "dotnet test failed with $LASTEXITCODE" }

& python (Join-Path $root 'scripts\windows\check-protocol.py')
if ($LASTEXITCODE -ne 0) { throw "check-protocol.py failed with $LASTEXITCODE" }
