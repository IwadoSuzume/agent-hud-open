# Progress

Read this first when resuming (TASK.md, top). Update after every step.

## Status

- **Current milestone:** M4 — Providers (review round 2; M5 hooks in the worktree `wt5`)
- **Branch:** `windows-port`, pushed to the fork `IwadoSuzume/agent-hud-open` (created 2026-10-16 for CI; upstream
  `jazzenchen/agent-hud-open` is never pushed to, no PR is opened).
- **Spike branch:** `spike-m0` (commit `809e047`, local only): the full spike, Core + tests building and running on
  Windows. Milestones M1–M5 re-apply it in reviewed steps; do not merge it.
- **Last approved tag:** `port-M3-approved` (`da470d9`); earlier `port-M2-approved` (`887c949`), `port-M1-approved` (`ffc8dba`), `port-M0-approved` (`990426e`)

## Milestones

| Milestone | State | Start commit | Approved tag | Notes |
| --- | --- | --- | --- | --- |
| M0 Reconnaissance & decisions | approved 2026-10-16 | `c258093` (upstream main) | `port-M0-approved` (`990426e`) | round 1: tests ALL_PASS (G1 run 38969577715 success, G6 pass); review CHANGES_REQUESTED (4 blocking, all doc gaps) → fixed |
| M1 Windows CI skeleton | approved 2026-10-16 | `703ae2e` | `port-M1-approved` (`ffc8dba`) | round 1: tests ALL_PASS (Windows run 38982139136, macOS run 38982141982), review APPROVE |
| M2 Support cross-platform | approved 2026-10-17 | `ffc8dba` | `port-M2-approved` (`887c949`) | round 1: tests ALL_PASS (Windows run 39000065894, macOS run 39000074546: 2086 XCTest + 10 swift-testing incl. `portableDigestsEqualCryptoKit`), review APPROVE |
| M3 Core platform layer | approved 2026-10-17 | `08bbc4a` | `port-M3-approved` (`da470d9`) | round 3 (`da470d9`): tests ALL_PASS (Windows run 39006576859: Core 1310 executed, 1301 passed, 9 skipped, 0 failed; macOS run 39006577913: 2086 XCTest + 10 swift-testing; local G2 warnings equal the baseline; D-006 holds), review APPROVE (3 non-blocking: an 8.3 short-path SessionProject case, D-032 wording, test.ps1 header — done on the M4 branch; the tester's 3 G8 doc notes fixed with the approval). Round 2 (`dd38fc8`): tests FAILURES (Windows run 39005191736: the D-032 retry built on attempt 2, then 4 tests failed on the runner only — the built-in Administrator's SID written as SDDL's `LA`, the runner's 8.3 `RUNNER~1` temporary path), macOS run 39005199779 success, review CHANGES_REQUESTED (that failure only) → test helpers compare the SDDL alias and resolve the fixture's final path; test.ps1's `-Filter` batch fixed and its retry limited to a file in use; WindowsFoldersTests' warnings fixed; D-021/D-033 notes. Round 1 (`c8dca6e`): tests FAILURES (Windows run 39003222984 failed in Swift Build's bundle Touch before any test ran; D-006 broken by one line of `InstanceLock.swift`; 9 warnings over the baseline), macOS run 39003224306 success, review CHANGES_REQUESTED (the same 2 blocking) → fixed: D-032 build-first, D-006 restored and exempted, port warnings fixed and upstream-line warnings baselined (D-033), plus the review's non-blocking items (pipe acceptor logs and reports a stop, header CR/LF refused, pipe key owner checked, PlatformGapsTests) |
| M4 Providers | review (round 2) | `469bc44` | — | round 1 (`c1d64a0`): tests ALL_PASS (Windows run 39028601296: Core 1350 executed, 1346 passed, 4 skipped; macOS run 39028601964: 2086 XCTest + 10 swift-testing; local warnings equal the baseline), review CHANGES_REQUESTED (4 blocking: PlatformSupport gated only `isInstalled`; macOS-only home folders still read on Windows; the D-019 test could not fail; four Windows places without a source) → fixed in `848ca5b` and the round-2 commit (D-036 revised, SUPPORT_MATRIX, 14 registered skips for the absent clients); non-blocking: package access, build.ps1 without swift, fake engine out of packages, test warnings, this file. Before review: Windows run 39028057775 on `696284b` failed in a cold release build (Swift Build Touch race) → `scripts/windows/build.ps1` (D-032) |
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

1. M4 review round 2 on `469bc44...HEAD` (the round-1 fixes are `848ca5b` and the commit after it): CI on the head
   (Windows push run + `Source checks` dispatch), port-tester (`reports/M4-tests-2.md`), port-reviewer; then tag
   `port-M4-approved`. The M4 work is on `windows-port` itself now (branch `m4-work` in the worktree
   `%LOCALAPPDATA%\agenthud-dev\wt` is the same commits).
2. M5 (hooks & MCP) on branch `m5-work` in the worktree `%LOCALAPPDATA%\agenthud-dev\wt5` (scratch
   `%LOCALAPPDATA%\agenthud-dev\wt5build`), rebased on M4 as it moves. Done there (WIP commits): per-client Windows hook
   forms in `HookCommand+Windows.swift` with the `HookInstaller` seam (Claude Code and Qoder CLI exec form, Copilot CLI
   `exec`, Codex `%ComSpec% /C`, CodeBuddy Git Bash with a double-quoted forward-slash path, Qwen Code
   `"shell": "powershell"`; Cursor, Qoder CN, QoderWork, Antigravity, ZCode and WorkBuddy get no hook), `isTransient`
   on Windows (a zip's Explorer copy, removable/optical/RAM drives, shares), the refused path characters, ACL-keeping
   settings writes (`HookSettings+Windows.swift`, `ReplaceFileW`, D-023), `HookFormsWindowsTests` running each form
   through its client's shell, `TestHooks` so the shared hook tests read either form. Sources for D-037 (to write):
   Claude Code *Hooks* docs; GitHub *Copilot CLI hooks reference*; Qoder *CLI hooks* (exec form, Windows caveats);
   openai/codex `codex-rs/hooks/src/engine/command_runner.rs` @ `ce0323f`; CodeBuddy *Hooks reference* (Git Bash
   enforced); QwenLM/qwen-code `hookRunner.ts`, `utils/shell-utils.ts` @ `fa02030`; measured: Git Bash's runtime
   splits `'…'\''…'` from a Windows command line. To do: gate Qoder CN/QoderWork, D-037 text, the hook engine
   executable (`agenthud-engine.exe`, console subsystem), MCP stdio and named-pipe channel tests
   (MCPAppChannelTests, PermissionHookTests on pipes), MCPToolsOff Windows variants, the observer's WinHTTP WebSocket,
   end-to-end tests with a temporary `USERPROFILE`/`APPDATA`.

## Known issues / TODO

- Spike test failures to fix are listed in PORTING_PLAN.md §8.
- An empty folder `E:\src` is left from the first junction (the tools may not remove a drive's top-level folder).
- Non-blocking review items from M0 round 1 are folded into DECISIONS.md (D-006…D-023) and PORTING_PLAN.md rows;
  the code changes they call for are in M3–M6.
