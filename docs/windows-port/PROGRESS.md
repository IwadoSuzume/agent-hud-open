# Progress

Read this first when resuming (TASK.md, top). Update after every step.

## Status

- **Current milestone:** M0 — reconnaissance and decisions (in review)
- **Branch:** `windows-port` (pushed to the fork `IwadoSuzume/agent-hud-open`; upstream is never pushed to)
- **Spike branch:** `spike-m0` (commit `809e047`): the full spike, Core + tests building and running on Windows.
  Milestones M1–M3 re-apply it in reviewed steps; do not merge it.
- **Last approved tag:** none yet

## Milestones

| Milestone | State | Start commit | Approved tag | Notes |
| --- | --- | --- | --- | --- |
| M0 Reconnaissance & decisions | review | `c258093` (upstream main) | — | PORTING_PLAN, ADR-001…004, DECISIONS, agents |
| M1 Windows CI skeleton | todo | | | |
| M2 Support cross-platform | todo | | | |
| M3 Core platform layer | todo | | | |
| M4 Providers | todo | | | |
| M5 Hooks & MCP | todo | | | |
| M6 Engine & UI protocol | todo | | | |
| M7 Windows UI shell | todo | | | |
| M8 Packaging | todo | | | |
| M9 Wrap-up | todo | | | |

## Environment (this machine)

- Windows 11 Pro 10.0.26200 x64, not elevated. Visual Studio 2022 Build Tools (VC x64/ARM64, Windows 11 SDK
  22621) and Swift 6.4.1 (`Swift.Toolchain`, per-user, `%LOCALAPPDATA%\Programs\Swift`) installed by winget on
  2026-10-16; .NET SDK 10.0.401; Python 3.13 as `python` (`python3` is the Store stub); Git for Windows; no `gh` —
  GitHub is driven through its REST API with git's stored credential (never printed or written).
- The repository is at `E:\桌面项目\agent-hud-open` (non-ASCII). **Build through the junction `E:\src\ahud`** with
  `--scratch-path E:\src\ahud-build` (D-007). `core.autocrlf=false` locally (the user's global setting is `true`).

## Gates — exact commands

Swift environment for every Windows command (PowerShell):

```powershell
$env:Path = "$env:LOCALAPPDATA\Programs\Swift\Toolchains\6.4.1+Asserts\usr\bin;$env:LOCALAPPDATA\Programs\Swift\Runtimes\6.4.1\usr\bin;" + $env:Path
$env:SDKROOT = "$env:LOCALAPPDATA\Programs\Swift\Platforms\6.4.1\Windows.platform\Developer\SDKs\Windows.sdk\"
Set-Location E:\src\ahud
```

| Gate | Command | Applies from |
| --- | --- | --- |
| G1 macOS | GitHub Actions workflow `Source checks` (`ci.yml`) dispatched on `windows-port` in the fork; read with `GET /repos/IwadoSuzume/agent-hud-open/actions/runs?branch=windows-port&event=workflow_dispatch` (jobs `test`, `app`, `macos` must be `success`) | M1 |
| G2 Windows build | `swift build -c release --scratch-path E:\src\ahud-build` (warnings compared with the baseline below); `dotnet build windows\AgentHUD.sln -c Release` from M7; CI `windows.yml` | M1 |
| G3 Windows tests | `swift test --scratch-path E:\src\ahud-build` (≈2 min; output appears at the end — redirect with `cmd /c "… > log 2>&1"`, PowerShell's `*>` buffers it all); every skipped/excluded test in SKIPPED_TESTS.md | M2 (Support), M3 (Core) |
| G4 determinism | `swift test --filter PortableDigestTests` and `RecordCodingGoldenTests`, on Windows and in the macOS CI | M2 |
| G5 UI | `dotnet test windows\AgentHUD.Tests`; snapshot smoke test (M7) | M7 |
| G6 boundaries | `python scripts\check-source-boundaries.py` | M0 |

Warning baseline (Swift 6.4.1 toolchain, not ours): `WinSDK.swiftmodule … reference to type 'wchar_t' broken by a
context change` (repeated per compile job).

## Next steps

1. Run port-tester (G6 only for M0) and port-reviewer on `c258093...HEAD`; fix; tag `port-M0-approved`.
2. M1: fork, enable Actions, add `windows.yml`, dispatch `ci.yml` for the macOS baseline.

## Known issues / TODO

- Spike test failures to fix are listed in PORTING_PLAN.md §8.
