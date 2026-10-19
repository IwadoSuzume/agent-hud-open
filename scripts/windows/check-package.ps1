<#
.SYNOPSIS
  Checks the Windows portable package (scripts\build-windows.ps1, D-055): its files, its notices, and that what it
  holds runs on its own.

.DESCRIPTION
  Unpacks -Zip into a temporary folder and checks:
  - every entry is under `Agent HUD Open/`, named with forward slashes, and the folder holds exactly the expected files
    (no symbols, no test assemblies, nothing left over);
  - LICENSE.txt, THIRD_PARTY_NOTICES.txt and RUNTIME_NOTICES.txt are the repository's files byte for byte, and the
    notices are also the macOS bundle's copy;
  - agenthud-package.json names the zip's version;
  - agenthud-engine.exe loads with no Swift folder on PATH (status 2, "no command given"; Windows' 0xC0000135 means a
    library is missing);
  - the packaged shell draws the smoke test's pictures against the packaged engine, again with no Swift folder on PATH
    (smoke-shell.ps1 -Shell), unless -NoShell.

.EXAMPLE
  scripts\windows\check-package.ps1 -Zip build\windows\AgentHUD-Open-0.5.4-windows-x64.zip
#>
param(
    [Parameter(Mandatory = $true)] [string] $Zip,
    [switch] $NoShell
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Zip = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Zip)
if (-not (Test-Path -LiteralPath $Zip)) { throw "no package at $Zip" }
if ((Split-Path -Leaf $Zip) -notmatch '^AgentHUD-Open-(.+)-windows-x64\.zip$') { throw "unexpected package name $(Split-Path -Leaf $Zip)" }
$version = $Matches[1]

$expected = @(
    # The shell (dotnet publish, framework-dependent).
    'AgentHUD.exe', 'AgentHUD.dll', 'AgentHUD.deps.json', 'AgentHUD.runtimeconfig.json', 'AgentHUD.Protocol.dll',
    'AgentHUD.Shell.dll',
    # The engine and the Swift runtime it loads.
    'agenthud-engine.exe', '_FoundationICU.dll', 'BlocksRuntime.dll', 'dispatch.dll', 'Foundation.dll',
    'FoundationEssentials.dll', 'FoundationInternationalization.dll', 'FoundationNetworking.dll', 'swift_Concurrency.dll',
    'swift_RegexParser.dll', 'swift_StringProcessing.dll', 'swiftCore.dll', 'swiftCRT.dll', 'swiftDispatch.dll',
    'swiftObservation.dll', 'swiftSynchronization.dll', 'swiftWinSDK.dll',
    # Licence, notices, the package's own files.
    'LICENSE.txt', 'THIRD_PARTY_NOTICES.txt', 'RUNTIME_NOTICES.txt', 'README.txt', 'agenthud-package.json')

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$failures = @()
$archive = [IO.Compression.ZipFile]::OpenRead($Zip)
try {
    $names = @($archive.Entries | ForEach-Object { $_.FullName })
} finally { $archive.Dispose() }
foreach ($name in $names) {
    if ($name.Contains('\')) { $failures += "entry $name has a backslash" }
    if (-not $name.StartsWith('Agent HUD Open/', [StringComparison]::Ordinal)) { $failures += "entry $name is outside 'Agent HUD Open/'" }
}
$inFolder = @($names | ForEach-Object { $_.Substring('Agent HUD Open/'.Length) })
foreach ($file in $expected) { if ($inFolder -cnotcontains $file) { $failures += "$file missing" } }
foreach ($file in $inFolder) { if ($expected -cnotcontains $file) { $failures += "$file is not a file of the package" } }

$unpacked = Join-Path ([IO.Path]::GetTempPath()) ("agenthud-package-" + [Guid]::NewGuid().ToString('N'))
try {
    [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $unpacked)
    $folder = Join-Path $unpacked 'Agent HUD Open'

    function Same([string] $a, [string] $b) {
        (Test-Path -LiteralPath $a) -and (Test-Path -LiteralPath $b) -and
            ((Get-FileHash -LiteralPath $a).Hash -eq (Get-FileHash -LiteralPath $b).Hash)
    }
    if (-not (Same (Join-Path $folder 'LICENSE.txt') (Join-Path $root 'LICENSE'))) { $failures += 'LICENSE.txt is not LICENSE' }
    if (-not (Same (Join-Path $folder 'THIRD_PARTY_NOTICES.txt') (Join-Path $root 'THIRD_PARTY_NOTICES.txt'))) { $failures += 'THIRD_PARTY_NOTICES.txt differs from the repository' }
    if (-not (Same (Join-Path $root 'THIRD_PARTY_NOTICES.txt') (Join-Path $root 'Sources\AgentHUDDesktop\Resources\THIRD_PARTY_NOTICES.txt'))) { $failures += 'the root and bundled THIRD_PARTY_NOTICES.txt differ' }
    if (-not (Same (Join-Path $folder 'RUNTIME_NOTICES.txt') (Join-Path $root 'windows\packaging\RUNTIME_NOTICES.txt'))) { $failures += 'RUNTIME_NOTICES.txt differs from windows\packaging' }

    $markerFile = Join-Path $folder 'agenthud-package.json'
    if (Test-Path -LiteralPath $markerFile) {
        $marker = Get-Content -Raw -LiteralPath $markerFile | ConvertFrom-Json
        if ($marker.version -ne $version) { $failures += "agenthud-package.json says $($marker.version), the zip $version" }
    }

    # No Swift folder on PATH: what the engine loads must come from the package (or from Windows itself).
    $systemRoot = $env:SystemRoot
    $bare = "$systemRoot\System32;$systemRoot"
    $engine = Join-Path $folder 'agenthud-engine.exe'
    if (Test-Path -LiteralPath $engine) {
        $start = New-Object Diagnostics.ProcessStartInfo $engine
        $start.UseShellExecute = $false
        $start.RedirectStandardError = $true
        $start.RedirectStandardOutput = $true
        $start.CreateNoWindow = $true
        $start.EnvironmentVariables['Path'] = $bare
        $process = [Diagnostics.Process]::Start($start)
        # Both streams are read in the background, so that a hung engine is stopped by the 30 s bound below.
        $errorText = $process.StandardError.ReadToEndAsync()
        $outputText = $process.StandardOutput.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); $failures += 'the packaged engine did not end within 30 s' }
        else {
            $process.WaitForExit()  # the streams' end, once the process is gone
            $complaint = $errorText.Result
            if ($process.ExitCode -eq -1073741515) { $failures += 'the packaged engine is missing a library (0xC0000135)' }
            elseif ($process.ExitCode -ne 2) { $failures += "the packaged engine ended with $($process.ExitCode), not 2: $($complaint.Trim())" }
        }
    }

    if (-not $failures -and -not $NoShell) {
        $realPath = $env:Path
        try {
            $env:Path = $bare
            & (Join-Path $PSScriptRoot 'smoke-shell.ps1') -Shell (Join-Path $folder 'AgentHUD.exe') -Engine $engine
        } catch {
            $failures += "the packaged shell's smoke test: $($_.Exception.Message)"
        } finally { $env:Path = $realPath }
    }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $unpacked -ErrorAction SilentlyContinue
}

if ($failures) {
    Write-Host ("Package check failed:`n  " + ($failures -join "`n  "))
    exit 1
}
Write-Host "Package check: $($expected.Count) files, notices as in the repository, the engine and the shell run from the package alone."
exit 0
