# M7 test report, round 1

- Branch: `windows-port`. Head under test: `c6222d2` ("Windows port M7 step 9: full-screen apps keep their display; M7
  ready for review"). M7 range `5ab51fc...c6222d2`: 73 files, +4967/−147. Swift sources changed: 9 files, +389/−17.
  All of them are under `Platform/Windows/`, except 4 lines of `Demo/DemoData.swift`, which are inside `#if os(Windows)`.
- Run by: port-tester, 2026-10-18, 20:20–20:45 local time (UTC−4). Machine: Windows 11 Pro 10.0.26200, not elevated,
  time zone Eastern Standard Time.
- The working tree was clean at `c6222d2` before and after the gates. The only untracked file is
  `docs/windows-port/reports/M7-review-1.md`, which the reviewer wrote in parallel; it is not mine. I wrote only this
  report. I committed nothing, pushed nothing, and made only read calls to the GitHub API. I did not rerun anything.
- Local gates ran through the junction `%LOCALAPPDATA%\agenthud-dev\src` (→ `E:\桌面项目\agent-hud-open`) with
  `--scratch-path %LOCALAPPDATA%\agenthud-dev\build` (D-007). `%LOCALAPPDATA%\agenthud-dev` is itself a junction to
  `E:\agenthud-dev`. Logs, the CI job logs and the smoke test's pictures are in `%LOCALAPPDATA%\agenthud-dev\tester7`.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | **PASS**: `Source checks` run 39180355391, attempt 1, `test`/`app`/`macos` success. 2087 XCTest, 8 skipped, 0 failures; swift-testing 10 passed. The upstream flaky test passed. |
| G2 Windows build | **PASS**: locally, release build 175 s with exactly the 6 baseline lines, and `dotnet build` 0 warnings, 0 errors. In CI, run 39180353080's step 11 succeeded with the same 6 lines. |
| G3 Windows tests | **FAIL**: Windows CI run 39180353080 failed. Its test runner crashed twice in `WindowsTimeZone.adopt()` on the runner's `UTC` zone. Locally the gate passes: 1461 executed, 1457 passed, 4 skipped, 0 failed, and 27/27 under an 8.3 `TEMP`. |
| G4 determinism | **PASS**: `RecordCodingGoldenTests` 4/4 locally, in Windows CI (Support batch) and in macOS CI |
| G5 UI | **PASS locally**: C# tests 40/40, fixtures 22 valid + 15 invalid, smoke test 13 pictures with status 0 after 3 s, `ui-check.ps1` 24/24 PASS. **Not run in CI**: the job skipped "Shell smoke test (G5)" after the failed Test step, so `shell-snapshot` uploaded nothing. |
| G6 boundaries | **PASS** locally and in both CI runs |
| G7/G8 | notes below. G8: one inaccurate statement in PROGRESS. |

## G1: PASS

`Source checks` run **39180355391**:

- Trigger: workflow_dispatch on `windows-port`, head `c6222d26452a1ed699921a4c69d3e884dcb34841`.
- Result: `completed` / `success`, `run_attempt` 1, 00:20:40Z to 00:32:14Z.

| Job | Id | Conclusion |
| --- | --- | --- |
| `test` | 117831590683 | success (00:20:55Z to 00:32:07Z) |
| `app` | 117831590442 | success (00:20:49Z to 00:27:49Z; `build-app.sh release`, codesign verify) |
| `macos` | 117834136840 | success |

- `test` job log:
  - `Source boundaries and ignore rules passed.`
  - `Executed 2087 tests, with 8 tests skipped and 0 failures (0 unexpected) in 426.552 (426.721) seconds`.
  - `✔ Test run with 10 tests passed after 1.374 seconds` (including `portableDigestsEqualCryptoKit` and the golden
    tests).
- **The upstream flaky test passed on attempt 1.**
  `StatsWindowLifecycleTests.testNativeRestoreFitsContentUpdatedWhileMiniaturized` passed in 2.046 s, so no rerun was
  needed.
- **The 8 macOS skips are the same as in M6.**
  - The four `…Probe` tests.
  - `testProbeWritesEveryBakedMarkBotAndAccent`.
  - `testFrameCost`.
  - `testAReminderMarkOpensAsItsLogoAndTurnsIntoItsBotOnceItsCardHasOpened`.
  - `testAGlowThatClosesStopsItsFrames`.
- All 34 entries of `scripts/windows/skipped-tests.txt` have a `passed` line in this macOS log (checked by script).
- **macOS warnings: the same file:line set as M6 round 3, nothing new.**
  - Core: `DeepSeekQuestions.swift:106`, `AntigravityCLI.swift:18`.
  - Core tests: `PermissionHookTests` 435/442/453, `PanelToolsSpanTests:91`, `DeepSeekProviderTests:525`,
    `CollectionSignalTests:331`, `UsageRefreshTests:73`.
  - Desktop tests: `AgentSeparationTests` 136/209/243, `JoinedGlassTests` 192/246, `ScreenStyleHUDTests:254`.

## G2: PASS

- **Swift build.**
  - Command: `scripts\windows\build.ps1 -Log <tester7>\g2swift.log -c release --scratch-path <build>`.
  - Duration: 175 s, `Build complete! (173.05 secs)`, exit 0, one attempt.
  - Warnings: exactly the 6 baseline lines from D-033, nothing new:
    - `MCPStdio.swift` `strerror`;
    - `PermissionHookClient.swift` `close`;
    - `ZstandardReader.swift` `close`;
    - `AntigravityCLI.swift` `init(cString:)`;
    - `CodexDesktopStream.swift` `wait(until:)` unused;
    - `DeepSeekQuestions.swift` `await`.
  - No `wchar_t` line this time. That is the toolchain's baseline item, and its absence is not a new warning.
- **Engine built:** `<build>\out\Products\Release-windows-x86_64\agenthud-engine.exe` (29,322,752 bytes,
  20:25).
- **.NET build.**
  - Command: `dotnet build windows\AgentHUD.sln -c Release`.
  - Result: 5 s, `0 个警告 0 个错误`. A `--no-incremental` rebuild also gave 0 warnings and 0 errors.
  - All 5 projects built: Protocol, Shell, both test projects and AgentHUD.
- **CI:** run 39180353080 step 11 "Build (release)" succeeded (`Build complete! (529.54 secs)`). Its Core lines are the
  same 6 baseline warnings.

## G3: FAIL (CI); local PASS

### Local

- **Command:** `& scripts\windows\test.ps1 -ScratchPath <build> -Log <tester7>\g3.log`.
- **Duration:** 215 s, exit 0. The test build was incremental: `Build complete! (25.43 secs)`.
- **Totals:**
  - Support: swift-testing 9/9 passed.
  - Core: XCTest **1461 executed, 1457 passed, 4 skipped, 0 failed**, summed over the 9 batches
    (113/126/125/201/201/255/76/254/110).
  - This equals the state line in SKIPPED_TESTS.md: 1457 pass, 4 runtime skips.
- **The four classes under an 8.3 `TEMP`.**
  - Setup: `TEMP` and `TMP` set to `C:\Users\suzume\AppData\Local\Temp\AG3215~1`, the short name of
    `…\Temp\agenthud tester7 LongNamedTemporaryFolder`.
  - Command: `& test.ps1 -ScratchPath <build> -Log <tester7>\g3short.log -Filter @('ShellProtocolTests',
    'EngineServeEndToEndTests', 'WindowsTimeZoneTests', 'InstanceLockWindowsTests')`.
  - Result: 26 s, exit 0, **27/27 passed**:
    - `ShellProtocolTests` 12;
    - `EngineServeEndToEndTests` 6 (18.4 s);
    - `WindowsTimeZoneTests` 3;
    - `InstanceLockWindowsTests` 6.
  - The tests left 16 items inside the folder, so the short `TEMP` was in effect.
  - I removed the folder afterwards.

### CI: Windows port run 39180353080, job `swift` 117831579356: failure

- The run completed with `failure` at 00:39:50Z.
- Steps that succeeded:
  - 3 Check source boundaries.
  - 4 Shell protocol and .NET tests (G5): `Passed! … 14` and `… 26`, `Protocol fixtures: 22 valid, 15 invalid, 0
    failure(s).`
  - 11 Build (release).
- Step 12 **Test** failed: `##[error]Process completed with exit code 1`.
- Steps 13 "Shell smoke test (G5)" and 15 "Compile a smoke package" were **skipped**.
- Step 14 ran but uploaded nothing: `No files were found with the provided path: D:\a\_temp/snapshot. No artifacts will
  be uploaded.`
- The run has 0 artifacts.

The test runner crashed twice. Both crashes have one cause:

1. **Batch `[D-H]`.** `EngineServeEndToEndTests.testARealRequestGoesThroughTheProtocolAndHooksChangeOnlyWithTheirSwitch`
   failed first:
   - `EngineServeEndToEndTests.swift:175: error: … XCTAssertNotNil failed` (no `state` within 30 s).
   - `:177: … XCTAssertTrue failed - the hook is set at start`.

   Then `Served.send(_:)` (`EngineServeEndToEndTests.swift:60`) wrote to a pipe whose engine was already gone:
   `Foundation/FileHandle.swift:709: Fatal error: 'try!' expression unexpectedly raised an error: … WindowsError Code=232`.
   Error 232 is "the pipe is being closed". The runner died, so the rest of the batch never ran (201 tests locally),
   including `testTheDemoServesStateTakesAnswersAndSettingsAndQuits`.
2. **Batch `[U-Z]`.** `WindowsTimeZoneTests.testAdoptingItMakesItFoundationsDefault` crashed in Foundation:
   `*** Program crashed: Illegal instruction …`. The stack is `Foundation.dll` ← `static WindowsTimeZone.adopt() + 36 at
   Sources\AgentHUDCore\Platform\Windows\WindowsTimeZone.swift:16:28` (`NSTimeZone.default = current()`). The rest of
   that batch never ran (110 tests locally).

- Totals of the batches that finished: 1150 executed, 3 skipped, 0 failed (113/126/125/201/255/76/254). Support's
  swift-testing: 9/9.

**Cause, reproduced locally outside the repository.** I built a scratch copy of `WindowsTimeZone`'s mapping and
`NSTimeZone.default = …` and ran it for several Windows zone names. I deleted the copy afterwards.

| Windows zone | ICU maps it to | `TimeZone(identifier:)` | `NSTimeZone.default = zone` |
| --- | --- | --- | --- |
| `UTC` | `Etc/UTC` | succeeds | **crashes** (`Exception c000001d`, illegal instruction), the same as CI |
| `Eastern Standard Time` | `America/New_York` | succeeds | works |
| `GMT Standard Time` | `Europe/London` | succeeds | works |
| `China Standard Time` | `Asia/Shanghai` | succeeds | works |
| `Greenwich Standard Time` | `Atlantic/Reykjavik` | succeeds | works |
| `UTC-11` | `Etc/GMT+11` | succeeds | works |
| `UTC-02` | `Etc/GMT+2` | succeeds | works |
| `UTC+12` | `Etc/GMT-12` | succeeds | works |
| `Dateline Standard Time` | `Etc/GMT+12` | succeeds | works |

What this means:

- GitHub's Windows runners use the `UTC` zone.
- `EngineServe` calls `WindowsTimeZone.adopt()` at start (`EngineServe.swift:67`). On such a machine,
  `agenthud-engine --serve` therefore dies before it writes `state`. That is why the end-to-end test failed and its next
  `send` hit a closed pipe.
- This is a product defect, not only a test problem: any user whose Windows zone is "(UTC) Coordinated Universal Time"
  would get a shell whose engine crashes at start.
- It does not show locally because this machine is in Eastern time.

**When it started.**

- It came in with M7 step 7 (`33c5782`, D-050). Windows run 39178306631 on `33c5782` failed with the same two crashes
  at the same lines.
- The run on step 8 (`d8ddb71`, 39179570219) was cancelled during its build.
- The last green Windows run is 39177665388 on step 6 (`7f7bba3`).

### Skips

- The 4 runtime skips, locally and in CI, are the four `…Probe` tests.
- All 34 skip-list patterns are registered in SKIPPED_TESTS.md §2 (checked by script, by class and test name).
- All 7 files excluded in `Package.swift` are registered in §1.
- Nothing unregistered was skipped.

## G4: PASS

- **Command:** `& test.ps1 -ScratchPath <build> -Log <tester7>\g4.log -Filter @('RecordCodingGoldenTests')`.
- **Duration:** 7 s, exit 0.
- **Result:** `√ Test run with 4 tests in 0 suites passed`.
  - `theRecordEncoderWritesTheGoldenSample`.
  - `millisecondDatesRoundTripTheGoldenSamples`.
  - `recordIdentitiesMatchTheGoldenSamples`.
  - `digestsMatchTheNISTVectors`.
- **CI:** the Support batch passed 9/9 in Windows CI and 10/10 in macOS CI.

## G5: PASS locally (the CI smoke step did not run)

- **`scripts\windows\test-dotnet.ps1`:** 3 s, exit 0.
  - `已通过! - 失败: 0，通过: 14，已跳过: 0，总计: 14 - AgentHUD.Protocol.Tests.dll`.
  - `已通过! - 失败: 0，通过: 26，已跳过: 0，总计: 26 - AgentHUD.Shell.Tests.dll`.
  - `Protocol fixtures: 22 valid, 15 invalid, 0 failure(s).`
  - This matches SKIPPED_TESTS' line of 40 C# tests.
- **`scripts\windows\smoke-shell.ps1 -Engine <build>\out\Products\Release-windows-x86_64\agenthud-engine.exe -Out
  <tester7>\snapshot`:** 5 s, exit 0. The build printed 0 warnings and 0 errors.
  - `Shell smoke test: 13 pictures in …\tester7\snapshot, status 0 after 3 s.`
  - Sizes: island-rest 992x67, island-open 992x780, island-usage 992x1798, card-question 992x1040, card-plan 992x826,
    event-reply-line 395x64, event-reply-card 992x364, event-quota-line 360x64, event-quota-card 992x558,
    event-credits-line 343x64, event-credits-card 992x460, settings 1091x976, statistics 1411x448.
- **What the pictures show.** I opened six of them.

| Picture | Shows | Matches its name |
| --- | --- | --- |
| `island-rest` | A dark rounded bar with the 17 vendor marks; Claude's mark has its orange dot | yes |
| `island-open` | The bar with "Needs approval / Run the test suite / `swift test --filter SyncRecordTests`" and Deny/Allow, then five queued lines (Avatar.tsx, Build for production, linear · create_issue, tsconfig.base.json, Which database?, Plan) | yes |
| `card-question` | "Asks a question / Which database?", the "1/2" badge, SQLite (One file) / Postgres / Other with "Type your own answer", Skip and a disabled Next, then the queue | yes |
| `event-quota-card` | Claude "Current session", "running low", burn-rate sentence, 12% used / 1h30m until empty / 1h12m next reset, the progress bar, "View usage statistics" | yes |
| `settings` | Appearance & language (System/Light/Dark, English), Startup (Launch at login), Clients (Client hooks with its description, "Wait for an answer: 10 minutes") | yes |
| `statistics` | "Recent usage, Excl. cache reads": Today 13M / Last 7 days 105M / Last 30 days 450M, cost and cache hits, stacked bars, top models and "3 more" | yes |

- **`scripts\windows\ui-check.ps1 -Engine <same exe>`:** 47 s. It ended with `UI check: every check passed.`
  - Every check passed:
    - PASS starting takes no focus
    - PASS the question waits in the queue
    - PASS clicking a queued line takes no focus
    - PASS Next waits for an answer
    - PASS an offered answer makes Next ready
    - PASS picking an answer takes no focus
    - PASS clicking the field takes the keyboard
    - PASS the field holds what was typed
    - PASS Enter goes on to the next question
    - PASS the keyboard stays through Next
    - PASS the answers are sent and the question leaves
    - PASS the keyboard goes back to the app that had it
    - PASS the plan waits in the queue
    - PASS an approved plan leaves
    - PASS --show-settings opens the settings window
    - PASS the wait's choices are the engine's words
    - PASS the engine saved the wait the window chose
    - PASS switching the hooks off asks first
    - PASS Cancel keeps the hooks on
    - PASS the dock rests on the primary display
    - PASS it starts at the top centre, Core's default
    - PASS the drop puts it on the left edge where it was let go
    - PASS the engine keeps the display on the left edge
    - PASS a full-screen app on a display steps its HUD aside until it goes
  - That is 24/24, with no SKIP: two displays, so the full-screen check ran.
  - Afterwards no `AgentHUD`/`agenthud-engine` process was left, and `HKCU\…\CurrentVersion\Run` has no AgentHUD entry,
    so launch at login did not touch the real profile.
- **CI:** the C# tests and the fixtures passed (step 4). The smoke test was skipped because of G3's failure, so the
  `shell-snapshot` artifact does not exist for `c6222d2`.

## G6: PASS

- **Command:** `python scripts\check-source-boundaries.py`, 1 s.
- **Output:** `Source boundaries and ignore rules passed.`
- **CI:** the same line in Windows step 3 and in the macOS `test` job.

## G7/G8 notes

1. **(G7/G3, blocking through G3) `WindowsTimeZone.adopt()` crashes the engine on a `UTC` Windows zone.**
   - Details are in G3: Foundation traps when `NSTimeZone.default` is set to ICU's `Etc/UTC`.
   - A guard should cover `adopt()` itself and every zone ICU can return. A test on a machine in this machine's zone does
     not see it; CI does, because the runner is in `UTC`.
2. **(G8) PROGRESS.md's M7 row says "CI green through step 8". That is not so.**
   - Windows run 39178306631 on step 7 (`33c5782`) failed with this crash.
   - Run 39179570219 on step 8 was cancelled.
   - Only the macOS `Source checks` runs were green for steps 7–9.
3. **The stack points to a fragile test helper, not to the engine.**
   - `EngineServeEndToEndTests.Served.send` uses `FileHandle.write(_:)`, which traps on a closed pipe.
   - A dead engine therefore takes the whole batch's runner down instead of failing one test.
4. **Minor visual points from the pictures (not failures).**
   - In `statistics`, "Fable 5.1" and "codex-auto-review" have the same purple dot, so two series look alike in every
     column.
   - In `card-question`, "Which database?" appears twice: as the card's title and as question 1/2's header.
5. **The real `%TEMP%` still grows (known issue).**
   - 107 top-level items appeared during my run, 72 of them `TemporaryDirectory.*` from the tests. The total is 3091.
   - I removed only my own 8.3 folder.
   - `M7-review-1.md` was written by the reviewer, not by me.

## Skipped tests and registration

| Skip | Kind | Registered |
| --- | --- | --- |
| `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe` | runtime (`AGENT_HUD_PROBE_…`) | yes, §3 |
| `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe` | runtime | yes, §3 |
| `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe` | runtime | yes, §3 |
| `SessionUsageProbeTests.testReportedSessionsUsageProbe` | runtime | yes, §3 |
| 34 patterns in `scripts/windows/skipped-tests.txt` | skip list | yes, all 34 in §2. Each passes on macOS (run 39180355391). |
| 7 files in `windowsSkippedTests` (`UnixSocketListenerTests`, `ChildProcessTests`, `InstanceLockTests`, `CodexDaemonOriginTransportTests`, `CodexDesktopTestServer`, `CodexDesktopPermissionsTests`, `CodexDesktopStreamTests`) | excluded files | yes, all 7 in §1 |
| Conditional runtime skips (no `node.exe`/`git.exe`/8.3 names/…) | runtime | none triggered locally |

In CI, the tests after the two crashes did not run: the rest of `[D-H]` and `[U-Z]`. They are not skips; they are
part of G3's failure.

TESTS: FAILURES
