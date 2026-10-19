# M7 test report, round 3

- Branch: `m7-work` (identical to `windows-port`, pushed). Head under test: `e7bd816` ("Windows port M7 round 3: the
  review's items").
  - Round 3 alone (`bd1cdd8...e7bd816`): 20 files, +231/−51.
  - Swift: 2 shared Core sources (`MCP/MCPServer.swift`, `MCP/MCPTools.swift`, each a new `#if os(Windows)` branch; the
    macOS text is unchanged), 2 upstream tests adjusted the same way (`MCPServerTests`, `MCPToolsOffTests`), and 2 port
    tests (`EngineServeEndToEndTests`, `ShellProtocolTests`).
  - C#: `Appearance` (new) with `AppearanceTests`, `CardRules.Diff` by card kind with a new test, `ShellModel.StringSetting`,
    `App`/`SettingsWindow`/`StatisticsWindow` (the appearance owned by the application).
- Run by: port-tester, 2026-10-19, 05:33–06:10 local time (UTC−4). Machine: Windows 11 Pro 10.0.26200, not elevated,
  time zone Eastern Standard Time, Windows app mode dark (`AppsUseLightTheme` = 0).
- Where it ran:
  - Worktree `E:\agenthud-dev\wt7`, reached through `%LOCALAPPDATA%\agenthud-dev\wt7` (D-007).
  - Scratch build `%LOCALAPPDATA%\agenthud-dev\tester7r3build` (new, cold).
  - Logs and pictures in `E:\agenthud-dev\tester7r3`: pass 1 in `run1\`, pass 2 in `run2\`, pass 3 at the top level
    (see "How it ran").
- Test profile, as PROGRESS.md's Gates section says:
  - `APPDATA`/`LOCALAPPDATA` pointed at my own `%LOCALAPPDATA%\agenthud-dev\testprofile-t7r3\{Roaming,Local}` for each
    test command. `test.ps1` and `smoke-shell.ps1` then make their own temporary profiles inside that.
  - **`USERPROFILE` and `HOME` were not overridden** (round 2's lesson). `remove-test-preferences.ps1` therefore found
    and removed the `AgentHUDTests.<UUID>.plist` files: `Removed 6 test preference file(s) from
    C:\Users\suzume\AppData\Local` after the first full G3. The real `%LOCALAPPDATA%` held 0 such `.plist` files before
    and after.
- What I changed: I wrote only this report. I committed nothing, pushed nothing, reran no CI job, did not run
  `ui-check.ps1`, and touched no client configuration.
  - `HKCU\…\CurrentVersion\Run` and `…\Explorer\StartupApproved\Run` were the same before and after, with no AgentHUD
    entry.
  - No `AgentHUD`/`agenthud-engine` process was left.
  - I removed my 8.3 TEMP folder and my test profile folder afterwards.
- Working tree:
  - Clean at `e7bd816` when I started (05:33).
  - At 05:38, while my gates ran, someone else changed `docs/windows-port/BLOCKERS.md` (+10/−10) and added
    `docs/windows-port/reports/M7-review-3.md`. Those are not mine.
  - They are documentation only. G6 passed both before them (05:34) and after them (05:47, 05:58, 06:05).

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | **PASS**: `Source checks` run 39230811027 on `e7bd816`, attempt 1, `success` (jobs `test`, `app`, `macos` all `success`). |
| G2 Windows build | **PASS**: cold release build 193 s, exactly the 6 baseline lines; `dotnet build` 0 warnings, 0 errors (also `--no-incremental`); `Windows port` run 39230808408 `Build (release)` `success`. |
| G3 Windows tests | **PASS**: 1465 executed, 1461 passed, 4 skipped, 0 failed (same in two full runs); the 4 changed classes under an 8.3 `TEMP`, 32/32. **Windows CI: PASS** on attempt 1 of run 39230808408. |
| G4 determinism | **PASS**: `RecordCodingGoldenTests` 4/4 |
| G5 UI | **PASS**: C# 56/56 (16 protocol, 40 shell); fixtures 24 valid, 17 invalid, 0 failures; smoke test 15 pictures, status 0 after 3 s; CI's G5 steps and the `shell-snapshot` artifact present. `ui-check.ps1` **not run**. |
| G6 boundaries | **PASS** |
| G7/G8 | notes below |

## How it ran

- One driver script outside the repository, `E:\agenthud-dev\tester7r3\run-gates.ps1`, ran the steps in sequence in
  the background, each with output to its own log.
- **Pass 1** (05:34–05:43): every gate, including the cold Swift release build. All passed. But my own poller held
  `progress.log` open, so the driver could not write its markers or exit codes there.
- **Pass 2** (05:47–05:51): every gate except the Swift build, to record exit codes. A poller locked the log again.
  The results equal pass 1.
- **Pass 3** (05:58–06:04): the same steps, each exit code written to its own `<step>.exit` file. Every one is `0`.
- Durations below come from the logs' creation and last-write times. This is a problem with my tooling, not a finding
  about the port.

## G1: PASS

Read with `sh /e/agenthud-dev/tools/gh.sh "/repos/IwadoSuzume/agent-hud-open/actions/runs?branch=windows-port&per_page=6"`
and the runs' `/jobs`.

- `Source checks` (workflow_dispatch) run **39230811027** on `e7bd816`: `completed` / `success`, attempt 1.
  - `test` 09:33:31–09:43:50Z `success`.
  - `app` 09:33:31–09:40:12Z `success`.
  - `macos` 09:43:53–09:43:56Z `success`.
- The upstream macOS timing test (`StatsWindowLifecycleTests.testNativeRestoreFitsContentUpdatedWhileMiniaturized`) did
  not fail. No rerun was needed and none was made.
- This round touches two shared Core files (`MCPServer.swift`, `MCPTools.swift`), so G1 does apply. Their macOS branches
  keep the old text, and `MCPServerTests`/`MCPToolsOffTests` passed on macOS.

## G2: PASS

**Swift build.**

- Command: `scripts\windows\build.ps1 -Log <tester7r3>\g2swift.log -c release --scratch-path <tester7r3build>`, with
  PROGRESS.md's `Path`/`SDKROOT`, from `%LOCALAPPDATA%\agenthud-dev\wt7`.
- Duration: 05:34:37–05:37:50 (193 s), `Build complete! (191.17 secs)`. One attempt, no "being used by another process",
  0 `error:` lines.
- Warnings: exactly the 6 baseline lines from D-033, each once, nothing new:
  - `MCPStdio.swift:59` `strerror`;
  - `PermissionHookClient.swift:38` `close`;
  - `ZstandardReader.swift:46` `close`;
  - `AntigravityCLI.swift:18` `init(cString:)`;
  - `CodexDesktopStream.swift:170` `wait(until:)` unused;
  - `DeepSeekQuestions.swift:106` `await`.
- There was no toolchain `wchar_t` line, as in round 2. Its absence is not a new warning.
- Engine: `<tester7r3build>\out\Products\Release-windows-x86_64\agenthud-engine.exe`, 29,403,648 bytes.

**.NET build.**

- `dotnet build windows\AgentHUD.sln -c Release`: 3 s, `已成功生成。 0 个警告 0 个错误`.
- `--no-incremental`, run twice (passes 2 and 3): 2 s each, 0 warnings, 0 errors. All 5 projects built.

**CI:** `Windows port` run 39230808408 `Build (release)` `success`.

## G3: PASS (local and Windows CI)

### Full run

- Command: `& scripts\windows\test.ps1 -ScratchPath <tester7r3build> -Log <tester7r3>\g3.log`, with PROGRESS.md's
  environment (`APPDATA`/`LOCALAPPDATA` redirected, `USERPROFILE`/`HOME` untouched).
- Pass 1: 05:37:53–05:42:17 (264 s), test build `Build complete! (65.15 secs)`.
- Pass 3: 05:58:45–06:02:12 (207 s), **exit 0**.
- Support: swift-testing `√ Test run with 9 tests in 0 suites passed`.
- Core XCTest, in all three passes: **1465 executed, 1461 passed, 4 skipped, 0 failed**.
  - The 9 batches were 113/126/125/201/201/255/76/256/112.
  - No batch failed, there were 0 `Test Case … failed` lines, and no `no test matched` line.
  - This equals SKIPPED_TESTS.md's state line: "1461 pass, 4 runtime skips, 34 listed skips, 7 excluded files, 0
    failures".
  - The one test more than round 2 (in the `[Q-T]` batch, 255 → 256) is the new
    `ShellProtocolTests.testTheSourcesRulesAreTheDesktopsCopy`.
- The upstream timing test `ProcessLinesTests.testABusyMacsListingIsReadInAMoment` passed:
  `a 414 KB process listing:` 10.35 / 10.55 / 10.56 ms, against its 20 ms bound.

### The classes changed in round 3, under an 8.3 `TEMP`

- Setup: `TEMP`/`TMP` = `C:\Users\suzume\AppData\Local\Temp\AG51DC~1`, the short name of
  `…\Temp\agenthud tester7r3 LongNamedTemporaryFolder`.
- Command: `test.ps1 -ScratchPath <tester7r3build> -Log <tester7r3>\g3short.log -Filter ShellProtocolTests,
  EngineServeEndToEndTests, MCPServerTests, MCPToolsOffTests`.
- Result: about 26 s, **exit 0**, **32/32 passed**:
  - `EngineServeEndToEndTests` 6, including
    `testARealRequestGoesThroughTheProtocolAndHooksChangeOnlyWithTheirSwitch` (12.0 s), which has the new `sources` and
    saved live-status checks;
  - `MCPServerTests` 10;
  - `MCPToolsOffTests` 2;
  - `ShellProtocolTests` 14, including `testTheSourcesRulesAreTheDesktopsCopy`.
- The short folder held 16 items afterwards (`TemporaryDirectory.*`, `org.swift.swiftpm`, …), so the short `TEMP` was
  in effect. I removed the folder.

### Windows CI

`Windows port` (push) run **39230808408** on `e7bd816`: `success` on **attempt 1**, 09:32:17–09:52:37Z. Every step was
`success`: boundaries, G5 .NET tests, release build, `Test`, shell smoke test, the pictures, and the smoke package. The
upstream Windows timing test did not fail, and nothing was rerun.

### Skips

- Runtime skips, 4:
  - `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe`;
  - `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe`;
  - `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe`;
  - `SessionUsageProbeTests.testReportedSessionsUsageProbe`.
  - All 4 are registered in SKIPPED_TESTS.md §3.
- Skip list: all 34 patterns in `scripts/windows/skipped-tests.txt` are in SKIPPED_TESTS.md (checked by script, class
  and test name).
- Excluded files: all 7 in `windowsSkippedTests` are in §1.
- Nothing unregistered was skipped.

## G4: PASS

- Command: `test.ps1 … -Filter RecordCodingGoldenTests`. Duration: 6 s, exit 0.
- Result: `√ Test run with 4 tests in 0 suites passed`.
  - `theRecordEncoderWritesTheGoldenSample`.
  - `millisecondDatesRoundTripTheGoldenSamples`.
  - `recordIdentitiesMatchTheGoldenSamples`.
  - `digestsMatchTheNISTVectors`.

## G5: PASS (`ui-check.ps1` not run)

**`scripts\windows\test-dotnet.ps1`:** 2 s, exit 0.

- `已通过! - 失败: 0，通过: 16 … AgentHUD.Protocol.Tests.dll`.
- `已通过! - 失败: 0，通过: 40 … AgentHUD.Shell.Tests.dll`.
- `Protocol fixtures: 24 valid, 17 invalid, 0 failure(s).`
- This matches SKIPPED_TESTS.md's line: 56 C# tests (16 protocol, 40 shell), none skipped.

**`python scripts\windows\check-protocol.py`, run on its own:** under 1 s, exit 0, with the same line.

**`scripts\windows\smoke-shell.ps1 -Engine <tester7r3build>\…\agenthud-engine.exe -Out <tester7r3>\snapshot`:** 4 s,
exit 0. Its build gave 0 warnings and 0 errors.

- `Shell smoke test: 15 pictures in E:\agenthud-dev\tester7r3\snapshot, status 0 after 3 s.` The result was the same in
  all three passes.
- Sizes, identical to round 2:
  - island-rest 992x67, island-open 992x780, island-request 992x131, island-usage 992x1798;
  - card-edit 992x864, card-question 992x1040, card-plan 992x826;
  - event-reply-line 395x64, event-reply-card 992x364, event-quota-line 360x64, event-quota-card 992x558,
    event-credits-line 343x64, event-credits-card 992x460;
  - settings 1091x1472, statistics 1411x448.

**What the pictures show.**

| Picture | Shows | Matches |
| --- | --- | --- |
| `settings` | Dark, as the demo's "System" appearance and this machine's dark app mode say (the window's look now comes from `App.FollowAppearance`). Appearance & language (System selected, English); Startup ("Launch at login" checked, the demo's value); Clients (hooks on, "Wait for an answer: 10 minutes"); Agents: Claude, Codex "Ready" with "Quota, sessions and usage", DeepSeek "Ready" with "Balance, sessions and usage", Antigravity greyed "Not supported on Windows / Appears once installed" | yes |
| `statistics` | Dark. "Recent usage", "Excl. cache reads"; Today 4.4M (≈$23.67 · Cache hits 79%), Last 7 days 105M, Last 30 days 450M; each has a coloured share bar, its top three models with marks, and "N more" | yes |
| `card-plan` | "Has a plan to review / Plan", the plan's two steps, Keep planning / Approve, accept edits / Approve; **no diff lines** (round 3's `CardRules.Diff` by kind) | yes |
| `card-question` | "Asks a question / Which database?", 1/2, SQLite (One file) / Postgres / Other, Skip and a disabled Next; no diff lines | yes |

**`scripts\windows\ui-check.ps1`:** **not run**, as instructed. The user may be at the machine.

**CI:** in run 39230808408, `Shell protocol and .NET tests (G5)` and `Shell smoke test (G5)` were `success`. The
`shell-snapshot` artifact is present (1,072,814 bytes, not expired).

## G6: PASS

- Command: `python scripts\check-source-boundaries.py`, about 1 s, exit 0. Output: `Source boundaries and ignore rules
  passed.`
- I ran it 4 times: at 05:34 on the clean head, and at 05:47, 05:58 and 06:05 with the other session's uncommitted
  BLOCKERS.md edit and review report present.

## G7/G8 notes (none blocking)

1. **(G7) Shared upstream files changed.**
   - `MCPServer.swift` and `MCPTools.swift` (Core) and their upstream tests gain `#if os(Windows)` branches.
   - Each `#else` keeps the macOS text byte for byte, and G1 is green.
   - The change is minimal, but it is a change to shared files, for the reviewer to weigh.
2. **(G8) `testTheSourcesRulesAreTheDesktopsCopy` compares source text.**
   - It finds a function's end by counting `{`/`}` in the Desktop's `SourceDetector.swift`, including braces inside
     strings and comments.
   - It passes on today's text. An upstream edit with an unbalanced brace in a string literal would fail it as a false
     alarm, not hide a difference. That is acceptable for a drift detector.
3. **(visual) The settings and statistics pictures follow this machine's app mode.**
   - Under "System" they are dark here because `AppsUseLightTheme` is 0.
   - On a machine in light mode, or a CI runner, they would be drawn light. The smoke test checks only sizes, so it
     passes either way.
   - `App.IsDark` falls back to dark (`dark ?? true`) only before `FollowAppearance` first runs, which is in
     `OnStartup`.
4. **(known issue) The real `%TEMP%` still grows.** It went from 3509 to 3809 top-level items over my three G3 passes
   (PROGRESS.md: clean up in M9). I removed only my own 8.3 folder.
5. **(tooling) Round 2's preference-file note is settled.** Without overriding `USERPROFILE`, `test.ps1`'s cleanup found
   and removed the 6 files Foundation wrote into the real `%LOCALAPPDATA%`, and 0 were left.

## Skipped tests and registration

| Skip | Kind | Registered |
| --- | --- | --- |
| `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe` | runtime (`AGENT_HUD_PROBE_…`) | yes, §3 |
| `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe` | runtime | yes, §3 |
| `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe` | runtime | yes, §3 |
| `SessionUsageProbeTests.testReportedSessionsUsageProbe` | runtime | yes, §3 |
| 34 patterns in `scripts/windows/skipped-tests.txt` | skip list | yes, all 34 in §2 |
| 7 files in `windowsSkippedTests` (`UnixSocketListenerTests`, `ChildProcessTests`, `InstanceLockTests`, `CodexDaemonOriginTransportTests`, `CodexDesktopTestServer`, `CodexDesktopPermissionsTests`, `CodexDesktopStreamTests`) | excluded files | yes, all 7 in §1 |
| Conditional runtime skips (no `node.exe`/`git.exe`/8.3 names/…) | runtime | none triggered locally |
| C# tests | — | none skipped |

Every gate I ran passed. Both CI runs on `e7bd816` were green on their first attempt, and nothing was rerun.
`ui-check.ps1` was not run, as instructed.

TESTS: ALL_PASS
