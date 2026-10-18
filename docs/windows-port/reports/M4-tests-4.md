# M4 test report, round 4

- Branch: `windows-port`. Head under test: `4cdf931` ("Windows port M4 round 4: the Grok Bot quota check can fail").
  The round-3 commit `76ec0e2` was never tested locally (the round-3 tester was stopped by a rate limit), so this
  round covers both: change set `0bdab94...4cdf931`, 11 files, +495/−22. Of these, 401 lines are `M4-tests-2.md`; the
  code and test changes are in 6 files. M4 range: `469bc44...4cdf931`, 65 files, +2118/−172.
- Run by: port-tester, 2026-10-18. Local times below are the machine's (UTC−4). Machine: Windows 11 Pro 10.0.26200.
- The working tree was clean at `4cdf931` before and after the gates. Only this report was written in the repository.
  Nothing was committed or pushed.
- **Another worktree was busy.** `wt5build` and `testprofile-wt5` (M5) changed at 01:12:58 and 01:13:14, while my G3
  ran. None of my runs printed "being used by another process" or "file in use". Every build I ran used
  `%LOCALAPPDATA%\agenthud-dev\build` only.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | PASS: 2086 XCTest (8 skipped, 0 failures) + 10 swift-testing. All 31 skip-list tests and the 3 tests taken off the list ran and passed on macOS. No new macOS test warning. |
| G2 Windows build | PASS: CI step 10 green (build.ps1, 1 attempt, no retry). Local release build green. Library warnings equal the baseline exactly, in both places. |
| G3 Windows tests | PASS: CI 1343 executed, 1339 passed, 4 skipped, 0 failed. Local: the same numbers, and the same set of test cases. All 31 skip-list entries are named in SKIPPED_TESTS.md. |
| G4 determinism | PASS (macOS CI, Windows CI, Windows local) |
| G5 UI | N/A (M7+) |
| G6 boundaries | PASS |
| M4 (a) provider tests use temporary fixtures only | PASS. Round 2's observation is resolved: the test no longer builds the production Claude provider against the real `%USERPROFILE%`. |
| M4 (b) D-006: the six replaced files equal upstream `c258093` | PASS; the 9 excluded test files are unchanged too |
| M4 (c) D-021: stray `%LOCALAPPDATA%\Debug-windows-x86_64` | absent before and after G3 |
| Round-2 BLOCKING 1 (driveless-path test on the D: runner) | **resolved**: it passes in CI, and now tests something there |
| Round-2 BLOCKING 2 (8 skip-list entries not named) | **resolved**: SKIPPED_TESTS.md §2 and the list file match name for name |
| G7 security review | review gate; observations below |
| G8 docs | PASS, with non-blocking notes |

## BLOCKING findings

None.

## Round-2 BLOCKING findings, checked again

1. **The driveless-path test on the `D:` runner: resolved.** In round 3, `WindowsExecutablesTests.testADrivelessPathIsRefusedEvenWhereAProgramExists`
   changed:
   - It no longer uses `%SystemRoot%\System32\whoami.exe`. It copies `whoami.exe` to `bin\tool.exe` in a temporary
     folder.
   - It sets the current directory to that folder, so that the driveless spelling resolves on the fixture's own drive.
   - It restores the current directory in a `defer`. Round 4 asserts that the restore worked.

   Results:
   - In CI it passed: `Test Case 'WindowsExecutablesTests.testADrivelessPathIsRefusedEvenWhereAProgramExists' passed
     (0.01 seconds)`, in run 39047601254 with the checkout on `D:\a\…`. Locally it passed in 0.003 s.
   - **The checks now mean something on the runner.** `XCTAssertTrue(fileExists(atPath: rootRelative))` passed there,
     so the file the test must refuse exists. The two `XCTAssertNil` checks that follow test a real refusal. They no
     longer pass only because the file is missing.
2. **The 8 unnamed skip-list entries: resolved.** The §2 row now names each test. I parsed the `` `Class/test` ``
   and `` `…/test` `` names of §2's 16 rows: they are 31 names, exactly the 31 unique entries of
   `scripts/windows/skipped-tests.txt`. No entry is only in the doc, and none is only in the file. Round 3 also took 3
   entries off the list (see G3).

## G1: PASS

`Source checks` run **39047601576**: workflow_dispatch on `windows-port`, head `4cdf931`. It ended `completed` /
`success` (created 16:01:28Z, finished 16:10:48Z).

| Job | Conclusion | Steps |
| --- | --- | --- |
| `test` (117439367762) | success | Check source boundaries: success. Test: success (16:01:41Z to 16:10:36Z). |
| `app` (117439367683) | success | Build application: success (16:01:43Z to 16:08:09Z). Verify local signature and resources: success. |
| `macos` (117441307576) | success | Tests and application passed: success. |

What the `test` log shows:

- XCTest: `Executed 2086 tests, with 8 tests skipped and 0 failures (0 unexpected) in 344.728 (344.834) seconds`. This
  is the same as M2, M3 and the earlier M4 rounds.
- **The 8 skips have not changed:**
  - the four `…Probe` tests
  - `ArtworkMemoryTests.testProbeWritesEveryBakedMarkBotAndAccent`
  - `BotFrameTests.testFrameCost`
  - `BotMarkTests.testAReminderMarkOpensAsItsLogoAndTurnsIntoItsBotOnceItsCardHasOpened`
  - `IslandAnimationTests.testAGlowThatClosesStopsItsFrames`
- swift-testing: `✔ Test run with 10 tests passed after 0.905 seconds.`
- `Source boundaries and ignore rules passed.`
- **No shared test is skipped on macOS without a record.** Each of the 31 `skipped-tests.txt` entries has a `passed`
  line in the macOS log.
- **The shared tests that round 3 changed pass on macOS.** All three have a `passed` line in the log:
  - `AdditionalProviderTests.testCursorNamesConversationsFromTheIDEAndTheAgentCLI` (now `#if os(Windows)` / `#else`)
  - `TencentBuddyProviderTests.testCodeBuddyAndWorkBuddyStaySeparateAndSubagentsJoinTheirParent`
  - `TencentBuddyProviderTests.testEngineTitlesAndWorkBuddyNamesReplaceTheFolderName`

  On macOS, the `.filter` in the first TencentBuddy test keeps all 8 ids, and the `where PlatformSupport.supports(source)`
  keeps both sources. So the macOS assertions are unchanged.
- **macOS test-build warnings: the same list as round 2.** No warning names `AdditionalProviderTests.swift`,
  `TencentBuddyProviderTests.swift`, `ClaudeCodeProvider.swift` or `AdditionalUsageProvider.swift`. The list is:
  - `PermissionHookTests.swift:423/430/441`
  - `PanelToolsSpanTests.swift:91`
  - `CollectionSignalTests.swift:331`
  - `UsageRefreshTests.swift:73`
  - `JoinedGlassTests.swift:192/246`
  - `ScreenStyleHUDTests.swift:254`
  - `AgentSeparationTests.swift:136/209/243`
  - `DeepSeekProviderTests.swift:525`
  - `DeepSeekQuestions.swift:106`
  - `AntigravityCLI.swift:18`

## G2: PASS

### CI

`Windows port` run **39047601254** was a push of head `4cdf931`. Job `swift` (117439364076, windows-latest) ended
`completed` / **`success`** (16:01:30Z to 16:20:41Z).

| # | Step | Conclusion |
| --- | --- | --- |
| 1–4 | Set up, checkout, Check source boundaries, System SQLite version | success |
| 5–6 | Cache the Swift installer / Download (skipped by design) | success / skipped |
| 7–9 | Verify and install Swift, Toolchain, Cache the Swift build | success |
| 10 | **Build (release)**: `scripts/windows/build.ps1 -c release`, 16:04:09Z to 16:12:54Z | **success** |
| 11 | Test: `scripts/windows/test.ps1`, 16:12:54Z to 16:20:10Z | **success** (G3) |
| 12 | Compile a smoke package | success (`smoke true`) |

- **No retry.** Step 10 built on its first attempt: `Build complete! (517.23 secs)`.
- The log has no "being used by another process" and no "hit a file in use".
- Release-build warnings in step 10 (ANSI stripped) are **exactly the 6 baseline warnings, each once**:
  - `MCPStdio.swift:54` `strerror`
  - `PermissionHookClient.swift:38` `close`
  - `ZstandardReader.swift:46` `close`
  - `AntigravityCLI.swift:18` `init(cString:)`
  - `CodexDesktopStream.swift:170` `wait(until:)`
  - `DeepSeekQuestions.swift:106` `await`

  There is no `wchar_t` line.

### Local

- Command: `swift build -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build`, with the PROGRESS.md Swift
  environment, run from the junction `%LOCALAPPDATA%\agenthud-dev\src` (→ `E:\桌面项目\agent-hud-open`) at `4cdf931`.
  Output was redirected through `cmd /c "… > log 2>&1"`.
- Result: exit 0, `Build complete! (240.65 secs)`. Wall clock was 245 s, 01:06:09 to 01:10:14.
- The build was incremental: Support and Core were recompiled.
- No file-in-use line, and no `error:`.
- **Warnings: exactly the same 6 baseline warnings, each once.** No new library warning. The two round-3 source changes
  (`AdditionalUsageProvider.swift:70`, `ClaudeCodeProvider.standardDesktopSessions`) warn nothing.

### Test-build warnings (G3's build; outside G2 since D-033)

- **Two new warnings, on lines the port wrote** (non-blocking finding 1). Both are in
  `Tests/AgentHUDCoreTests/WindowsSupport/ProviderPathsWindowsTests.swift`, in the new
  `testGrokBotsCacheIsNeverAskedOnWindows`. Each is printed twice, in CI step 11 and in the local build-first log:
  - `:103:25: warning: no calls to throwing functions occur within 'try' expression`
    - This is `XCTAssertNotNil(try GrokBotQuota.read(…))`, from `76ec0e2`.
    - `GrokBotQuota.read(in:now:)` does not throw: `static func read(in directory: URL, now: Date) -> ProviderQuota?`.
  - `:111:62: warning: string interpolation produces a debug description for an optional value`
    - This is `XCTFail("…\(quota.client)")`, from `4cdf931`.
    - `ProviderQuota.client` is `String?` (`ProviderData.swift:108`).

  D-033 says "the port's own test files are kept warning-free all the same". M4 round 1 treated the same kind of
  warning as non-blocking, so I classify these the same way. The file is `#if os(Windows)`, so macOS is not affected.
- **What remains are the upstream lines from M3, unchanged:** `MCPStdioTests.swift` (`close`/`dup`/`dup2`, 19 sites),
  `PanelToolsSpanTests.swift:91`, `CollectionSignalTests.swift:331`, `UsageRefreshTests.swift:73`,
  `DeepSeekProviderTests.swift:525` (×2). This is CI's full list. The local test build was incremental (`Build
  complete! (18.96 secs)`), so it printed only `DeepSeekProviderTests.swift:525` and the two new lines.

## G3: PASS

### CI (step 11 of run 39047601254)

- The build-first step (`build.ps1 --build-tests`) took 1 attempt: `Build complete! (229.72 secs)`.
- Support: `Test run with 9 tests in 0 suites passed after 0.682 seconds.`
- Core, 9 batches: 114 + 126 + 127 + 166 + 188 + 221 + 61 + 242 + 98 = **1343 executed: 1339 passed, 4 skipped, 0
  failed**.
- `Removed 6 test preference file(s) from C:\Users\runneradmin\AppData\Local`.

### Local

- Command: `%LOCALAPPDATA%\agenthud-dev\src\scripts\windows\test.ps1 -ScratchPath %LOCALAPPDATA%\agenthud-dev\build -Log
  <scratch>\g3.log`.
- Setup: Windows PowerShell 5.1, the PROGRESS.md environment, the junction, `4cdf931`. test.ps1 makes its own fresh
  `agenthud-testprofile-<guid>` under `%TEMP%` and removes it afterwards: none was left.
- Result: exit 0 in **180 s** (01:10:26 to 01:13:26).
- The build-first step took 1 attempt: `Build complete! (18.96 secs)`.
- Support: `Test run with 9 tests in 0 suites passed after 0.399 seconds.`
- Core: the same 9 batch sizes as CI, **1343 executed: 1339 passed, 4 skipped, 0 failed**.
- `Removed 6 test preference file(s) from C:\Users\suzume\AppData\Local`.
- The CI and local sets of 1343 test cases are **identical**: a sorted diff finds no local-only and no CI-only case.
- **The known flaky test did not fail.** `FileChangeMonitorWindowsTests.testAWatchedDirectoryThatGoesAwayAsksForAFullScan`
  passed locally (0.002 s) and in CI. That is why I made no single-test re-runs.

### Compared with round 2 (1338 / 1334 / 4 / 0 locally)

1338 + 3 + 2 = 1343:

- **3 tests are off the skip list again, and run on Windows.** All three pass in CI and locally:
  - `AdditionalProviderTests.testCursorNamesConversationsFromTheIDEAndTheAgentCLI`
  - `TencentBuddyProviderTests.testCodeBuddyAndWorkBuddyStaySeparateAndSubagentsJoinTheirParent`
  - `TencentBuddyProviderTests.testEngineTitlesAndWorkBuddyNamesReplaceTheFolderName`

  On Windows they assert that the gate holds: only the editor's names, with no agent-CLI title, and WorkBuddy's half
  is absent. So round 2's coverage note on CodeBuddy's subagent-joining is resolved.
- **2 tests are new, and both pass in CI and locally:**
  - `ProviderPathsWindowsTests.testGrokBotsCacheIsNeverAskedOnWindows`
  - `ProviderPathsWindowsTests.testUnsourcedFoldersAreNotRead`
- `ProviderPathsWindowsTests.testTheMacDesktopAppsLocationsAreNeverUsed` now ends with
  `XCTAssertNil(ClaudeCodeProvider.standardDesktopSessions)`. It passed in both places.
- **The round-4 fix itself.** `testGrokBotsCacheIsNeverAskedOnWindows` now gives `GrokClient` the fixture's clock
  (`client.clock = { fixture.now }`). It expects `ProviderFailure.login("Grok CLI")`, and it first asserts that
  `GrokBotQuota.read(in:now: fixture.now)` reads the fixture.
  - So without the `supportsDesktopApps` guard in `GrokClient` (line 60), the Bot's cache would answer, and the test
    would reach its `XCTFail`. I read the code; I did not run that mutation (I do not edit source).
  - The routine-run half asserts that the roster is visible (`GrokBotSessions.agentIDs == [fixture.agent]`). It then
    expects 0 service calls.

### Skips

**Runtime skips: 4, the same in CI and locally.** All are in SKIPPED_TESTS.md §3:

- `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe`
- `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe`
- `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe`
- `SessionUsageProbeTests.testReportedSessionsUsageProbe`

No conditional skip triggered (no Node, no Git, no 8.3 names): `node.exe` and `git.exe` are on `PATH` in both places,
and the volumes keep 8.3 names.

**Skip list: `scripts/windows/skipped-tests.txt` has 31 unique entries.**

- None of them appears in the local or the CI log.
- All 31 are named in §2, and §2 names nothing else.
- All 31 pass on macOS.

**Excluded files:** the 9 entries of `windowsSkippedTests` match §1's 9 rows, and all 9 are unchanged from `c258093`.

**The state line is one off** (G8 note 2). SKIPPED_TESTS.md says: "State at M4 round 3 …: 1338 pass, 4 runtime
skips, 31 listed skips, 9 excluded files, 0 failures". Both runs measured 1339 passed, 1343 executed. The 4, 31 and 9
match.

### M4 (c), D-021: the real `%LOCALAPPDATA%` (`C:\Users\suzume\AppData\Local`)

| When | `Debug-windows-x86_64` | `*.plist` |
| --- | --- | --- |
| before G2 (01:05:57) | **absent** | 0 |
| after G3 (01:13:49) | **absent** | 0 |

The real `%APPDATA%\Agent HUD Open` still has only its folders dated 2026-10-16 17:20 (from before D-021). Nothing in
it changed during the gates.

## G4: PASS

The Support golden tests ran in all three places:

- `recordIdentitiesMatchTheGoldenSamples`
- `digestsMatchTheNISTVectors`
- `millisecondDatesRoundTripTheGoldenSamples`
- `theRecordEncoderWritesTheGoldenSample`

| Where | Result |
| --- | --- |
| macOS CI | 10/10 passed, including `portableDigestsEqualCryptoKit` |
| Windows CI | 9/9 passed |
| Windows local | 9/9 passed |

`git diff 469bc44 4cdf931 -- Sources/AgentHUDSupport Tests/AgentHUDSupportTests` is empty.

## G6: PASS

- `python scripts\check-source-boundaries.py` at `4cdf931`: `Source boundaries and ignore rules passed.`, exit 0, 1 s.
- It also passed in CI: step 3 of the macOS `test` job and step 3 of the Windows job.

## M4 (a): provider tests use temporary fixtures only — PASS

Every fixture in the round-3 and round-4 tests is under `FileManager.default.temporaryDirectory`:

- `GrokBotCacheFixture` (`GrokBotCache-<uuid>`) and the Grok CLI home from `directory()`. `GrokClient` gets both
  `home:` and `botDirectory:`, so its default `UserHome.directory` path is never evaluated. With no credential file
  there, `fetch()` fails with the login error before any request.
- `testUnsourcedFoldersAreNotRead`: a fixture home with a planted `.bun/install/global/node_modules/<package>`.
  `OpenAgentPaths` and `DeepSeekCredentialLocator.module` are given `home:`.
- `WindowsExecutablesTests` copies `whoami.exe` from System32 into a temporary folder. It changes the current
  directory to that folder and restores it afterwards.
- **Round 2's observation is resolved.** `testTheMacDesktopAppsLocationsAreNeverUsed` no longer builds
  `ClaudeCodeProvider.standard(…)`, which read the real `%USERPROFILE%` and watched it. It reads
  `ClaudeCodeProvider.standardDesktopSessions`, which is `nil` on Windows and builds nothing.

## M4 (b): D-006 and the excluded tests — PASS

- `git diff c258093 4cdf931 -- Sources/AgentHUDCore/<file>` is **0 bytes** for all six `windowsReplaced` files, and all
  six exist:
  - `System/UnixSocket.swift`
  - `System/UnixSocketListener.swift`
  - `System/ChildProcess.swift`
  - `System/FileChangeMonitor.swift`
  - `System/InstanceLock.swift`
  - `Providers/Codex/CodexDesktopIPC.swift`
- All 9 `windowsSkippedTests` files diff to 0 bytes against `c258093`.
- `Package.swift` did not change in rounds 3 and 4.

## G7 (observations, for the reviewer)

- **Round 2's ungated item is fixed.** `AdditionalUsageProvider` passes `botQuotaDirectory` only when
  `PlatformSupport.supportsDesktopApps` is true, so on Windows it is `nil`.
- **`ClaudeCodeProvider.standardDesktopSessions`** is a new internal static. `standard(…)` uses it, so the production
  wiring and the test read the same gate. On macOS the behaviour is unchanged (`ClaudeDesktopSessions()`).
- **Shared upstream test files changed in round 3**, minimally, with the macOS assertions kept as they were:
  - `AdditionalProviderTests.swift`: one `#if os(Windows)` / `#else` around one assertion.
  - `TencentBuddyProviderTests.swift`: one `#if`, plus a `where PlatformSupport.supports(source)` and a `.filter`.
    Neither changes anything on macOS.

  These will be rebase-conflict points against upstream (D-006 aims for clean rebases). They are tests, not the six
  replaced sources.
- **The driveless test changes the process-wide current directory.** XCTest on Windows runs the cases of a batch one
  after another, so no other test sees it. The restore is asserted. A future parallel run (`--parallel`) would need
  to revisit this.

## G8: PASS, with non-blocking notes

**What matches the code:**

- SKIPPED_TESTS §1, §2 and §3 match the code and both runs. §3 now names the 3 DeepSeek compressed-log tests, and it
  lists the conditional skips: the Node skip of `ChildProcessWindowsTests`, the Git skip of `SessionProjectWindowsTests`
  and its 8.3 skip. This resolves round 2's G8 notes 2 and 3.
  - The `whoami.exe` skip is gone from `WindowsExecutablesTests`.
  - The `XCTSkip` calls in `WindowsSupport/` are exactly the ones §3 lists.
- SUPPORT_MATRIX footnote 9 no longer cites the nonexistent D-037 (round 2's G8 note 1). It now reads "M5 gives it no
  hook there".
- The skip-list comments and the §2 reasons no longer name WorkBuddy or Cursor's agent folder, which now run on Windows
  as gate checks.
- The flaky `FileChangeMonitorWindowsTests` test is recorded in PROGRESS "Known issues".

**Non-blocking notes:**

1. **PROGRESS.md has not moved past round 2.**
   - The status line reads "M4 — Providers (review round 2; …)".
   - The M4 milestone row reads "review (round 2)". It records only round 1, without round 2's test result (FAILURES,
     run 39030218591) or the round-3 and round-4 review findings and fixes.
   - "Next steps" item 1 still describes review round 2.
2. **SKIPPED_TESTS.md's state line** says "M4 round 3 … 1338 pass". Both runs at `4cdf931` measured **1339** passed
   of 1343 executed, 0 failures. The round-3 local run that PROGRESS mentions (the flaky test failing once) would give
   1338 passed plus 1 failure, not 0 failures. The other counts match: 4 runtime skips, 31 listed skips, 9 excluded
   files.
3. **The two new test-build warnings** in `ProviderPathsWindowsTests.swift:103/111` (G2 above), against D-033's "the
   port's own test files are kept warning-free".

## Skipped tests

| Kind | Count | Registered |
| --- | --- | --- |
| Excluded files (`windowsSkippedTests`) | 9 files | yes, §1, an exact match; all unchanged from `c258093` |
| Skip list (`skipped-tests.txt`) | 31 tests | yes: all 31 named in §2 (an exact match in both directions); none ran on Windows; all 31 pass on macOS |
| Runtime skips (`XCTSkip`) | 4 tests, the same in CI and locally (the 4 opt-in probes) | yes, §3 |
| Conditional runtime skips (no `node.exe`; no `git.exe`; no 8.3 names) | 0 triggered | yes, §3 |
| Support `portableDigestsEqualCryptoKit` (compiled only with CryptoKit) | 1 | yes (the AgentHUDSupportTests section) |

## Verdict summary

| Gate | Verdict |
| --- | --- |
| G1 | PASS (run 39047601576: 2086 XCTest / 8 skipped / 0 failed + 10 swift-testing; all 31 Windows-skipped tests and the 3 changed shared tests pass on macOS; no new macOS warning) |
| G2 | PASS (run 39047601254 step 10, build.ps1, 1 attempt, no retry; local release build 240.7 s; warnings equal the baseline in both) |
| G3 | PASS (CI and local: 1343 executed, 1339 passed, 4 skipped, 0 failed, identical case sets; every skip registered) |
| G4 | PASS |
| G5 | N/A |
| G6 | PASS |
| M4 (a) fixtures only | PASS (round 2's real-home observation resolved) |
| M4 (b) D-006 | PASS |
| M4 (c) `Debug-windows-x86_64` | absent before and after G3 |
| Round-2 BLOCKING 1, 2 | both resolved |
| G7 | observations only |
| G8 | PASS with 3 non-blocking notes |

BLOCKING findings: none.

TESTS: ALL_PASS
