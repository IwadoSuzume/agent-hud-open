# Progress

Read this first when resuming (TASK.md, top). Update after every step.

## Status

- **Current milestone:** M0 — reconnaissance and decisions (review round 2)
- **Branch:** `windows-port`, pushed to the fork `IwadoSuzume/agent-hud-open` (created 2026-10-16 for CI; upstream
  `jazzenchen/agent-hud-open` is never pushed to, no PR is opened).
- **Spike branch:** `spike-m0` (commit `809e047`, local only): the full spike, Core + tests building and running on
  Windows. Milestones M1–M5 re-apply it in reviewed steps; do not merge it.
- **Last approved tag:** none yet

## Milestones

| Milestone | State | Start commit | Approved tag | Notes |
| --- | --- | --- | --- | --- |
| M0 Reconnaissance & decisions | review 2 | `c258093` (upstream main) | — | round 1: tests ALL_PASS (G1 run 38969577715 success, G6 pass); review CHANGES_REQUESTED (4 blocking, all doc gaps) → fixed |
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
  GitHub is driven through its REST API with git's stored credential, never printed or written.
- The repository is at `E:\桌面项目\agent-hud-open` (non-ASCII). **Build through the per-user junction
  `%LOCALAPPDATA%\agenthud-dev\src`** with `--scratch-path %LOCALAPPDATA%\agenthud-dev\build` (D-007).
  `core.autocrlf=false` locally (the user's global setting is `true`).

## Gates — exact commands

Windows environment for every Swift command (PowerShell); tests run in a temporary profile (D-021):

```powershell
$env:Path = "$env:LOCALAPPDATA\Programs\Swift\Toolchains\6.4.1+Asserts\usr\bin;$env:LOCALAPPDATA\Programs\Swift\Runtimes\6.4.1\usr\bin;" + $env:Path
$env:SDKROOT = "$env:LOCALAPPDATA\Programs\Swift\Platforms\6.4.1\Windows.platform\Developer\SDKs\Windows.sdk\"
$build = "$env:LOCALAPPDATA\agenthud-dev\build"
Set-Location "$env:LOCALAPPDATA\agenthud-dev\src"
# for tests only:
$profile = "$env:LOCALAPPDATA\agenthud-dev\testprofile"; Remove-Item -Recurse -Force $profile -ErrorAction SilentlyContinue
New-Item -ItemType Directory "$profile\Roaming", "$profile\Local" | Out-Null
$env:APPDATA = "$profile\Roaming"; $env:LOCALAPPDATA_REAL = $env:LOCALAPPDATA; $env:LOCALAPPDATA = "$profile\Local"
```

`swift test` prints its results only when it ends (~2 min for Core); redirect it from `cmd /c "… > log 2>&1"`, because
PowerShell's `*>` holds everything until the process exits too.

| Gate | Command | Applies |
| --- | --- | --- |
| G1 macOS | GitHub Actions `Source checks` (`ci.yml`) dispatched on `windows-port` in the fork (`POST /repos/IwadoSuzume/agent-hud-open/actions/workflows/ci.yml/dispatches {"ref":"windows-port"}`), read with `GET /repos/IwadoSuzume/agent-hud-open/actions/runs?branch=windows-port&event=workflow_dispatch`; jobs `test`, `app`, `macos` must be `success` for the milestone's head commit | every milestone (M0: run 38969577715 on `d28f59d`, success) |
| G2 Windows build | `swift build -c release --scratch-path $build` (warnings compared with the baseline below); `dotnet build windows\AgentHUD.sln -c Release` from M7; the `Windows port` workflow (`windows.yml`) | M1 (CI), M2+ |
| G3 Windows tests | `swift test --scratch-path $build` in the temporary profile; every exclusion and runtime skip in SKIPPED_TESTS.md | M2 (Support), M3+ (Core) |
| G4 determinism | `RecordCodingGoldenTests` (Support), on Windows and in the macOS CI | M2+ |
| G5 UI | `dotnet test windows\AgentHUD.Tests`; snapshot smoke test | M7+ |
| G6 boundaries | `python scripts\check-source-boundaries.py` | every milestone |

Warning baseline (Swift 6.4.1 toolchain and SDK, not the port's): `WinSDK.swiftmodule … reference to type 'wchar_t'
broken by a context change` (repeated per compile job); `'strerror' is deprecated` in `MCP/MCPStdio.swift` (shared
code, Windows CRT only).

## Next steps

1. Round 2 of M0: port-tester (G1 on the new head, G6, G8) and port-reviewer; then tag `port-M0-approved`.
2. M1: Windows branch of `Package.swift` (Support only), `.github/workflows/windows.yml` (drafted, untracked).

## Known issues / TODO

- Spike test failures to fix are listed in PORTING_PLAN.md §8.
- An empty folder `E:\src` is left from the first junction (the tools may not remove a drive's top-level folder).
- Non-blocking review items from M0 round 1 are folded into DECISIONS.md (D-006…D-023) and PORTING_PLAN.md rows;
  the code changes they call for are in M3–M6.
