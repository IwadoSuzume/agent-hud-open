# Progress

Read this first when resuming (TASK.md, top). Update after every step.

## Status

- **Current milestone:** M5 — Hooks & MCP (review round 2). M4 closed after four rounds **without approval**: its last
  review found two untested Windows implementations (BLOCKERS.md B-001); their tests land at the start of M5's range.
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
| M4 Providers | **not approved** (4 rounds, B-001) 2026-10-18 | `469bc44` | — (closed at `4cdf931`) | round 4 (`4cdf931`): tests ALL_PASS (`reports/M4-tests-4.md`: Windows run 39047601254 and local both 1343 executed, 1339 passed, 4 skipped, 0 failed; macOS run 39047601576: 2086 XCTest + 10 swift-testing, all 31 Windows-skipped tests pass on macOS; warnings equal the baseline), review CHANGES_REQUESTED (`reports/M4-review-4.md`: rounds 1–3 all fixed; 2 new BLOCKING — no Windows test of the WinHTTP transport or of Credential Manager → B-001, fixed in M5's range). Round 3 (`76ec0e2`, review only — its tester was cut off by a rate limit; covered by round 4's tests; CI on `cda1fca` green): review CHANGES_REQUESTED (the Grok Bot quota check could not fail) → `4cdf931`. Round 2 (`0bdab94`): tests FAILURES (`reports/M4-tests-2.md`: the driveless-path test on CI's `D:`; 8 unnamed skip-list entries), review CHANGES_REQUESTED (counterparts that test the gates) → `76ec0e2`. Round 1 (`c1d64a0`): tests ALL_PASS (Windows run 39028601296, macOS run 39028601964), review CHANGES_REQUESTED (4 blocking: PlatformSupport gated only `isInstalled`; macOS-only home folders read on Windows; the D-019 test could not fail; four Windows places without a source) → `848ca5b`, `8509b17` (D-036 revised, SUPPORT_MATRIX, registered skips). Before review: run 39028057775 on `696284b` failed in a cold release build (Swift Build Touch race) → `scripts/windows/build.ps1` (D-032) |
| M5 Hooks & MCP | review (round 2) | `505492b` (M4's close) | — | round 1 (`c369f8d`): tests FAILURES (`reports/M5-tests-1.md`: Windows run 39102050084 1425 run, 1420 passed, 4 skipped, 1 failed — Claude's ancestry test under the runner's 8.3 `RUNNER~1` temporary folder; macOS run 39102050317 1 failure in the upstream Desktop test `StatsWindowLifecycleTests.testNativeRestoreFitsContentUpdatedWhileMiniaturized`, no Desktop change in the port; local test.ps1 1421/0), review CHANGES_REQUESTED (`reports/M5-review-1.md`: BLOCKING — a failed `ReplaceFileW` could delete the only copy of a settings file) → round 2: backup and restore, long paths, both spellings in ancestry, WebSocket calls under the cancel lock, `WindowsHTTP.rules`, hook-form sources with URLs, skip register, 8.3 temporary folders, DeepSeek npm roots injectable, macOS quoting pinned |
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

1. M5 review round 2 on `505492b...HEAD` (M5's start is M4's close commit): push `windows-port`, CI (Windows push run +
   `Source checks` dispatch), port-tester (`reports/M5-tests-2.md`), port-reviewer (`reports/M5-review-2.md`); then tag
   `port-M5-approved` and close B-001. M5 was developed on `m5-work` in `%LOCALAPPDATA%\agenthud-dev\wt5` (scratch
   `wt5build`; runner `wt5.cmd <log> <swift args>` in the session scratchpad sets the toolchain and a temporary profile)
   and merged into `windows-port`.
2. M6 (engine & UI protocol) after M5's approval.

## Known issues / TODO

- `FileChangeMonitorWindowsTests.testAWatchedDirectoryThatGoesAwayAsksForAFullScan` failed once in a local G3 run
  (2026-10-17, M4 round 3) while three other builds and a tester's G3 ran on the machine; it passed 3 of 3 alone and
  has not failed in CI. Watch for it; its `eventually` wait is the place to look.

- Spike test failures to fix are listed in PORTING_PLAN.md §8.
- An empty folder `E:\src` is left from the first junction (the tools may not remove a drive's top-level folder).
- The MCP server's `instructions` (Core text) say the HUD shows "at the Mac's notch"; the Windows build serves the same
  words. Platform-aware product text belongs to M6/M7 (the UI's strings come from Core).
- The real `%TEMP%` grows by about 50 folders per G3 run (M4's `ProviderEnginesWindowsTests`, upstream fixtures,
  swift-corelibs' `TemporaryDirectory.*`; M5's fixtures leave nothing): clean up in M9 or give test.ps1 its own TEMP.
- Cursor's `AdditionalSource.isInstalled` on Windows checks the real `%APPDATA%` database (M4 review round 4,
  non-blocking): no test reads it today; make the database injectable when one does.
- Non-blocking review items from M0 round 1 are folded into DECISIONS.md (D-006…D-023) and PORTING_PLAN.md rows;
  the code changes they call for are in M3–M6.
