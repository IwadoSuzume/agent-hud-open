# Progress

Read this first when resuming (TASK.md, top). Update after every step.

## Status

- **Current milestone:** M8 — Packaging. M7 approved 2026-10-19 (`port-M7-approved`, `e7bd816`); M6 approved 2026-10-18
  (`port-M6-approved`, `f531b63`); M5 approved 2026-10-18 (`port-M5-approved`, `bb1ce7d`); M4 closed after four rounds
  without approval, its blocker B-001 closed by M5.
- **Branch:** `windows-port`, pushed to the fork `IwadoSuzume/agent-hud-open` (created 2026-10-16 for CI; upstream
  `jazzenchen/agent-hud-open` is never pushed to, no PR is opened).
- **Spike branch:** `spike-m0` (commit `809e047`, local only): the full spike, Core + tests building and running on
  Windows. Milestones M1–M5 re-apply it in reviewed steps; do not merge it.
- **Last approved tag:** `port-M7-approved` (`e7bd816`); earlier `port-M6-approved` (`f531b63`), `port-M5-approved` (`bb1ce7d`), `port-M3-approved` (`da470d9`), `port-M2-approved` (`887c949`), `port-M1-approved` (`ffc8dba`), `port-M0-approved` (`990426e`)

## Milestones

| Milestone | State | Start commit | Approved tag | Notes |
| --- | --- | --- | --- | --- |
| M0 Reconnaissance & decisions | approved 2026-10-16 | `c258093` (upstream main) | `port-M0-approved` (`990426e`) | round 1: tests ALL_PASS (G1 run 38969577715 success, G6 pass); review CHANGES_REQUESTED (4 blocking, all doc gaps) → fixed |
| M1 Windows CI skeleton | approved 2026-10-16 | `703ae2e` | `port-M1-approved` (`ffc8dba`) | round 1: tests ALL_PASS (Windows run 38982139136, macOS run 38982141982), review APPROVE |
| M2 Support cross-platform | approved 2026-10-17 | `ffc8dba` | `port-M2-approved` (`887c949`) | round 1: tests ALL_PASS (Windows run 39000065894, macOS run 39000074546: 2086 XCTest + 10 swift-testing incl. `portableDigestsEqualCryptoKit`), review APPROVE |
| M3 Core platform layer | approved 2026-10-17 | `08bbc4a` | `port-M3-approved` (`da470d9`) | round 3 (`da470d9`): tests ALL_PASS (Windows run 39006576859: Core 1310 executed, 1301 passed, 9 skipped, 0 failed; macOS run 39006577913: 2086 XCTest + 10 swift-testing; local G2 warnings equal the baseline; D-006 holds), review APPROVE (3 non-blocking: an 8.3 short-path SessionProject case, D-032 wording, test.ps1 header — done on the M4 branch; the tester's 3 G8 doc notes fixed with the approval). Round 2 (`dd38fc8`): tests FAILURES (Windows run 39005191736: the D-032 retry built on attempt 2, then 4 tests failed on the runner only — the built-in Administrator's SID written as SDDL's `LA`, the runner's 8.3 `RUNNER~1` temporary path), macOS run 39005199779 success, review CHANGES_REQUESTED (that failure only) → test helpers compare the SDDL alias and resolve the fixture's final path; test.ps1's `-Filter` batch fixed and its retry limited to a file in use; WindowsFoldersTests' warnings fixed; D-021/D-033 notes. Round 1 (`c8dca6e`): tests FAILURES (Windows run 39003222984 failed in Swift Build's bundle Touch before any test ran; D-006 broken by one line of `InstanceLock.swift`; 9 warnings over the baseline), macOS run 39003224306 success, review CHANGES_REQUESTED (the same 2 blocking) → fixed: D-032 build-first, D-006 restored and exempted, port warnings fixed and upstream-line warnings baselined (D-033), plus the review's non-blocking items (pipe acceptor logs and reports a stop, header CR/LF refused, pipe key owner checked, PlatformGapsTests) |
| M4 Providers | **not approved** (4 rounds, B-001) 2026-10-18 | `469bc44` | — (closed at `4cdf931`) | round 4 (`4cdf931`): tests ALL_PASS (`reports/M4-tests-4.md`: Windows run 39047601254 and local both 1343 executed, 1339 passed, 4 skipped, 0 failed; macOS run 39047601576: 2086 XCTest + 10 swift-testing, all 31 Windows-skipped tests pass on macOS; warnings equal the baseline), review CHANGES_REQUESTED (`reports/M4-review-4.md`: rounds 1–3 all fixed; 2 new BLOCKING — no Windows test of the WinHTTP transport or of Credential Manager → B-001, fixed in M5's range). Round 3 (`76ec0e2`, review only — its tester was cut off by a rate limit; covered by round 4's tests; CI on `cda1fca` green): review CHANGES_REQUESTED (the Grok Bot quota check could not fail) → `4cdf931`. Round 2 (`0bdab94`): tests FAILURES (`reports/M4-tests-2.md`: the driveless-path test on CI's `D:`; 8 unnamed skip-list entries), review CHANGES_REQUESTED (counterparts that test the gates) → `76ec0e2`. Round 1 (`c1d64a0`): tests ALL_PASS (Windows run 39028601296, macOS run 39028601964), review CHANGES_REQUESTED (4 blocking: PlatformSupport gated only `isInstalled`; macOS-only home folders read on Windows; the D-019 test could not fail; four Windows places without a source) → `848ca5b`, `8509b17` (D-036 revised, SUPPORT_MATRIX, registered skips). Before review: run 39028057775 on `696284b` failed in a cold release build (Swift Build Touch race) → `scripts/windows/build.ps1` (D-032) |
| M5 Hooks & MCP | approved 2026-10-18 | `505492b` (M4's close) | `port-M5-approved` (`bb1ce7d`) | round 2 (`bb1ce7d`): tests ALL_PASS (`reports/M5-tests-2.md`: Windows run 39104084529 and local both 1430 executed, 1426 passed, 4 skipped, 0 failed, also under an 8.3 `TEMP`; macOS run 39104084904 green on attempt 2 after one `rerun-failed-jobs` — the upstream flaky test below; 2087 XCTest), review APPROVE (`reports/M5-review-2.md`, 9 non-blocking → M6 step 1). Round 1 (`c369f8d`): tests FAILURES (`reports/M5-tests-1.md`: Claude's ancestry under the runner's 8.3 `RUNNER~1`; the same upstream macOS flake), review CHANGES_REQUESTED (`reports/M5-review-1.md`: a failed `ReplaceFileW` could delete the only copy of a settings file) → round 2: backup and restore, long paths, long forms in ancestry, WebSocket calls under the cancel lock, `WindowsHTTP.rules`, hook-form sources with URLs, skip register, 8.3 `TEMP`, DeepSeek npm roots injectable, macOS quoting pinned |
| M6 Engine & UI protocol | approved 2026-10-18 | `0f51d89` (M5's approval) | `port-M6-approved` (`f531b63`) | round 3 (`f531b63`): tests ALL_PASS (`reports/M6-tests-3.md`: Windows run 39164570245 and local both 1451 executed, 1447 passed, 4 skipped, 0 failed, 65/65 of 7 classes also under an 8.3 `TEMP`; G5 11/11 C#, 19 valid and 15 invalid fixtures; macOS run 39164577291 green on attempt 1, 2087 XCTest + 10 swift-testing; warnings equal the baseline), review APPROVE (`reports/M6-review-3.md`, 10 non-blocking → M7 step 1). Round 2 (`9d00cc2`): tests not filed (the session ended before the tester's report; Windows run 39116413550 failed: `HookFormsWindowsTests.testTheLongFormOfAPathBeyondMaxPath` built its "long" expectation under the runner's 8.3 `RUNNER~1` TEMP; macOS run 39116414085 green), review CHANGES_REQUESTED (`reports/M6-review-2.md`, recovered from the session: the real-engine test inherited every client-home variable and the real `APPDATA`/`LOCALAPPDATA`) → round 3: an allowlisted child environment with every profile folder inside the test's home, a bounded hook wait, the fixture base spelled in full, `hello` replaceable and `error` dropped first under a stall, `--language` applied before the lock check, `SessionProject` memoised per report, the unused `Hooks` seam removed, `engine-state.later.json` ("Pending update", "Live status off", `unverified`) read by both sides, restore-source properties and `.rsp` files refused, D-042/D-043 and PROTOCOL.md notes (token text, session title, GMT); the lock's running holder compared by final path (D-044: the first local G3 after the build folder moved behind a junction failed 4 tests). Local round 3: G3 1451 executed, 1447 passed, 4 skipped, also the changed classes under an 8.3 `TEMP`; G5 11/11; warnings equal the baseline. Round 1 (`80fb737`): tests FAILURES (`reports/M6-tests-1.md`: the fixtures checked out CR LF on the runner, no `.gitattributes`, so G5 failed in CI and the job stopped; everything passed locally; macOS run 39113715915 green), review CHANGES_REQUESTED (`reports/M6-review-1.md`: hooks and hold time re-applied on every 10 s tick; labels not Core's own rules; writes blocking the main actor) → round 2 (`39753bf`): per-value watches as macOS, `AgentRow.resetLabel`/`sessionStatusLabel`/`SessionProject`, a writer thread with coalesced state, `.gitattributes`, more fixtures, C# and boundary-check hardening, `windows/nuget.config`, telemetry off job-wide, real-approval and stalled-shell tests. Local round 2: G3 1449 executed, 1445 passed, 4 skipped; G5 10/10; warnings equal the baseline |
| M7 Windows UI shell | approved 2026-10-19 | `5ab51fc` (M6's approval) | `port-M7-approved` (`e7bd816`) | round 3 (`e7bd816`): tests ALL_PASS (`reports/M7-tests-3.md`: G2 cold release build with the 6 baseline warnings, .NET 0; G3 1465 executed, 1461 passed, 4 skipped, 0 failed, three passes, the changed classes 32/32 under an 8.3 `TEMP`; G4 4/4; G5 16 + 40 C#, 24/17 fixtures, 15 pictures; G6; Windows run 39230808408 and macOS run 39230811027 green on attempt 1), review APPROVE (`reports/M7-review-3.md`, 3 non-blocking: SKIPPED_TESTS' count now measured by the tester, BLOCKERS reordered with the approval, `MCPTools.instructions`' doc comment → M8 step 1). Round 2 (`96bdd61`): tests ALL_PASS locally (`reports/M7-tests-2.md`: G2 6 baseline warnings, .NET 0; G3 1464 executed, 1460 passed, 4 skipped, 0 failed; G4 4/4; G5 16 + 38 C#, 24/17 fixtures, 15 pictures; G6), macOS run 39184004326 green, Windows run 39183956058 attempt 1 failed on the upstream timing test `ProcessLinesTests.testABusyMacsListingIsReadInAMoment` alone (23.50 ms against its 20 ms bound; 12.5–18 ms on earlier runs, 10 ms locally) → one `rerun-failed-jobs` as agreed for upstream timing tests; review CHANGES_REQUESTED (`reports/M7-review-2.md`: 1 blocking — the unfinished M7 work without an owner, 8 non-blocking) → round 3 (D-054): BLOCKERS B-004/B-005 and the references to them, `--mcp`'s Windows words, `CardRules.Diff` by card kind, the windows' appearance owned by the application, the source rules compared with the Desktop's, the end-to-end test's sources and saved live-status defaults, SUPPORT_MATRIX's wording, a test comment; launch at login's gate left to M8. Round 1 (`c6222d2`): tests FAILURES (`reports/M7-tests-1.md`: every gate passed locally, but Windows run 39180353080 crashed in G3 — the engine's `WindowsTimeZone.adopt()` trapped on the runner's `UTC` zone, since step 7, so step 7's run 39178306631 failed too and step 8's was cancelled: the last green Windows run before it was step 6's 39177665388; macOS run 39180355391 green), review CHANGES_REQUESTED (`reports/M7-review-1.md`: an edit's card hid its lines; a waiting request opened the panel unasked; the TASK §3 settings display and D-043's M7 items unowned) → round 2 (D-053): the diff first (`CardRules`), the request's line at rest (`IslandParts`), protocol 1.5 `sources` and the Agents section, live-status defaults at start, B-002/B-003 for the agent-tools channel and the session title/row tokens, the Desktop's colours (`DesktopColours`), no Core defaults in C#, the caption rule for full screen, `LoginItem` gated and clearing Task Manager's "disabled", live appearance and DPI, lost capture, `--feed` only with `--snapshot`, the time zone's fixed offset and `Etc/UTC` (D-050), a closed pipe failing one test instead of a batch, the C# `unverified` check (recorded as done in step 1, done now), 1.4 and 1.5 C# tests and invalid fixtures, a display-scale loop found by the smoke test. Steps 1–9 (`a66759f`…): M6 round 3's review items; the WPF shell (island per display, request queue, question and plan cards, events, tray, settings, statistics, the HUD on any edge, full-screen apps); protocol 1.1–1.4; the engine's time zone |
| M8 Packaging | todo | | | |
| M9 Wrap-up | todo | | | |

## Environment (this machine)

- Windows 11 Pro 10.0.26200 x64, not elevated. Visual Studio 2022 Build Tools (VC x64/ARM64, Windows 11 SDK
  22621); Visual Studio Community 2026 Insiders at `D:\visual studio\main` (.NET desktop and C++ desktop workloads;
  the user allows it for M7's WPF shell — the gates still build with `dotnet`); Swift 6.4.1 (`Swift.Toolchain`, per-user, `%LOCALAPPDATA%\Programs\Swift`) installed by winget on
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
| G5 UI | `scripts\windows\test-dotnet.ps1` (`dotnet test windows\AgentHUD.sln -c Release`, warnings as errors, telemetry off, D-042; then `python scripts\windows\check-protocol.py`): the protocol's C# contract tests from M6, the shell's own (`AgentHUD.Shell.Tests`) from M7; and from M7 `scripts\windows\smoke-shell.ps1 -Engine <release agenthud-engine.exe>` (the shell's `--snapshot` with the demo in a temporary profile: five pictures — at rest, open, the usage panel, a question's and a plan's cards — of plausible size, status 0 within 30 s; CI keeps the pictures as the `shell-snapshot` artifact); opt-in, on a desktop nobody is using, `scripts\windows\ui-check.ps1 -Engine <exe>` (real clicks and typing, D-046) | M6 (protocol), M7+ (UI) |
| G6 boundaries | `python scripts\check-source-boundaries.py` | every milestone |

Warning baseline (Swift 6.4.1 toolchain and SDK, not the port's): `WinSDK.swiftmodule … reference to type 'wchar_t'
broken by a context change` (repeated per compile job). Upstream lines the port did not change, Windows only
(D-033): `'strerror' is deprecated` in `MCP/MCPStdio.swift`; `'close' is deprecated` in
`Hooks/Permission/PermissionHookClient.swift` and `Providers/Kit/Zstandard/ZstandardReader.swift`; `'init(cString:)' is
deprecated` in `Providers/Antigravity/AntigravityCLI.swift`; `result of call to 'wait(until:)' is unused` in
`Providers/Codex/CodexDesktopStream.swift`; `no 'async' operations occur within 'await' expression` in
`Hooks/Permission/DeepSeekQuestions.swift`. Anything else is a new warning.

## Next steps (resume here)

1. M7 step 1 (start `f531b63`, M6's approval): M6 round 3's ten non-blocking review items, on `m7-work` in
   `%LOCALAPPDATA%\agenthud-dev\wt7` (scratch `wt7build`): every test engine in a home of its own with a `Path` of the
   system and the Swift runtime only, a key-subset check; the writer's queue rules as `ProtocolWriter.enqueue` (a
   `hello` replaced in place) with `ProtocolWriterTests`, which also covers the `SessionProject` memo; a junction made
   through `FSCTL_SET_REPARSE_POINT` and a folder kept while its link is; the max-path test's guard; `imagePath`'s
   slashes; the C# `unverified` check. Also the tester's note: `test.ps1` should fail a filtered batch that runs no test.
   Done: `a66759f` (G3 1456 executed, 1452 passed, 4 skipped).
2. M7 step 2 (D-045, done in `m7-work`): the shell's skeleton and ADR-002's risk spike, measured — an island per
   display, click-through, never activating; the engine connection, hover, request queue on its display, tray; protocol
   1.1 (`panel.marks`, rows' `modelText`/`shortModelText`/`mark`, sessions' `vendor`/`mark`, approvals' `mark`); the
   snapshot and `smoke-shell.ps1` (G5, CI step).
3. M7 step 3 (D-046): question and plan cards (drafts kept per request, one question at a time, a plan's three
   answers and its note, a plan answered elsewhere), typing that takes the keyboard only once clicked, the Windows demo's
   question and plan, `scripts\windows\ui-check.ps1` (opt-in; 14 checks passed locally). A person should still type an
   answer through a Chinese input method once (the check bypasses input methods).
4. M7 step 4 (D-047): events on the island — protocol 1.2 (each event's words, the Desktop's copy, checked against its
   sources), `EventQueue` (the Desktop's alert queue for news), the event line at rest and its card when hovered, the
   snapshot's six event pictures from the fixtures (`--feed`). Not yet: replies listed beside a waiting request; a
   reply's return to its session and token-usage actions (session navigation is macOS-only so far).
5. M7 step 5 (D-048): the settings window (the General pane: appearance, language, launch at login, client hooks with
   their confirmation, the approval wait), launch at login through the `Run` key, WPF's Fluent theme with Mica for the
   normal windows, `--show-settings`; the snapshot draws the window and `ui-check.ps1` changes a setting through the
   engine (19 checks passed locally).
6. M7 step 6 (D-049): the statistics window's Recent usage card (protocol 1.3), `--show-stats`, its snapshot. G1 for
   step 4 (`da4f908`): macOS run 39172797224 green on attempt 2 after the agreed single rerun of the upstream flake.
7. M7 step 7 (D-050): the engine's time zone is Windows' own.
8. M7 step 8 (D-051): the HUD on any edge per display (protocol 1.4: displays named by their monitor interface path,
   placed by Core), dragged live to the nearest edge and saved as a patch of `screens`; `ui-check.ps1` drags it (23
   checks passed locally).
9. M7 step 9 (D-052): the HUD steps aside for a full-screen app on its display, never over a waiting request
   (`ui-check.ps1`: 24 checks passed locally, two displays).
10. M7 round 1 (`c6222d2`): CHANGES_REQUESTED, and G3 failed in CI (`reports/M7-review-1.md`, `M7-tests-1.md`).
   Item 1 above claimed "the C# `unverified` check": that edit had not landed; it is in round 2.
11. M7 round 2 (D-053): the fixes listed in the M7 row. Local: G3 1464 executed, 1460 passed, 4 skipped, 0 failed; G5 54 C# tests (16 protocol, 38 shell), 24 valid and 17 invalid fixtures, the 15-picture smoke test; `ui-check.ps1` 25 checks; G6 passed. Next: push, CI both platforms,
   port-tester (G5's smoke test, and `ui-check.ps1` on an idle desktop), port-reviewer on `5ab51fc...HEAD`. Left for
   later, recorded in BLOCKERS B-002–B-005 (M7 round 3): the agent-tools channel, the session title and row tokens, the
   panel's balances, accounts, notices and token periods, replies beside a request, the settings window's other panes,
   the other statistics pages, the Simple panel, logo size and spacing, moving the HUD to another display; and a
   session `message` in a fixture. For M9's
   `docs/windows.md`: D-048's differences from the Desktop (the hooks-off confirmation asks with the hooks' own note,
   not the list of what stops working). Visual Studio may be used (Environment); the gates build with `dotnet`.

12. M7 round 3 (D-054): M7 review round 2's items (see the M7 row). Local: the changed Swift classes 32/32 (`ShellProtocolTests`, `EngineServeEndToEndTests`, `MCPServerTests`, `MCPToolsOffTests`); G5 56 C# tests (16 protocol, 40 shell), 24/17 fixtures, the 15-picture smoke test; G6 passed. Committed as `e7bd816`; approved (see the M7 row).

13. M8 step 1 (start `e7bd816`, M7's approval): `scripts/build-windows.ps1` (one command: the junction, the release
   engine, the shell published, the portable zip with LICENSE and THIRD_PARTY_NOTICES.txt), the Swift runtime's DLLs and
   their notices, launch at login's gate on a marker the script writes (M7 review round 2), `MCPTools.instructions`'
   doc comment above each branch (M7 review round 3), a CI artifact of the zip (no release).

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
- Resolved in M7 step 7 (D-050): swift-corelibs-foundation on Windows reports the local time zone as GMT; `--serve` now
  adopts Windows' zone as Foundation's default (`WindowsTimeZone`, the system ICU's Windows-to-IANA mapping, else the
  current offset). `TimeZone.current` itself still says GMT, and Core does not read it. Hooks and `--mcp` format no
  times. The protocol fixtures are made in UTC on purpose and are not affected.
- Resolved in M7 round 3 (D-054): `--mcp` on Windows says the HUD is at the top of the screen and that the agent tools
  are not available on Windows yet (BLOCKERS B-002).
- When `USERPROFILE` is pointed at a test home (the tester's choice in M7 round 2), `remove-test-preferences.ps1`
  looks there and misses the `AgentHUDTests.<UUID>.plist` files swift-corelibs writes into the real `%LOCALAPPDATA%`;
  `test.ps1` alone does not override `USERPROFILE`. Clean up in M9 with the `%TEMP%` item below.
- For M8: launch at login's "installed copy" gate (`LoginItem.cs`) is a path test (`\bin\Debug\`, `\bin\Release\`);
  the packaging script should write a marker beside the shell and the gate should require it (M7 review round 2).
- The real `%TEMP%` grows by about 50 folders per G3 run (M4's `ProviderEnginesWindowsTests`, upstream fixtures,
  swift-corelibs' `TemporaryDirectory.*`; M5's fixtures leave nothing): clean up in M9 or give test.ps1 its own TEMP.
- Cursor's `AdditionalSource.isInstalled` on Windows checks the real `%APPDATA%` database (M4 review round 4,
  non-blocking): no test reads it today; make the database injectable when one does.
- Non-blocking review items from M0 round 1 are folded into DECISIONS.md (D-006…D-023) and PORTING_PLAN.md rows;
  the code changes they call for are in M3–M6.
