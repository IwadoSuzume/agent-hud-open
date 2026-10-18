# M5 test report, round 1

- Branch: `windows-port`. Head under test: `c369f8d` ("Windows port M5: hooks and MCP on Windows"). M5 range:
  `505492b...c369f8d`, 46 files, +1937/−94. M4 closed at `505492b` without approval (BLOCKERS.md B-001). The two tests
  B-001 asked for are in this range and are checked below: `ProviderHTTPWindowsTests` (WinHTTP) and
  `WindowsCredentialsTests` (Credential Manager).
- Run by: port-tester, 2026-10-18. Local times are the machine's (UTC−4). Machine: Windows 11 Pro 10.0.26200.
- The working tree was clean at `c369f8d` before and after the gates. I wrote only this report in the repository. I
  committed nothing and pushed nothing. I re-ran no CI job.
- I saw no other build on the machine (no `swift`, `lld` or `clang` process when I started). All my builds used
  `%LOCALAPPDATA%\agenthud-dev\build` through the junction `%LOCALAPPDATA%\agenthud-dev\src` (→
  `E:\桌面项目\agent-hud-open`).

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | **FAIL**: run 39102050317 ended `failure`. 2086 XCTest, 8 skipped, **1 failure**: `AgentHUDDesktopTests.StatsWindowLifecycleTests.testNativeRestoreFitsContentUpdatedWhileMiniaturized`, an upstream Desktop UI test. The port has changed no Desktop file. swift-testing: 10 passed. All 34 skip-list tests pass on macOS. No new macOS warning. |
| G2 Windows build | PASS: CI step 10 green (1 attempt). Local release build green, `agenthud-engine.exe` built. Library warnings equal the baseline exactly, both in CI and locally. |
| G3 Windows tests | **FAIL in CI**, PASS locally. CI: 1425 executed, 1420 passed, 4 skipped, **1 failed** (`WindowsExecutablesTests.testClaudesEngineIsRecognisedAmongAHooksAncestors`). Local: 1425 executed, 1421 passed, 4 skipped, 0 failed. **The CI failure reproduces locally when `TEMP` is an 8.3 short spelling.** |
| G4 determinism | PASS (macOS CI, Windows CI, Windows local) |
| G5 UI | N/A (M7+) |
| G6 boundaries | PASS (local, and in both CI jobs) |
| M5 (a) `HookEngineEndToEndTests` ran | PASS: all 4 executed and passed, locally and in CI. None was skipped. |
| M5 (b) skips registered, state line | PASS: 34/34 skip-list entries and 7/7 excluded files are named in SKIPPED_TESTS.md. The state line matches the local run. It does not match CI, which has 1 failure. |
| M5 (c) no `agenthud-test-*` credential left | PASS: 0 matches before, 0 after G3, 0 at the end |
| M5 (d) no stray `Debug-windows-x86_64`, no test preferences | PASS: folder absent before and after; 0 `*.plist` in the real `%LOCALAPPDATA%` before and after (test.ps1 removed its 6) |
| M5 (e) nothing written to the real client folders | PASS: no hook or settings file changed. The only changes in `.claude` are Claude Code's own `backups\` rotation and `skills\synced`, from the running client. |
| M5 (f) flaky `FileChangeMonitorWindowsTests` test | did not fail: passed locally and in CI, so no single re-runs were needed |
| B-001 tests | present and passing: `ProviderHTTPWindowsTests` 9/9 and `WindowsCredentialsTests` 3/3, both in CI and locally |
| G7 | review gate; observations below |
| G8 | notes below |

## BLOCKING findings

1. **The Windows CI fails (G3): an M5 test assumes the temporary folder has no 8.3 spelling.**

   **The failure.** `WindowsExecutablesTests.testClaudesEngineIsRecognisedAmongAHooksAncestors` is new in M5's range. It
   fails in run 39102050084, step 11, on the `[U-Z]` batch:

   ```
   WindowsExecutablesTests.swift:35: error: … XCTAssertEqual failed: ("nil") is not equal to ("Optional("-p")") -
   WindowsExecutablesTests.swift:36: error: … XCTAssertTrue failed - a print-mode run asks no one
   ```

   Line 33 passes in the same run, so `ClaudeEngineLocator.processPaths` finds the fixture engine. After that,
   `ClaudeSessionOrigins.engineArguments` does not match the fixture engine against those paths.

   **Reproduced locally.** I ran `test.ps1 -Filter AgentHUDCoreTests.WindowsExecutablesTests` twice:
   - With `TEMP`/`TMP` set to the short spelling of a folder whose long name has spaces
     (`C:\Users\suzume\AppData\Local\AGENTH~1\M5R1LO~1`): **the same 2 failures on lines 35 and 36**. The other 6 tests
     passed.
   - With the same folder's long spelling: all 7 passed.

   On the runner, the temporary folder is the 8.3 `C:\Users\RUNNER~1\…`, as found in M3 round 2.

   **Most likely cause** (from reading the code; I made no source change):
   - `engineArguments` (`Hooks/ClaudeSessionOrigins.swift:111`) puts the ancestor's executable through
     `resolvingSymlinksInPath()`. On Windows, that gives the long final path.
   - `processPaths` (`Providers/Claude/ClaudeEngineLocator.swift`, the Windows branch) keeps each candidate in its given
     spelling: `WindowsExecutables.program(_).path`, which is not resolved.
   - The case-insensitive comparison (`:115`) then compares two spellings of the same file.
   - `ClaudeHeadlessRuns.headless` uses the same paths, which is why line 36 fails too.

   **Why this matters outside the test.** The same mismatch happens whenever a candidate's home or `PATH` entry is
   written in its short form. The hook then does not recognise its Claude Code host (session origin, print-mode
   detection).

   **Suggested fix.** Normalise both sides the same way: give `processPaths` the final path, or compare the final paths
   of both. At minimum, resolve the fixture's path as the M3 round-2 tests do. Also add a Windows test with an 8.3
   home, so the fix is checked on this machine and not only on the runner.

2. **G1 is not green for the head.** `Source checks` run 39102050317, job `test`, failed on:

   ```
   Tests/AgentHUDDesktopTests/Stats/StatsWindowLifecycleTests.swift:46: error: -[AgentHUDDesktopTests.StatsWindowLifecycleTests
   testNativeRestoreFitsContentUpdatedWhileMiniaturized] : XCTAssertEqualWithAccuracy failed: ("187.0") is not equal to
   ("480.0") +/- ("1.0") - A minimized window keeps its frame while caching the new content height
   ```

   The evidence says this is a flaky AppKit timing test, not a regression:
   - `git diff c258093 c369f8d -- Sources/AgentHUDDesktop Sources/AgentHUDOpenApp Tests/AgentHUDDesktopTests` is empty.
   - The M5 changes to shared Core files compile to the same code on macOS: every addition is inside `#if os(Windows)`,
     with the old line in `#else`.
   - The same test passed in every earlier `Source checks` run, including 39047601576 (M4 round 4: 2086, 0 failures).

   Even so, TASK.md §5 needs a `success` run for the head, so G1 cannot pass. **Suggestion:** re-run the `test` job (or
   dispatch again on the fixed head) and confirm that it passes.

## G1: FAIL

`Source checks` run **39102050317** was a workflow_dispatch on `windows-port`, head `c369f8d`. It ended `completed` /
`failure`.

| Job | Conclusion | Steps |
| --- | --- | --- |
| `test` (117600149333) | **failure** | Check source boundaries: success. Test: failure (05:52:45Z to 06:04:22Z). |
| `app` (117600149508) | success | Build application: success (05:52:42Z to 05:59:30Z). Verify local signature and resources: success. |
| `macos` (117602173584) | failure | "Tests and application passed": failure, because `test` failed. |

What the `test` log shows:

- XCTest: `Executed 2086 tests, with 8 tests skipped and 1 failure (0 unexpected) in 444.037 (444.230) seconds`. The
  count is the same as in M2–M4.
- The 8 skips are the same as in M4: the four `…Probe` tests, `ArtworkMemoryTests.testProbeWritesEveryBakedMarkBotAndAccent`,
  `BotFrameTests.testFrameCost`, `BotMarkTests.testAReminderMarkOpensAsItsLogoAndTurnsIntoItsBotOnceItsCardHasOpened`
  and `IslandAnimationTests.testAGlowThatClosesStopsItsFrames`.
- swift-testing: `✔ Test run with 10 tests passed after 1.338 seconds.` This includes `portableDigestsEqualCryptoKit`.
- **No shared test is skipped on macOS without a record.** All 34 `skipped-tests.txt` entries have a `passed` line on
  macOS. This includes the 3 new M5 entries (`ClientHooksTests/…KeepsItsPermissions`, `MCPToolsOffTests` ×2).
- **The shared test files M5 changed all pass on macOS, with no failure:**

  | Test class | Passed |
  | --- | --- |
  | `AttentionHookTests` | 6 |
  | `ClaudeSessionOriginsTests` | 8 |
  | `ClientHooksTests` | 4 |
  | `CodexSessionOriginsTests` | 6 |
  | `CompactionHookTests` | 6 |
  | `CompletionHooksTests` | 7 |
  | `PermissionHookTests` | 35 |
  | `MCPAppChannelTests` | 10 |
  | `CopilotProviderTests` | 10 |
  | `QwenProviderTests` | 4 |

- **macOS warnings: no new line.**
  - `PermissionHookTests.swift` warns at 435/442/453. These are M4's 423/430/441, moved by 12 lines by M5's additions;
    `git blame` shows upstream lines.
  - The rest is M4's list: `AgentSeparationTests` 136/209/243, `JoinedGlassTests` 192/246, `ScreenStyleHUDTests:254`,
    `PanelToolsSpanTests:91`, `CollectionSignalTests:331`, `UsageRefreshTests:73`, `DeepSeekProviderTests:525`,
    `DeepSeekQuestions:106`, `AntigravityCLI:18`.
- `Source boundaries and ignore rules passed.`

## G2: PASS

### CI

`Windows port` run **39102050084** was a push of head `c369f8d`. Job `swift` (117600146987) ended `failure`, in
step 11 (G3).

- **Step 10, Build (release)** (`build.ps1 -c release`): **success**, 05:54:37Z to 06:03:35Z, `Build complete! (527.90
  secs)`.
  - It took 1 attempt. The log has no "being used by another process" or "file in use" line.
  - Warnings: **exactly the 6 baseline warnings, each once**:
    - `MCPStdio.swift:59` `strerror`
    - `PermissionHookClient.swift:38` `close`
    - `ZstandardReader.swift:46` `close`
    - `AntigravityCLI.swift:18` `init(cString:)`
    - `CodexDesktopStream.swift:170` `wait(until:)`
    - `DeepSeekQuestions.swift:106` `await`
  - There is no `wchar_t` line in step 10.
  - `MCPStdio`'s line moved from 54 to 59 because M5 added the `_setmode` block above it. The `strerror` line itself is
    upstream's and unchanged.
- Step 12 (Compile a smoke package) was skipped because step 11 failed.

### Local

- Command: `swift build -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build`, with the PROGRESS.md Swift
  environment, from the junction at `c369f8d`. Output was redirected through `cmd /c "… > log 2>&1"`.
- Result: exit 0, `Build complete! (184.66 secs)`. Wall clock: 01:54:14 to 01:57:22.
- The new product `agenthud-engine.exe` was built in `release\`.
- There was no `error:` and no file-in-use line.
- **Warnings: the same 6 baseline warnings, each once.** No new library warning.

### Test-build warnings (G3's build; outside G2 since D-033)

- CI's test build (`Build complete! (201.98 secs)`) printed the `wchar_t` baseline (16×), the 6 library lines, and
  these upstream test lines:
  - `MCPStdioTests.swift:80/81/84`
  - `PanelToolsSpanTests:91`
  - `CollectionSignalTests:331`
  - `UsageRefreshTests:73`
  - `DeepSeekProviderTests:525` (×2)
  - `PermissionHookTests.swift:375` (`createFile` result unused) and `:435/442/453` (`String??` coerced). This file is
    built on Windows for the first time, now that M5 took it out of `windowsSkippedTests`.
- `git blame` shows all of these are upstream lines (Jazzen Chen, 2026-10-14). The port's own test files print
  nothing.
- **M4 round 4's two port-line warnings are fixed.** `ProviderPathsWindowsTests.swift:103/111` no longer warn: the
  `try` was dropped, and `String(describing:)` is used.
- The local test build was incremental (`Build complete! (27.26 secs)`). It printed a subset of the same lines, and
  nothing else.

## G3: FAIL (CI) / PASS (local)

### CI (step 11 of run 39102050084, 06:03:35Z to 06:10:25Z)

- Build-first step: 1 attempt.
- Support: `Test run with 9 tests in 0 suites passed after 0.714 seconds.`
- Core, 9 batches: 113 + 126 + 125 + 187 + 200 + 255 + 70 + 242 + 107 = **1425 executed: 1420 passed, 4 skipped,
  1 failed** (2 assertion failures in the last batch, `[U-Z]`; see BLOCKING 1).
- `Removed 6 test preference file(s) from C:\Users\runneradmin\AppData\Local`.

### Local

- Command: `%LOCALAPPDATA%\agenthud-dev\src\scripts\windows\test.ps1 -ScratchPath %LOCALAPPDATA%\agenthud-dev\build -Log
  <scratch>\m5r1\g3.log`.
- Setup: Windows PowerShell 5.1, the PROGRESS.md environment, the junction, `c369f8d`.
- Result: exit 0 in **203 s** (01:57:38 to 02:01:01).
- Build-first step: 1 attempt.
- Support: 9 passed.
- Core: the same 9 batch sizes as CI, **1425 executed: 1421 passed, 4 skipped, 0 failed**.
- `Removed 6 test preference file(s) from C:\Users\suzume\AppData\Local`.
- test.ps1 made its own `agenthud-testprofile-<guid>` and removed it: 0 were left in `%TEMP%`.
- **The CI and local sets of 1425 test cases are identical** (a sorted diff of the names finds no difference). The only
  difference in outcome is BLOCKING 1.
- **Reproduction of the CI failure.** `test.ps1 -Filter AgentHUDCoreTests.WindowsExecutablesTests`, with `TEMP`/`TMP`
  set to an 8.3 spelling: 7 executed, 2 failures (lines 35 and 36), exit 1. With the long spelling of the same folder:
  7 passed, exit 0. I removed the scratch folder afterwards.

### Compared with M4 round 4 (1343 executed)

The difference is +82 executed, +82 passed. I did not attribute every one of the 82, but the new Windows classes run:

| Class | Tests |
| --- | --- |
| `HookFormsWindowsTests` | 16 |
| `ProviderHTTPWindowsTests` | 9 |
| `WindowsWebSocketTests` | 5 |
| `HookEngineEndToEndTests` | 4 |
| `WindowsCredentialsTests` | 3 |
| `MCPToolsOffWindowsTests` | 2 |

In addition:

- the now-built `PermissionHookTests` and `MCPAppChannelTests` (taken out of `windowsSkippedTests`), minus the 3 new
  skip-list entries;
- new cases in `WindowsExecutablesTests` and `ChildProcessWindowsTests`.

### M5 (a): `HookEngineEndToEndTests`: PASS

All 4 executed and passed in both places. None was skipped. The class has no `XCTSkip`: a missing
`agenthud-engine.exe` throws, so the test fails rather than skips.

| Test | Local | CI |
| --- | --- | --- |
| `testClaudeCodesHookReachesTheEngineAndCarriesTheAnswerBack` | 0.178 s | passed |
| `testWithoutARunningEngineTheHookPrintsNothingAndLeavesTheClientsOwnPrompt` | 0.118 s | passed |
| `testTheEngineServesMCPOnItsStandardInputAndOutput` | 0.114 s | passed |
| `testAClientThatNeverClosesItsPipeIsLetGoByTheWatchdog` | 6.565 s | passed |

Its homes (`HUD 端到端 <UUID>` in `%TEMP%`) were removed: none was left.

### B-001's tests

| Class | Local | CI | Tests |
| --- | --- | --- | --- |
| `ProviderHTTPWindowsTests` | 9/9 passed | 9/9 passed | body limit, unreachable host, timeout, redirect not followed, request as sent, unsafe request not sent, authentication challenge, error status, no cookie |
| `WindowsCredentialsTests` | 3/3 passed | 3/3 passed | `…ReadFromTheServicesEmptyUser`, `…AnotherUsersCredentialIsNotTheActiveAccount`, `…NotUTF8OrIsEmptyIsNoToken` |

### M5 (f): the flaky test

`FileChangeMonitorWindowsTests.testAWatchedDirectoryThatGoesAwayAsksForAFullScan` passed locally (0.001 s) and in CI.
It did not fail, so I made no single-test re-runs.

## M5 (b): skips registered: PASS

- **Skip list:** `scripts/windows/skipped-tests.txt` has **34 unique entries**. I parsed the `` `Class/test` ``,
  `` `…/test` `` and `×3 (…)` names of SKIPPED_TESTS.md §2. They are exactly the same 34 names: none is only in the
  file, and none is only in the doc.
  - None of the 34 ran on Windows, locally or in CI.
  - All 34 pass on macOS.
- **Excluded files:** `windowsSkippedTests` in `Package.swift` has **7 files**. All 7 are rows of §1, and §1 has
  7 rows.
  - M5 removed `MCP/MCPAppChannelTests.swift` and `Hooks/Permission/PermissionHookTests.swift` from the list. Both now
    build and pass on Windows.
- **Runtime skips:** 4, in both places, all in §3: `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe`,
  `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe`,
  `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe` and `SessionUsageProbeTests.testReportedSessionsUsageProbe`.
  No conditional skip (Node, Git, 8.3) triggered.
- **State line:** "1421 pass, 4 runtime skips, 34 listed skips, 7 excluded files, 0 failures". It **matches the local
  run** exactly. CI measured 1420 passed and 1 failure (BLOCKING 1).

## M5 (c), (d), (e): the real profile

I took stat-only snapshots: names, sizes and modification times, at depth ≤ 2, without the transcript, log and cache
folders. I read no file. The snapshots were at 01:54:09 (before G2), 02:01:10 (just after G3) and 02:13:21 (after the
reproduction runs).

| Check | Before | After G3 | End |
| --- | --- | --- | --- |
| `cmdkey /list` lines matching `agenthud-test` (count only) | 0 | 0 | 0 |
| `%LOCALAPPDATA%\Debug-windows-x86_64` | absent | absent | absent |
| `*.plist` directly in the real `%LOCALAPPDATA%` | 0 | 0 | 0 |
| `agenthud-testprofile-*` in `%TEMP%` | 0 | 0 | 0 |
| `%APPDATA%\Agent HUD Open` modification time | 2026-10-16 17:20:19 | same | same |
| `.qwen`, `.codebuddy`, `.qoder` | absent | absent | absent |
| `.codex`, `.copilot` (folder and every file at depth ≤ 2) | — | unchanged | unchanged |
| `.claude` folder time | 01:04:04 | unchanged | unchanged |

What did change in `.claude`:

- During G3, only `.claude\backups\.claude.json.backup.<epoch-ms>` files rotated. Their times are 01:54:00, 01:57:22 and
  02:01:01; the last two are the moments my own tool calls returned.
- Later, `.claude\skills\synced\…` changed at 02:04:01, when no test was running.

Both are the running Claude Code client's own activity. No `settings.json`, hook or MCP file in any of the six folders
changed.

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

`git diff 505492b c369f8d -- Sources/AgentHUDSupport Tests/AgentHUDSupportTests` is empty.

## G6: PASS

- `python scripts\check-source-boundaries.py` at `c369f8d`: `Source boundaries and ignore rules passed.`, exit 0.
- It also passed in CI: step 3 of the Windows job and of the macOS `test` job.

## D-006

`git diff c258093 c369f8d` is 0 bytes for all six `windowsReplaced` files:

- `System/UnixSocket.swift`
- `System/UnixSocketListener.swift`
- `System/ChildProcess.swift`
- `System/FileChangeMonitor.swift`
- `System/InstanceLock.swift`
- `Providers/Codex/CodexDesktopIPC.swift`

## G7 (observations, for the reviewer)

- **The macOS paths of the shared Hooks files are unchanged.** Each M5 addition is a `#if os(Windows)` branch with the
  old code in `#else`:
  - `HookCommand.make` / `isTransient`
  - `HookInstaller`
  - `HookSettings`
  - `PermissionHooks`
  - `DeepSeekQuestionObserver.stream`
  - `MCPStdio.run` (`_setmode` binary mode)
  - `engineArguments`' case-insensitive match

  `ClaudeEngineLocator.processPaths` keeps the old macOS expression in its `#else`.
- **The credential tests are well contained.** `WindowsCredentialsTests` writes `CRED_PERSIST_SESSION` credentials
  under `agenthud-test-<UUID>`, deletes them in teardown blocks, and never names a `gh:` target. None was left
  (M5 (c)).
- **`%TEMP%` leftovers (non-blocking, not from M5).** The real `%TEMP%` holds 360 `agenthud*` folders, 46 of them dated
  today and 126 dated 2026-10-17, and 2067 `TemporaryDirectory.*` folders.
  - The `agenthud 引擎 <UUID>` folders come from M4's `ProviderEnginesWindowsTests` (`:12`, no teardown removal).
  - The `agenthud-engine-<UUID>` folders come from upstream `ClaudeEngineTests` / `ClaudeProviderTests` /
    `UsageInsightsTests` fixtures.
  - The `TemporaryDirectory.*` folders are swift-corelibs' atomic-write folders.
  - The new M5 fixtures (`HUD 端到端`, `HUD Hooks 回调`, `off 关闭-`) left nothing.
  - These folders are outside the user's profile data, but they grow by about 50 per G3 run.

## G8: notes (non-blocking)

1. **PROGRESS.md and SKIPPED_TESTS.md record the local result** (1421 passed, 0 failed). They should note that CI on
   the runner fails until BLOCKING 1 is fixed.
2. **PROGRESS "Known issues"** could record the 8.3 class of failure next to M3 round 2's. This is the second time a
   test has assumed the temporary folder's long spelling.

## Skipped tests

| Kind | Count | Registered |
| --- | --- | --- |
| Excluded files (`windowsSkippedTests`) | 7 files | yes, §1: an exact match; the six replaced sources are unchanged from `c258093` |
| Skip list (`skipped-tests.txt`) | 34 tests | yes: all 34 named in §2, an exact match in both directions; none ran on Windows; all 34 pass on macOS |
| Runtime skips (`XCTSkip`) | 4 tests, the same in CI and locally (the 4 opt-in probes) | yes, §3 |
| Conditional runtime skips (no `node.exe`; no `git.exe`; no 8.3 names) | 0 triggered | yes, §3 |
| Support `portableDigestsEqualCryptoKit` (compiled only with CryptoKit) | 1 | yes (AgentHUDSupportTests section) |

## Verdict summary

| Gate | Verdict |
| --- | --- |
| G1 | **FAIL** (run 39102050317: 2086 XCTest, 8 skipped, 1 failure in upstream `StatsWindowLifecycleTests`, which is not touched by the port and looks flaky; needs a green re-run) |
| G2 | PASS (run 39102050084 step 10, 1 attempt; local release build 184.7 s; warnings equal the baseline in both) |
| G3 | **FAIL** (CI: 1425 / 1420 passed / 4 skipped / **1 failed**, `WindowsExecutablesTests.testClaudesEngineIsRecognisedAmongAHooksAncestors`, reproduced locally with an 8.3 `TEMP`; local default run: 1425 / 1421 / 4 / 0) |
| G4 | PASS |
| G5 | N/A |
| G6 | PASS |
| M5 (a) end-to-end tests ran | PASS (4/4, local and CI) |
| M5 (b) skips registered | PASS (34 + 7 + 4, state line matches the local run) |
| M5 (c) test credentials | PASS (0 `agenthud-test` matches) |
| M5 (d) stray folder / preferences | PASS |
| M5 (e) real client folders | PASS (no hook or settings file changed) |
| M5 (f) flaky test | did not fail |
| B-001 tests | present, 12/12 pass in CI and locally |
| G7 | observations only |
| G8 | 2 non-blocking notes |

BLOCKING findings:

1. The Windows CI G3 failure (8.3 temporary path vs `resolvingSymlinksInPath` in `engineArguments`).
2. G1's red macOS run (most likely flaky, needs a green run).

TESTS: FAILURES
