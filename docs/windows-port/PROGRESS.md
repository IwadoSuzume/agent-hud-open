# Progress

Read this first when resuming (TASK.md, top). Update after every step.

## Status

- **Current milestone:** M6 — Engine & UI protocol (review round 1). M5 approved 2026-10-18 (`port-M5-approved`,
  `bb1ce7d`); M4 closed after four rounds without approval, its blocker B-001 closed by M5.
- **Branch:** `windows-port`, pushed to the fork `IwadoSuzume/agent-hud-open` (created 2026-10-16 for CI; upstream
  `jazzenchen/agent-hud-open` is never pushed to, no PR is opened).
- **Spike branch:** `spike-m0` (commit `809e047`, local only): the full spike, Core + tests building and running on
  Windows. Milestones M1–M5 re-apply it in reviewed steps; do not merge it.
- **Last approved tag:** `port-M5-approved` (`bb1ce7d`); earlier `port-M3-approved` (`da470d9`), `port-M2-approved` (`887c949`), `port-M1-approved` (`ffc8dba`), `port-M0-approved` (`990426e`)

## Milestones

| Milestone | State | Start commit | Approved tag | Notes |
| --- | --- | --- | --- | --- |
| M0 Reconnaissance & decisions | approved 2026-10-16 | `c258093` (upstream main) | `port-M0-approved` (`990426e`) | round 1: tests ALL_PASS (G1 run 38969577715 success, G6 pass); review CHANGES_REQUESTED (4 blocking, all doc gaps) → fixed |
| M1 Windows CI skeleton | approved 2026-10-16 | `703ae2e` | `port-M1-approved` (`ffc8dba`) | round 1: tests ALL_PASS (Windows run 38982139136, macOS run 38982141982), review APPROVE |
| M2 Support cross-platform | approved 2026-10-17 | `ffc8dba` | `port-M2-approved` (`887c949`) | round 1: tests ALL_PASS (Windows run 39000065894, macOS run 39000074546: 2086 XCTest + 10 swift-testing incl. `portableDigestsEqualCryptoKit`), review APPROVE |
| M3 Core platform layer | approved 2026-10-17 | `08bbc4a` | `port-M3-approved` (`da470d9`) | round 3 (`da470d9`): tests ALL_PASS (Windows run 39006576859: Core 1310 executed, 1301 passed, 9 skipped, 0 failed; macOS run 39006577913: 2086 XCTest + 10 swift-testing; local G2 warnings equal the baseline; D-006 holds), review APPROVE (3 non-blocking: an 8.3 short-path SessionProject case, D-032 wording, test.ps1 header — done on the M4 branch; the tester's 3 G8 doc notes fixed with the approval). Round 2 (`dd38fc8`): tests FAILURES (Windows run 39005191736: the D-032 retry built on attempt 2, then 4 tests failed on the runner only — the built-in Administrator's SID written as SDDL's `LA`, the runner's 8.3 `RUNNER~1` temporary path), macOS run 39005199779 success, review CHANGES_REQUESTED (that failure only) → test helpers compare the SDDL alias and resolve the fixture's final path; test.ps1's `-Filter` batch fixed and its retry limited to a file in use; WindowsFoldersTests' warnings fixed; D-021/D-033 notes. Round 1 (`c8dca6e`): tests FAILURES (Windows run 39003222984 failed in Swift Build's bundle Touch before any test ran; D-006 broken by one line of `InstanceLock.swift`; 9 warnings over the baseline), macOS run 39003224306 success, review CHANGES_REQUESTED (the same 2 blocking) → fixed: D-032 build-first, D-006 restored and exempted, port warnings fixed and upstream-line warnings baselined (D-033), plus the review's non-blocking items (pipe acceptor logs and reports a stop, header CR/LF refused, pipe key owner checked, PlatformGapsTests) |
| M4 Providers | **not approved** (4 rounds, B-001) 2026-10-18 | `469bc44` | — (closed at `4cdf931`) | round 4 (`4cdf931`): tests ALL_PASS (`reports/M4-tests-4.md`: Windows run 39047601254 and local both 1343 executed, 1339 passed, 4 skipped, 0 failed; macOS run 39047601576: 2086 XCTest + 10 swift-testing, all 31 Windows-skipped tests pass on macOS; warnings equal the baseline), review CHANGES_REQUESTED (`reports/M4-review-4.md`: rounds 1–3 all fixed; 2 new BLOCKING — no Windows test of the WinHTTP transport or of Credential Manager → B-001, fixed in M5's range). Round 3 (`76ec0e2`, review only — its tester was cut off by a rate limit; covered by round 4's tests; CI on `cda1fca` green): review CHANGES_REQUESTED (the Grok Bot quota check could not fail) → `4cdf931`. Round 2 (`0bdab94`): tests FAILURES (`reports/M4-tests-2.md`: the driveless-path test on CI's `D:`; 8 unnamed skip-list entries), review CHANGES_REQUESTED (counterparts that test the gates) → `76ec0e2`. Round 1 (`c1d64a0`): tests ALL_PASS (Windows run 39028601296, macOS run 39028601964), review CHANGES_REQUESTED (4 blocking: PlatformSupport gated only `isInstalled`; macOS-only home folders read on Windows; the D-019 test could not fail; four Windows places without a source) → `848ca5b`, `8509b17` (D-036 revised, SUPPORT_MATRIX, registered skips). Before review: run 39028057775 on `696284b` failed in a cold release build (Swift Build Touch race) → `scripts/windows/build.ps1` (D-032) |
| M5 Hooks & MCP | approved 2026-10-18 | `505492b` (M4's close) | `port-M5-approved` (`bb1ce7d`) | round 2 (`bb1ce7d`): tests ALL_PASS (`reports/M5-tests-2.md`: Windows run 39104084529 and local both 1430 executed, 1426 passed, 4 skipped, 0 failed, also under an 8.3 `TEMP`; macOS run 39104084904 green on attempt 2 after one `rerun-failed-jobs` — the upstream flaky test below; 2087 XCTest), review APPROVE (`reports/M5-review-2.md`, 9 non-blocking → M6 step 1). Round 1 (`c369f8d`): tests FAILURES (`reports/M5-tests-1.md`: Claude's ancestry under the runner's 8.3 `RUNNER~1`; the same upstream macOS flake), review CHANGES_REQUESTED (`reports/M5-review-1.md`: a failed `ReplaceFileW` could delete the only copy of a settings file) → round 2: backup and restore, long paths, long forms in ancestry, WebSocket calls under the cancel lock, `WindowsHTTP.rules`, hook-form sources with URLs, skip register, 8.3 `TEMP`, DeepSeek npm roots injectable, macOS quoting pinned |
| M6 Engine & UI protocol | review (round 1) | `0f51d89` (M5's approval) | — | local before review: G3 `test.ps1` 1445 executed, 1441 passed, 4 runtime skips, 0 failed; G5 `test-dotnet.ps1` 7/7 and 16 valid + 15 invalid fixtures; G2 warnings equal the baseline; G6 pass |
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
| G5 UI | `scripts\windows\test-dotnet.ps1` (`dotnet test windows\AgentHUD.sln -c Release`, warnings as errors, telemetry off, D-042; then `python scripts\windows\check-protocol.py`): the protocol's C# contract tests from M6; the shell's view-model tests and the `--demo` snapshot smoke test join from M7 | M6 (protocol), M7+ (UI) |
| G6 boundaries | `python scripts\check-source-boundaries.py` | every milestone |

Warning baseline (Swift 6.4.1 toolchain and SDK, not the port's): `WinSDK.swiftmodule … reference to type 'wchar_t'
broken by a context change` (repeated per compile job). Upstream lines the port did not change, Windows only
(D-033): `'strerror' is deprecated` in `MCP/MCPStdio.swift`; `'close' is deprecated` in
`Hooks/Permission/PermissionHookClient.swift` and `Providers/Kit/Zstandard/ZstandardReader.swift`; `'init(cString:)' is
deprecated` in `Providers/Antigravity/AntigravityCLI.swift`; `result of call to 'wait(until:)' is unused` in
`Providers/Codex/CodexDesktopStream.swift`; `no 'async' operations occur within 'await' expression` in
`Hooks/Permission/DeepSeekQuestions.swift`. Anything else is a new warning.

## Next steps (resume here)

1. M6 review round 1 on `0f51d89...HEAD`: push `windows-port`, CI (Windows push run + `Source checks` dispatch; G1's
   upstream flake: one `rerun-failed-jobs`), port-tester (`reports/M6-tests-1.md`, with G5 `scripts\windows\test-dotnet.ps1`
   now applying), port-reviewer (`reports/M6-review-1.md`); then tag `port-M6-approved`. M6 was developed on `m6-work`
   in `%LOCALAPPDATA%\agenthud-dev\wt6` (scratch `wt6build`, runner `wt6.cmd` in the session scratchpad).
   Done in M6: M5 round 2's review items; the protocol v1.0 (PROTOCOL.md, schema, fixtures, `ShellProtocol`,
   `ShellStrings`, `EngineServer`, `agenthud-engine --serve`), contract tests in Swift (`ShellProtocolTests`) and C#
   (`windows/AgentHUD.Protocol.Tests`), end-to-end tests of `--serve` (`EngineServeEndToEndTests`), the G5 script and
   CI step, the .NET package allowlist in the boundary check (D-041…D-043).
2. M7 (Windows UI shell, `windows/AgentHUD`, WPF on .NET 10, ADR-002) after M6's approval: it reads only the protocol;
   it needs, as they come, more `ShellStrings` keys (the alert wording, D-043), the agent-tools channel (D-043), and
   any panel field the projection lacks (an additive minor version).

## Known issues / TODO

- `FileChangeMonitorWindowsTests.testAWatchedDirectoryThatGoesAwayAsksForAFullScan` failed once in a local G3 run
  (2026-10-17, M4 round 3) while three other builds and a tester's G3 ran on the machine; it passed 3 of 3 alone and
  has not failed in CI. Watch for it; its `eventually` wait is the place to look.

- Spike test failures to fix are listed in PORTING_PLAN.md §8.
- An empty folder `E:\src` is left from the first junction (the tools may not remove a drive's top-level folder).
- The upstream macOS test `AgentHUDDesktopTests.StatsWindowLifecycleTests.testNativeRestoreFitsContentUpdatedWhileMiniaturized`
  is timing-dependent on the runner (failed on 39102050317 and attempt 1 of 39104084904 with 187 vs 480, 3.4–3.8 s;
  passes in about 1.7 s). The port changes no Desktop code: for G1, one `rerun-failed-jobs` of the failed job is the
  agreed response, and a second failure is a finding.
- swift-corelibs-foundation on Windows reports the local time zone as GMT (`TimeZone.current`, `Calendar.current`, a
  default `DateFormatter`; measured by the M6 round-1 tester on a UTC−4 machine, with or without `TZ`): a reset more
  than a day off is labelled in GMT ("Sun 13:00"). The engine should set `NSTimeZone.default` from the Windows zone at
  start (M7, with a test); the protocol fixtures are made in UTC on purpose and are not affected.
- The MCP server's `instructions` (Core text) say the HUD shows "at the Mac's notch"; the Windows build serves the same
  words. Platform-aware product text belongs to M6/M7 (the UI's strings come from Core).
- The real `%TEMP%` grows by about 50 folders per G3 run (M4's `ProviderEnginesWindowsTests`, upstream fixtures,
  swift-corelibs' `TemporaryDirectory.*`; M5's fixtures leave nothing): clean up in M9 or give test.ps1 its own TEMP.
- Cursor's `AdditionalSource.isInstalled` on Windows checks the real `%APPDATA%` database (M4 review round 4,
  non-blocking): no test reads it today; make the database injectable when one does.
- Non-blocking review items from M0 round 1 are folded into DECISIONS.md (D-006…D-023) and PORTING_PLAN.md rows;
  the code changes they call for are in M3–M6.
