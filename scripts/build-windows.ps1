<#
.SYNOPSIS
  Builds the Windows portable package of Agent HUD Open in one command (docs/windows-port, TASK.md M8, D-055).

.DESCRIPTION
  1. Builds from an ASCII path (D-007): a repository whose path is not ASCII is reached through the per-user junction
     %LOCALAPPDATA%\agenthud-dev\src, made here when it does not exist.
  2. The engine: `swift build -c release --product agenthud-engine` through scripts\windows\build.ps1 (D-032). Swift
     must be on PATH (docs/windows-port/PROGRESS.md, Gates), and its toolchain must be the one RUNTIME_NOTICES.txt
     names (6.4.1).
  3. The shell: `dotnet publish windows\AgentHUD -c Release -r win-x64 --self-contained false`: it runs on the
     machine's .NET 10 Desktop Runtime, which Windows keeps up to date (D-055).
  4. The folder `Agent HUD Open`: the shell, agenthud-engine.exe, the Swift runtime libraries the engine loads (copied
     unchanged from the toolchain's runtime folder, the folder on PATH that holds swiftCore.dll), LICENSE.txt,
     THIRD_PARTY_NOTICES.txt, RUNTIME_NOTICES.txt, README.txt and the package marker 'agenthud-package.json'.
     The Microsoft Visual C++ runtime is not copied: Microsoft asks for its central install (D-055).
  5. The zip AgentHUD-Open-<version>-windows-x64.zip in -Out: entries in ordinal name order, with forward slashes and
     the source commit's time, so the same commit and toolchain give the same entries.
  Then scripts\windows\check-package.ps1 checks the zip, unless -NoCheck. Nothing is signed and nothing is published.

.EXAMPLE
  scripts\build-windows.ps1
  scripts\build-windows.ps1 -Out C:\temp\hud -ScratchPath C:\temp\hud-build
#>
param(
    [string] $Out = "",
    [string] $ScratchPath = "",
    [switch] $NoCheck
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'

function Get-FullPath([string] $path) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path) }

# The version is the macOS app's (scripts/build-app.sh), the one place the project names it.
$appScript = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts\build-app.sh')
if ($appScript -notmatch 'CFBundleShortVersionString</key><string>([0-9][0-9A-Za-z.\-]*)</string>') {
    throw 'no CFBundleShortVersionString in scripts/build-app.sh'
}
$version = $Matches[1]
$runtimeVersion = '6.4.1'

# 1. An ASCII path to build from.
$buildRoot = $root
if ($root -match '[^\x00-\x7F]') {
    $junction = Join-Path $env:LOCALAPPDATA 'agenthud-dev\src'
    if ($junction -match '[^\x00-\x7F]') { throw "the repository and $junction are not ASCII paths; clone the repository to an ASCII path (D-007)" }
    if (Test-Path -LiteralPath $junction) {
        $target = @((Get-Item -LiteralPath $junction).Target)[0]
        if (-not $target -or $target.TrimEnd('\') -ne $root.TrimEnd('\')) { throw "$junction exists and does not lead to $root" }
    } else {
        New-Item -ItemType Directory -Force (Split-Path -Parent $junction) | Out-Null
        New-Item -ItemType Junction -Path $junction -Target $root | Out-Null
    }
    $buildRoot = $junction
    if (-not $ScratchPath) { $ScratchPath = Join-Path $env:LOCALAPPDATA 'agenthud-dev\package-build' }
}
if (-not $ScratchPath) { $ScratchPath = Join-Path $buildRoot '.build' }
if (-not $Out) { $Out = Join-Path $root 'build\windows' }
$Out = Get-FullPath $Out
$ScratchPath = Get-FullPath $ScratchPath

# 2. The engine.
if (-not (Get-Command swift -ErrorAction SilentlyContinue)) { throw 'swift is not on PATH (docs/windows-port/PROGRESS.md, Gates)' }
$swiftVersion = (& swift --version 2>&1 | Out-String)
if ($swiftVersion -notmatch [regex]::Escape("Swift version $runtimeVersion")) {
    throw "RUNTIME_NOTICES.txt names Swift $runtimeVersion's runtime; this toolchain is: $($swiftVersion.Trim())"
}
& (Join-Path $root 'scripts\windows\build.ps1') -c release --product agenthud-engine --package-path $buildRoot --scratch-path $ScratchPath
if ($LASTEXITCODE -ne 0) { throw "swift build failed with $LASTEXITCODE" }
$binPath = (& swift build -c release --package-path $buildRoot --scratch-path $ScratchPath --show-bin-path 2>$null | Select-Object -Last 1).Trim()
$engine = Join-Path $binPath 'agenthud-engine.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw "no agenthud-engine.exe in $binPath" }

$runtime = $env:Path.Split(';') | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'swiftCore.dll')) } | Select-Object -First 1
if (-not $runtime) { throw 'no folder on PATH holds swiftCore.dll (the Swift runtime)' }
# What agenthud-engine.exe loads from the Swift runtime, directly or through another of these (measured with
# `dumpbin /dependents`, D-055); check-package.ps1 starts the engine with no Swift folder on PATH to prove the list.
$runtimeLibraries = @(
    '_FoundationICU.dll', 'BlocksRuntime.dll', 'dispatch.dll', 'Foundation.dll', 'FoundationEssentials.dll',
    'FoundationInternationalization.dll', 'FoundationNetworking.dll', 'swift_Concurrency.dll', 'swift_RegexParser.dll',
    'swift_StringProcessing.dll', 'swiftCore.dll', 'swiftCRT.dll', 'swiftDispatch.dll', 'swiftObservation.dll',
    'swiftSynchronization.dll', 'swiftWinSDK.dll')

# 3. The shell.
$publish = Join-Path $Out 'publish'
if (Test-Path -LiteralPath $publish) { Remove-Item -Recurse -Force -LiteralPath $publish }
& dotnet publish (Join-Path $buildRoot 'windows\AgentHUD\AgentHUD.csproj') -c Release -r win-x64 --self-contained false `
    "-p:Version=$version" -p:DebugType=None -p:DebugSymbols=false -o $publish
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with $LASTEXITCODE" }

# 4. The folder.
$stage = Join-Path $Out 'Agent HUD Open'
if (Test-Path -LiteralPath $stage) { Remove-Item -Recurse -Force -LiteralPath $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item -Path (Join-Path $publish '*') -Destination $stage -Recurse
Copy-Item -LiteralPath $engine -Destination $stage
foreach ($library in $runtimeLibraries) {
    $file = Join-Path $runtime $library
    if (-not (Test-Path -LiteralPath $file)) { throw "the Swift runtime in $runtime has no $library" }
    Copy-Item -LiteralPath $file -Destination $stage
}
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $stage 'LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $root 'THIRD_PARTY_NOTICES.txt') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'windows\packaging\RUNTIME_NOTICES.txt') -Destination $stage
Copy-Item -LiteralPath (Join-Path $root 'windows\packaging\README.txt') -Destination $stage

$commit = 'unknown'; $commitTime = [DateTimeOffset]::new(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
if (Get-Command git -ErrorAction SilentlyContinue) {
    $head = (& git -C $root rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $head) {
        $commit = "$head".Trim()
        $commitTime = [DateTimeOffset]::Parse("$(& git -C $root log -1 --format=%cI HEAD)".Trim(), [Globalization.CultureInfo]::InvariantCulture)
    }
}
# The marker launch at login looks for (AgentHUD.Shell.Package.MarkerFileName): only a packaged copy registers itself.
$marker = [ordered]@{ name = 'Agent HUD Open'; version = $version; commit = $commit; runtime = 'win-x64'; swift = $runtimeVersion }
[IO.File]::WriteAllText((Join-Path $stage 'agenthud-package.json'), ($marker | ConvertTo-Json) + "`n", (New-Object Text.UTF8Encoding $false))

# 5. The zip.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zipPath = Join-Path $Out "AgentHUD-Open-$version-windows-x64.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -Force -LiteralPath $zipPath }
$files = [string[]]@(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object { $_.FullName })
[Array]::Sort($files, [StringComparer]::Ordinal)
$zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $name = 'Agent HUD Open/' + $file.Substring($stage.Length + 1).Replace('\', '/')
        $entry = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $commitTime
        $source = [IO.File]::OpenRead($file)
        $output = $entry.Open()
        try { $source.CopyTo($output) } finally { $output.Dispose(); $source.Dispose() }
    }
} finally { $zip.Dispose() }

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash
$megabytes = [Math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)
Write-Host "Package: $zipPath ($megabytes MB, $($files.Count) files, SHA-256 $hash)"

if (-not $NoCheck) {
    & (Join-Path $root 'scripts\windows\check-package.ps1') -Zip $zipPath
    if ($LASTEXITCODE -ne 0) { throw "check-package.ps1 failed with $LASTEXITCODE" }
}
