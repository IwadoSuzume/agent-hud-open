# M5 test report, round 2

- Branch: `windows-port`. Head under test: `bb1ce7d` ("Windows port M5 round 2: a failed replace never costs the user
  their file"). M5 range: `505492b...bb1ce7d`. Round-2 change set: `c369f8d...bb1ce7d`, 18 files, +818/−65.
  - Code: `ClaudeSessionOrigins`, `HookCommand+Windows`, `HookSettings+Windows`, `ProviderHTTP+Windows`, `Win32`,
    `WindowsWebSocket`, `DeepSeekCredentialLocator`.
  - Tests: `ClientHooksTests`, `HookFormsWindowsTests`, `ProviderHTTPWindowsTests`, `ProviderPathsWindowsTests`,
    `WindowsExecutablesTests`.
  - Docs.
  - `Package.swift`, `scripts/` and `.github/` are unchanged in round 2.
- Run by: port-tester, 2026-10-18. Local times are the machine's (UTC−4). Machine: Windows 11 Pro 10.0.26200.
- The working tree was clean at `bb1ce7d` before and after the gates. I wrote only this report in the repository. I
  committed nothing and pushed nothing.
- **My one CI action:** a single `rerun-failed-jobs` of `Source checks` run 39104084904, at 06:39:23Z, as instructed (see
  G1).
- No other build was running when I started (no `swift`, `lld` or `clang` process). All my builds used
  `%LOCALAPPDATA%\agenthud-dev\build` through the junction `%LOCALAPPDATA%\agenthud-dev\src` (→
  `E:\桌面项目\agent-hud-open`).

## Round-1 BLOCKING items

| # | Round-1 finding | Round 2 |
| --- | --- | --- |
| 1 | `WindowsExecutablesTests.testClaudesEngineIsRecognisedAmongAHooksAncestors` failed on the runner's 8.3 `RUNNER~1` temporary folder, and locally with an 8.3 `TEMP` | **Resolved.** It passes in Windows CI run 39104084529, in the local default run, and in the local run with `TEMP`/`TMP` set to an 8.3 spelling (`C:\Users\suzume\AppData\Local\AGENTH~2\M5R2LO~1`): 7/7, 0 skipped. The test now also checks an ancestor and a home that are spelled short. It reports skipped only when the volume has no 8.3 names, and it did not skip in any of the three places. |
| 2 | G1 not green: upstream `StatsWindowLifecycleTests.testNativeRestoreFitsContentUpdatedWhileMiniaturized` | **Resolved after one re-run.** Attempt 1 failed with the same assertion as in round 1. Attempt 2, a re-run of the failed jobs only, passed. The run's conclusion is `success`. |

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | **PASS** (on attempt 2): run 39104084904 for head `bb1ce7d`. Attempt 1: `test` failure (1 upstream Desktop failure, the same as round 1). Attempt 2: `test`, `app` and `macos` all success. 2087 XCTest, 8 skipped, 0 failures. swift-testing 10 passed. All 34 skip-list tests pass on macOS. No new macOS warning. |
| G2 Windows build | PASS. CI step 10 is green on attempt 2 of 3: attempt 1 hit D-032's Touch file-in-use race, and the retry handled it. The local release build is green in 201.4 s. Library warnings equal the baseline exactly (6 lines, each once), both in CI and locally. |
| G3 Windows tests | PASS. CI and local agree exactly: **1430 executed, 1426 passed, 4 skipped, 0 failed**. The two sets of test-case names are identical. The 8.3-`TEMP` runs passed too. |
| G4 determinism | PASS (macOS CI, Windows CI, Windows local) |
| G5 UI | N/A (M7+) |
| G6 boundaries | PASS: locally, and in both CI jobs |
| M5 (a) `HookEngineEndToEndTests` ran | PASS: 4/4 executed and passed, locally and in CI. None was skipped. |
| M5 (b) skips registered, state line | PASS. All 34 skip-list entries and all 7 excluded files are in SKIPPED_TESTS.md. The 4 runtime skips are in §3. The new conditional (8.3) skips are registered and were not triggered. The state line "1426 pass, 4 runtime skips, 34 listed skips, 7 excluded files, 0 failures" matches CI and the local run. |
| M5 (c) no `agenthud-test` credential left | PASS: `cmdkey /list` shows 0 matching lines before, after G3 and at the end (count only) |
| M5 (c′) no `.agenthud-*` staged or backup file left | PASS: 0 files named `*.agenthud-*` anywhere under `%TEMP%` (a recursive search) before, after G3 and at the end. There were also 0 under the 8.3 scratch `TEMP`, which I then removed. |
| M5 (d) no stray `Debug-windows-x86_64`, no test preferences | PASS: the folder was absent throughout. There were 0 `*.plist` files in the real `%LOCALAPPDATA%` before and after; test.ps1 removed its 6. |
| M5 (e) nothing written to the real client folders | PASS: no hook, settings or MCP file changed. The only changes are Claude Code's own `.claude\backups` rotation and `.claude\skills\synced`. |
| M5 (f) flaky `FileChangeMonitorWindowsTests` test | did not fail: passed locally and in CI |
| B-001 tests | present and passing. `ProviderHTTPWindowsTests`: 10/10, including the new `testEveryRequestIsSentWithTheRulesAndCertificatesAreCheckedButForLoopback`. `WindowsCredentialsTests`: 3/3. Both in CI and locally. |
| G7 | review gate; observations below |
| G8 | notes below |

## BLOCKING findings

None.

## G1: PASS

`Source checks` run **39104084904**: workflow_dispatch on `windows-port`, head
`bb1ce7dd06a9c954ea9f824c0965659d2a0b7ad7`. The final state is `completed` / `success`, `run_attempt` 2.

| Attempt | Job | Conclusion | Times (UTC) |
| --- | --- | --- | --- |
| 1 | `test` (117606135998) | **failure** | Test step 06:27:31 to 06:37:10 |
| 1 | `app` (117606135809) | success | Build application 06:27:33 to 06:37:59; Verify local signature and resources: success |
| 1 | `macos` (117608032072) | failure (because `test` failed) | 06:38:07 |
| 2 | `test` (117608263801) | **success** | Check source boundaries: success; Test step 06:39:36 to 06:48:17 |
| 2 | `app` (117608264877) | success (carried over from attempt 1: the same step times) | — |
| 2 | `macos` (117609840141) | **success** | 06:48:24 |

### Attempt 1: the same upstream failure as round 1

```
Tests/AgentHUDDesktopTests/Stats/StatsWindowLifecycleTests.swift:46: error: -[AgentHUDDesktopTests.StatsWindowLifecycleTests
testNativeRestoreFitsContentUpdatedWhileMiniaturized] : XCTAssertEqualWithAccuracy failed: ("187.0") is not equal to
("480.0") +/- ("1.0") - A minimized window keeps its frame while caching the new content height
```

- `Executed 2087 tests, with 8 tests skipped and 1 failure (0 unexpected) in 387.716 seconds`.
- The test failed after 3.804 s. In round 1 it failed after 3.409 s.
- **The port did not cause this.** `git diff c258093 bb1ce7d -- Sources/AgentHUDDesktop Sources/AgentHUDOpenApp
  Tests/AgentHUDDesktopTests` is empty.
- **The runner did not change.** The image was `macos-15-arm64` 20260907.0337.1, with provisioner 20260828.587. That
  is the same image as M4 round 4's green run 39047601576, where the test passed in 1.698 s.

### Attempt 2: green

- `Executed 2087 tests, with 8 tests skipped and 0 failures (0 unexpected) in 374.474 seconds`.
- `testNativeRestoreFitsContentUpdatedWhileMiniaturized` passed (1.676 s).
- swift-testing: `✔ Test run with 10 tests passed after 1.047 seconds.` This includes `portableDigestsEqualCryptoKit`.
- 2087 is round 1's 2086 plus the new macOS-only `ClientHooksTests.testTheCommandLineSingleQuotesThePathForTheShell`,
  which passed. It pins the POSIX `'\''` quoting, as review round 1 asked.
- The 8 skips are the same as in M2–M5 round 1:
  - the four `…Probe` tests;
  - `ArtworkMemoryTests.testProbeWritesEveryBakedMarkBotAndAccent`;
  - `BotFrameTests.testFrameCost`;
  - `BotMarkTests.testAReminderMarkOpensAsItsLogoAndTurnsIntoItsBotOnceItsCardHasOpened`;
  - `IslandAnimationTests.testAGlowThatClosesStopsItsFrames`.
- All 34 `skipped-tests.txt` entries have a `passed` line on macOS.
- macOS warnings, as file:line: exactly round 1's set, nothing new. Core:
  - `DeepSeekQuestions:106`
  - `AntigravityCLI:18`

  Core tests:
  - `PermissionHookTests` 435/442/453
  - `PanelToolsSpanTests:91`
  - `DeepSeekProviderTests:525`
  - `CollectionSignalTests:331`
  - `UsageRefreshTests:73`

  Desktop tests:
  - `AgentSeparationTests` 136/209/243
  - `JoinedGlassTests` 192/246
  - `ScreenStyleHUDTests:254`
- `Source boundaries and ignore rules passed.`

## G2: PASS

### CI

`Windows port` run **39104084529**: a push of head `bb1ce7d`, job `swift` (117606132196), conclusion `success`.

- **Step 10, Build (release)** (`build.ps1 -c release`): success, 06:29:32Z to 06:38:33Z.
  - **2 attempts.** Attempt 1 failed in 15 s: `error: Touch …\AgentHUDOpen_AgentHUDCoreTests.bundle failed …` and `The
    process cannot access the file because it is being used by another process.`. build.ps1 then printed `swift build
    hit a file in use (attempt 1 of 3)` and retried.
  - Attempt 2 ended `Build complete! (523.97 secs)`.
  - This is the cold-build Touch race that D-032's retry exists for. The port did not cause it.
- **Warnings: exactly the 6 baseline lines, each once.** No `wchar_t` line appeared in step 10.
  - `MCPStdio.swift:59` `strerror`
  - `PermissionHookClient.swift:38` `close`
  - `ZstandardReader.swift:46` `close`
  - `AntigravityCLI.swift:18` `init(cString:)`
  - `CodexDesktopStream.swift:170` `wait(until:)`
  - `DeepSeekQuestions.swift:106` `await`
- **Step 12, Compile a smoke package:** success.

### Local

- Command: `swift build -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build`, from the junction at `bb1ce7d`,
  with the PROGRESS.md Swift environment. I redirected the output through `cmd /c "… > log 2>&1"`.
- Result: exit 0, `Build complete! (201.37 secs)`. Wall clock 02:29:19 to 02:32:44.
- `release\agenthud-engine.exe` was rebuilt (02:32).
- There was no `error:` line and no file-in-use line.
- **Warnings: the same 6 baseline lines, each once.** No new library warning.

### Test-build warnings (G3's build; outside G2 since D-033)

- CI's test build (`Build complete! (197.94 secs)`) printed:
  - the `wchar_t` toolchain baseline;
  - the 6 library lines;
  - the upstream test lines that round 1 listed: `PermissionHookTests` 375/435/442/453, `MCPStdioTests` 80/81/84,
    `PanelToolsSpanTests:91`, `CollectionSignalTests:331`, `UsageRefreshTests:73`, `DeepSeekProviderTests:525` (×2).
- **None of the port's test files, including the five changed in round 2, printed a warning.**
- The local test build was incremental (`Build complete! (22.27 secs)`). It printed only `DeepSeekProviderTests:525`
  (×2).

## G3: PASS

### CI (step 11 of run 39104084529, 06:38:33Z to 06:45:05Z)

- Build-first step: 1 attempt, no file-in-use line.
- Support: `Test run with 9 tests in 0 suites passed after 0.659 seconds.`
- Core, 9 batches: 113 + 126 + 125 + 191 + 200 + 255 + 71 + 242 + 107 = **1430 executed: 1426 passed, 4 skipped,
  0 failed**.
- `Removed 6 test preference file(s) from C:\Users\runneradmin\AppData\Local`.

### Local (default `TEMP`)

- Command: `%LOCALAPPDATA%\agenthud-dev\src\scripts\windows\test.ps1 -ScratchPath %LOCALAPPDATA%\agenthud-dev\build -Log
  <scratch>\m5r2\g3.log`.
- Setup: Windows PowerShell 5.1, the PROGRESS.md environment, the junction, `bb1ce7d`.
- Result: exit 0 in **207 s** (02:32:57 to 02:36:24).
- Build-first step: 1 attempt. Support: 9 passed.
- Core: the same 9 batch sizes as CI, **1430 executed: 1426 passed, 4 skipped, 0 failed**.
- `Removed 6 test preference file(s) from C:\Users\suzume\AppData\Local`.
- test.ps1's `agenthud-testprofile-<guid>` was removed: 0 were left in `%TEMP%`.
- **CI and local executed the same 1430 test cases**: a sorted diff of the names is empty.

### Local, with `TEMP`/`TMP` set to an 8.3 spelling (round-1 BLOCKING 1)

- The scratch folder: `%LOCALAPPDATA%\agenthud m5r2 short temp\m5r2 long name temp`. Its short spelling is
  `C:\Users\suzume\AppData\Local\AGENTH~2\M5R2LO~1`.
- I set that short spelling as `TEMP`/`TMP` and ran test.ps1 once for each class:

  | Filter | Result |
  | --- | --- |
  | `AgentHUDCoreTests.WindowsExecutablesTests` | **7 executed, 0 failures, 0 skipped**, exit 0 (round 1: 2 failures on lines 35/36) |
  | `AgentHUDCoreTests.HookFormsWindowsTests` | **20 executed, 0 failures, 0 skipped**, exit 0 |

- The short-spelling cases of `testClaudesEngineIsRecognisedAmongAHooksAncestors` ran. The test did not skip, and it
  skips only when the fixture has no 8.3 name.
- Afterwards the scratch `TEMP` held only SwiftPM lock files, `org.swift.*` caches and 30 swift-corelibs
  `TemporaryDirectory.*` folders. There was no fixture and no `.agenthud-*` file. I removed the whole scratch folder.
- (My first attempt passed both filters to one `-File` call. PowerShell then delivered the two filters as one string,
  and the run matched no test cases. I re-ran with one filter per call.)

### Compared with round 1 (1425 executed)

The difference is +5 executed and +5 passed. All five are new Windows tests:

| Test | Local | CI |
| --- | --- | --- |
| `HookFormsWindowsTests.testAFailedReplaceLeavesTheUsersFileWhereItWas` (seams for 1177/1176/1175) | passed 0.026 s | passed |
| `HookFormsWindowsTests.testASettingsFileTheClientHoldsIsLeftAsItWas` (a real `ReplaceFileW` failure) | passed 0.010 s | passed |
| `HookFormsWindowsTests.testASettingsFileDeeperThanMaxPathIsWritten` | passed 0.023 s | passed |
| `HookFormsWindowsTests.testAZipsCopyIsTransientWhicheverWayTheTemporaryFolderIsSpelled` | passed 0.008 s | passed |
| `ProviderHTTPWindowsTests.testEveryRequestIsSentWithTheRulesAndCertificatesAreCheckedButForLoopback` | passed | passed |

- The batches changed accordingly: batch 4 went from 187 to 191, and batch 7 from 70 to 71.
- `ProviderPathsWindowsTests`' DeepSeek case now asserts nil against an injected empty npm profile. It passed in both
  places.

### M5 (a): `HookEngineEndToEndTests`: PASS

All 4 executed and passed, locally and in CI:

- `testClaudeCodesHookReachesTheEngineAndCarriesTheAnswerBack`
- `testWithoutARunningEngineTheHookPrintsNothingAndLeavesTheClientsOwnPrompt`
- `testTheEngineServesMCPOnItsStandardInputAndOutput`
- `testAClientThatNeverClosesItsPipeIsLetGoByTheWatchdog`

None was skipped. No `HUD 端到端 *` folder was left in `%TEMP%`.

### M5 (f): the flaky test

`FileChangeMonitorWindowsTests.testAWatchedDirectoryThatGoesAwayAsksForAFullScan` passed locally and in CI. No single
re-runs were needed.

## M5 (b): skips registered: PASS

- **Skip list.** `scripts/windows/skipped-tests.txt` is unchanged: 34 unique entries. All 34 are named in SKIPPED_TESTS.md
  §2.
  - The only name in §2 that is not in the list is the Windows counterpart `…/testAZipsCopyRemovableAndNetworkPlacesAreTransient`.
  - None of the 34 ran on Windows, locally or in CI.
  - All 34 pass on macOS (attempt 2).
- **Excluded files.** `windowsSkippedTests` in `Package.swift` has 7 files, and all 7 are §1 rows. §1 has 7 rows.
- **Runtime skips.** There were 4, the same in CI and locally, all in §3:
  - `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe`
  - `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe`
  - `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe`
  - `SessionUsageProbeTests.testReportedSessionsUsageProbe`
- **New conditional skips are registered in §3.** None was triggered in any run:
  - the 8.3 skips of `testAZipsCopyIsTransientWhicheverWayTheTemporaryFolderIsSpelled` and
    `testClaudesEngineIsRecognisedAmongAHooksAncestors`;
  - the no-PowerShell skip of `testQwenCodesPowerShellRunsTheCommand`;
  - the no-Git-Bash skip of `testCodeBuddysGitBashRunsTheCommand`.

  The new §4 lists the `#if !os(Windows)` case of `MCPAppChannelTests` and the macOS-only `ClientHooksTests` test.
- **State line.** "1426 pass, 4 runtime skips, 34 listed skips, 7 excluded files, 0 failures" **matches both CI and the
  local run** exactly.

## M5 (c), (c′), (d), (e): the real profile and the temporary folder

### Snapshots

I took stat-only snapshots: names, sizes and modification times, at depth ≤ 2, without the transcript, log and cache
folders. I read no file. The snapshots were at 02:28:52 (before G2), 02:37:15 (after G3) and 02:49:36 (end, after the
8.3 runs and CI).

| Check | Before | After G3 | End |
| --- | --- | --- | --- |
| `cmdkey /list` lines matching `agenthud-test` (count only) | 0 | 0 | 0 |
| Files named `*.agenthud-*` under `%TEMP%`, recursive | 0 | 0 | 0 |
| `%LOCALAPPDATA%\Debug-windows-x86_64` | absent | absent | absent |
| `*.plist` directly in the real `%LOCALAPPDATA%` | 0 | 0 | 0 |
| `agenthud-testprofile-*` in `%TEMP%` | 0 | 0 | 0 |
| `%APPDATA%\Agent HUD Open` modification time | 2026-10-16 17:20:19 | same | same |
| `.qwen`, `.codebuddy`, `.qoder` | absent | absent | absent |
| `.codex`, `.copilot`, `.claude` folder times | unchanged | unchanged | unchanged |

### What changed in `.claude`

Between the first and last snapshot, only `.claude\backups\.claude.json.backup.*` rotated and
`.claude\skills\synced\…` changed. Both are the running Claude Code client's own activity.

Every other entry of the six client folders is identical. No `settings.json`, hook or MCP file changed.

### Round 2's fixture folders in `%TEMP%`

| Fixture | Left after G3 |
| --- | --- |
| `HUD temporary folder 临时 *` | 0 |
| `HUD 端到端 *` | 0 |
| `agenthud 程序 *` | 0 |
| `agenthud 路径 *` | 0 |
| `off 关闭-*` | 0 |

- One `HUD Hooks 回调 9610DF28-…` folder is in `%TEMP%`. It was created on **2026-10-17 at 08:15**, before M5's first
  test round, and holds only a fixture engine. No run of this round left it.
- The MAX_PATH test's tree, over 300 characters, was removed with its home, because no new `HUD Hooks 回调` folder
  appeared.

## G4: PASS

The four Support golden tests passed in all three places:

- `recordIdentitiesMatchTheGoldenSamples`
- `digestsMatchTheNISTVectors`
- `millisecondDatesRoundTripTheGoldenSamples`
- `theRecordEncoderWritesTheGoldenSample`

| Where | Result |
| --- | --- |
| macOS CI | 10/10 passed, including `portableDigestsEqualCryptoKit` |
| Windows CI | 9/9 passed |
| Windows local | 9/9 passed |

`git diff 505492b bb1ce7d -- Sources/AgentHUDSupport Tests/AgentHUDSupportTests` is empty.

## G6: PASS

- `python scripts\check-source-boundaries.py` at `bb1ce7d`: `Source boundaries and ignore rules passed.`, exit 0.
- It also passed in CI: step 3 of the Windows job, and the macOS `test` job in both attempts.

## D-006

`git diff c258093 bb1ce7d` is 0 bytes for all six `windowsReplaced` files:

- `System/UnixSocket.swift`
- `System/UnixSocketListener.swift`
- `System/ChildProcess.swift`
- `System/FileChangeMonitor.swift`
- `System/InstanceLock.swift`
- `Providers/Codex/CodexDesktopIPC.swift`

## G7 (observations, for the reviewer)

- **The shared files keep their macOS paths.**
  - `ClaudeSessionOrigins.engineArguments`: the new long-path comparison is inside `#if os(Windows)`, and the `#else`
    line is unchanged.
  - `DeepSeekCredentialLocator.module(home:)`: the macOS branch now calls a private `module(roots:cache:)` with the same
    roots and cache as before.
  - macOS ran the shared tests green on attempt 2.
- **`HookSettings.replaceKeepingSecurity` has a seam with the system call as its default.** I checked its behaviour only
  through the tests:
  - 1177 (old file moved to the backup), 1176 and 1175 each leave the original content in place and no `.agenthud-`
    file.
  - A real failure, a handle held without `FILE_SHARE_DELETE`, leaves the file unchanged and nothing beside it.
  - A later successful replace removes the backup.

  All of these passed under a long and under an 8.3 `TEMP`.
- **The 8.3 handling is now tested on this machine, not only on the runner.** Both
  `testClaudesEngineIsRecognisedAmongAHooksAncestors` and `testAZipsCopyIsTransientWhicheverWayTheTemporaryFolderIsSpelled`
  build an 8.3 spelling with `GetShortPathNameW` on a fixture folder whose long name needs one, so they run whatever
  `TEMP` is.

## G8: notes (non-blocking)

1. **The upstream macOS test `StatsWindowLifecycleTests.testNativeRestoreFitsContentUpdatedWhileMiniaturized` has now
   failed on two consecutive dispatches** (39102050317, and 39104084904 attempt 1), with the same values (187 vs 480).
   It passed on a re-run, on the same runner image as M4 round 4.
   - The failing attempts took about 3.4–3.8 s. The passing attempts took about 1.7 s.
   - This suggests a timing dependency in the upstream test.
   - PROGRESS "Known issues" could record it, and say that one `rerun-failed-jobs` is the agreed response, so that a
     future G1 is not read as a regression.
2. **CI step 10 needed D-032's retry** (attempt 1 of 3, Touch file-in-use on the test bundle). It worked as designed.
   This only confirms that the retry is still needed on cold runner builds.
3. **PROGRESS.md's M5 row** can now record round 2's CI results:
   - Windows run 39104084529: 1430 executed, 1426 passed, 4 skipped, 0 failed.
   - macOS run 39104084904: green on attempt 2, 2087 XCTest.

## Skipped tests

| Kind | Count | Registered |
| --- | --- | --- |
| Excluded files (`windowsSkippedTests`) | 7 files | yes, §1: an exact match; the six replaced sources are unchanged from `c258093` |
| Skip list (`skipped-tests.txt`) | 34 tests | yes: all 34 are named in §2; none ran on Windows; all 34 pass on macOS |
| Runtime skips (`XCTSkip`) | 4 tests, the same in CI and locally (the 4 opt-in probes) | yes, §3 |
| Conditional runtime skips (no `node.exe`, no `git.exe`, no 8.3 names, no Windows PowerShell, no Git Bash) | 0 triggered | yes, §3; the two new 8.3 rows and the PowerShell and Git Bash rows were added in round 2 |
| Cases left out inside a running test (`#if !os(Windows)`) | 2 (`ClientHooksTests/testTheCommandLineSingleQuotesThePathForTheShell`, a case of `MCPAppChannelTests/testWithNoApplicationServingTheSocketACallSaysNotRunning`) | yes, §4 |
| Support `portableDigestsEqualCryptoKit` (compiled only with CryptoKit) | 1 | yes (AgentHUDSupportTests section) |

## Verdict summary

| Gate | Verdict |
| --- | --- |
| G1 | PASS (run 39104084904, `success` on attempt 2 after one `rerun-failed-jobs`; attempt 1 failed only on the upstream `StatsWindowLifecycleTests` test, the same assertion as round 1; attempt 2 ran 2087 XCTest with 8 skipped and 0 failures, and 10 swift-testing) |
| G2 | PASS (CI step 10 green after D-032's file-in-use retry; local release build 201.4 s; warnings equal the baseline in both) |
| G3 | PASS (CI and local: 1430 executed / 1426 passed / 4 skipped / 0 failed, the same cases; with an 8.3 `TEMP`: `WindowsExecutablesTests` 7/7, `HookFormsWindowsTests` 20/20) |
| G4 | PASS |
| G5 | N/A |
| G6 | PASS |
| M5 (a) end-to-end tests ran | PASS (4/4, local and CI) |
| M5 (b) skips registered | PASS (34 + 7 + 4; state line matches CI and local) |
| M5 (c) test credentials | PASS (0 `agenthud-test` matches) |
| M5 (c′) `.agenthud-*` leftovers | PASS (0 under `%TEMP%`, 0 under the 8.3 scratch `TEMP`) |
| M5 (d) stray folder / preferences | PASS |
| M5 (e) real client folders | PASS (no hook, settings or MCP file changed) |
| M5 (f) flaky test | did not fail |
| B-001 tests | present; 13/13 pass in CI and locally |
| Round-1 BLOCKING 1 (8.3 ancestry test) | resolved |
| Round-1 BLOCKING 2 (G1 red) | resolved on re-run |
| G7 | observations only |
| G8 | 3 non-blocking notes |

BLOCKING findings: none.

TESTS: ALL_PASS
