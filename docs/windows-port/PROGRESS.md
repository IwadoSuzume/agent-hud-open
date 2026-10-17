# Progress

Read this first when resuming (TASK.md, top). Update after every step.

## Status

- **Current milestone:** M3 — Core platform layer (in review)
- **Branch:** `windows-port`, pushed to the fork `IwadoSuzume/agent-hud-open` (created 2026-10-16 for CI; upstream
  `jazzenchen/agent-hud-open` is never pushed to, no PR is opened).
- **Spike branch:** `spike-m0` (commit `809e047`, local only): the full spike, Core + tests building and running on
  Windows. Milestones M1–M5 re-apply it in reviewed steps; do not merge it.
- **Last approved tag:** `port-M2-approved` (`887c949`); earlier `port-M1-approved` (`ffc8dba`), `port-M0-approved` (`990426e`)

## Milestones

| Milestone | State | Start commit | Approved tag | Notes |
| --- | --- | --- | --- | --- |
| M0 Reconnaissance & decisions | approved 2026-10-16 | `c258093` (upstream main) | `port-M0-approved` (`990426e`) | round 1: tests ALL_PASS (G1 run 38969577715 success, G6 pass); review CHANGES_REQUESTED (4 blocking, all doc gaps) → fixed |
| M1 Windows CI skeleton | approved 2026-10-16 | `703ae2e` | `port-M1-approved` (`ffc8dba`) | round 1: tests ALL_PASS (Windows run 38982139136, macOS run 38982141982), review APPROVE |
| M2 Support cross-platform | approved 2026-10-17 | `ffc8dba` | `port-M2-approved` (`887c949`) | round 1: tests ALL_PASS (Windows run 39000065894, macOS run 39000074546: 2086 XCTest + 10 swift-testing incl. `portableDigestsEqualCryptoKit`), review APPROVE |
| M3 Core platform layer | review (round 2) | `08bbc4a` | — | round 1 (`c8dca6e`): tests FAILURES (Windows run 39003222984 failed in Swift Build's bundle Touch before any test ran; D-006 broken by one line of `InstanceLock.swift`; 9 warnings over the baseline), macOS run 39003224306 success, review CHANGES_REQUESTED (the same 2 blocking) → fixed: D-032 build-first, D-006 restored and exempted, port warnings fixed and upstream-line warnings baselined (D-033), plus the review's non-blocking items (pipe acceptor logs and reports a stop, header CR/LF refused, pipe key owner checked, PlatformGapsTests) |
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
$testProfile = "$env:LOCALAPPDATA\agenthud-dev\testprofile"; Remove-Item -Recurse -Force $testProfile -ErrorAction SilentlyContinue
New-Item -ItemType Directory "$testProfile\Roaming", "$testProfile\Local" | Out-Null
$env:APPDATA = "$testProfile\Roaming"; $env:LOCALAPPDATA_REAL = $env:LOCALAPPDATA; $env:LOCALAPPDATA = "$testProfile\Local"
```

`swift test` prints its results only when it ends (~2 min for Core); redirect it from `cmd /c "… > log 2>&1"`, because
PowerShell's `*>` holds everything until the process exits too.

| Gate | Command | Applies |
| --- | --- | --- |
| G1 macOS | GitHub Actions `Source checks` (`ci.yml`) dispatched on `windows-port` in the fork (`POST /repos/IwadoSuzume/agent-hud-open/actions/workflows/ci.yml/dispatches {"ref":"windows-port"}`), read with `GET /repos/IwadoSuzume/agent-hud-open/actions/runs?branch=windows-port&event=workflow_dispatch`; jobs `test`, `app`, `macos` must be `success` for the milestone's head commit | every milestone (runs listed in the milestone table) |
| G2 Windows build | `swift build -c release --scratch-path $build` (warnings compared with the baseline below); `dotnet build windows\AgentHUD.sln -c Release` from M7; the `Windows port` workflow (`windows.yml`) | M1 (CI), M2+ |
| G3 Windows tests | `scripts\windows\test.ps1 -ScratchPath $build -Log $env:TEMP\g3.log` (temporary profile, registered skips, batches, preference cleanup); every exclusion, listed skip and runtime skip in SKIPPED_TESTS.md | M2 (Support), M3+ (Core) |
| G4 determinism | `RecordCodingGoldenTests` (Support), on Windows and in the macOS CI | M2+ |
| G5 UI | `dotnet test windows\AgentHUD.Tests`; snapshot smoke test | M7+ |
| G6 boundaries | `python scripts\check-source-boundaries.py` | every milestone |

Warning baseline (Swift 6.4.1 toolchain and SDK, not the port's): `WinSDK.swiftmodule … reference to type 'wchar_t'
broken by a context change` (repeated per compile job). Upstream lines the port did not change, Windows only
(D-033): `'strerror' is deprecated` in `MCP/MCPStdio.swift`; `'close' is deprecated` in
`Hooks/Permission/PermissionHookClient.swift` and `Providers/Kit/Zstandard/ZstandardReader.swift`; `'init(cString:)' is
deprecated` in `Providers/Antigravity/AntigravityCLI.swift`; `result of call to 'wait(until:)' is unused` in
`Providers/Codex/CodexDesktopStream.swift`; `no 'async' operations occur within 'await' expression` in
`Hooks/Permission/DeepSeekQuestions.swift`. Anything else is a new warning.

## Next steps (resume here)

1. M3 review round 2 on `08bbc4a...HEAD` (the round-1 fixes): port-tester and port-reviewer; a green Windows run is
   required; then tag `port-M3-approved`.
2. M4 (providers): SUPPORT_MATRIX research per client; D-019 executables/PATH; a scripted fake-engine executable for
   the Claude/Codex/Antigravity/MCP-client tests; Windows locators; DeepSeek observer test server on Winsock; Copilot
   `hostsFile` on Windows; then remove their entries from `skipped-tests.txt`.
3. M4 work in progress in the worktree `%LOCALAPPDATA%\agenthud-dev\wt`, branch `m4-work` (from `c8dca6e`; rebase it
   on `windows-port` once M3 is approved): `Executables` on Windows (D-019 central filter), `WindowsCodex` npm engine
   places, the fake engine `Tests/WindowsFakeEngine` with `Tests/AgentHUDCoreTests/Support/TestEngine.swift`, the
   provider tests converted to it, `ProviderEnginesWindowsTests`.

## Known issues / TODO

- Spike test failures to fix are listed in PORTING_PLAN.md §8.
- An empty folder `E:\src` is left from the first junction (the tools may not remove a drive's top-level folder).
- Non-blocking review items from M0 round 1 are folded into DECISIONS.md (D-006…D-023) and PORTING_PLAN.md rows;
  the code changes they call for are in M3–M6.
