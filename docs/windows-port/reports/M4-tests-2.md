# M4 test report, round 2

- Branch: `windows-port`. Head under test: `0bdab94` ("Windows port M4: round-1 test report"), on `8509b17` and
  `848ca5b` (the round-2 fixes). Round-2 range: `c1d64a0...0bdab94`, 27 files, +568/−47. M4 range: `469bc44...0bdab94`,
  62 files, +1641/−168.
- Run by: port-tester, 2026-10-17. Local times below are the machine's (UTC−4). Machine: Windows 11 Pro 10.0.26200.
- The working tree was clean at `0bdab94` before and after the gates. Only this report was written in the repository.
  Nothing was committed or pushed.
- **Other worktrees were busy.** They built and tested with their own scratch paths and profiles while my gates ran.
  `wt5build` and `testprofile-wt5` changed at 07:52 and 07:53. `wtbuild` and `testprofile-wt` changed at 08:08.
  None of my runs printed "being used by another process": the local G2, the local G3, and the two single-test
  reproductions. Every build I ran used `%LOCALAPPDATA%\agenthud-dev\build` only.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | PASS: 2086 XCTest (8 skipped, 0 failures) + 10 swift-testing. All 34 skip-list tests ran and passed on macOS. The `ClaudeEngineTests.swift:115` warning is gone from the macOS log. |
| G2 Windows build | PASS: CI step 10 green (build.ps1, 1 attempt, no retry). Local release build green. Library warnings equal the baseline exactly. No test-build warning in the files M4 wrote. |
| G3 Windows tests | **FAIL**: CI step 11 failed on 1 test, `WindowsExecutablesTests.testADrivelessPathIsRefusedEvenWhereAProgramExists`, which depends on the environment. Locally 1338 executed, 1334 passed, 4 skipped, 0 failed. 8 skip-list entries are not named in SKIPPED_TESTS.md. |
| G4 determinism | PASS (macOS CI, Windows CI, Windows local) |
| G5 UI | N/A (M7+) |
| G6 boundaries | PASS |
| M4 (a) provider tests use temporary fixtures only | PASS. Observation: one new test builds the production Claude provider against the real `%USERPROFILE%`. |
| M4 (b) D-006: the six replaced files equal upstream `c258093` | PASS; the 9 excluded test files are unchanged too |
| M4 (c) D-021: stray `%LOCALAPPDATA%\Debug-windows-x86_64` | absent before and after G3 |
| G7 security review | review gate; observations below |
| G8 docs | PASS, with non-blocking notes |

## BLOCKING findings

1. **The `Windows port` workflow is red for the head.** Run 39030218591, step 11 "Test", fails on
   `WindowsExecutablesTests.testADrivelessPathIsRefusedEvenWhereAProgramExists`, which was added in round 2:

   ```
   D:\a\agent-hud-open\agent-hud-open\Tests\AgentHUDCoreTests\WindowsSupport\WindowsExecutablesTests.swift:67: error:
   WindowsExecutablesTests.testADrivelessPathIsRefusedEvenWhereAProgramExists : XCTAssertTrue failed - the driveless
   spelling reaches the same file: /Windows/System32/whoami.exe
   ```

   - **Why it fails.** The test takes `%SystemRoot%\System32\whoami.exe` (on `C:`) and removes the drive. It then
     assumes that `/Windows/System32/whoami.exe` resolves to the same file. A driveless path resolves against the
     process's **current drive**. On the runner that drive is `D:`, because the checkout is `D:\a\…` and SwiftPM runs
     the tests in the package folder. `D:\Windows\System32\whoami.exe` does not exist there.
   - **Why it passes here.** Locally the package is the junction `%LOCALAPPDATA%\agenthud-dev\src` on `C:`. The test also
     passed when I started `swift test` from `E:\桌面项目\agent-hud-open`, because SwiftPM still ran it in the
     package folder on `C:`.
   - **So the failure is deterministic.** The test fails on every runner whose checkout drive is not the system drive.
   - **On the runner the test also proves nothing.** The two `XCTAssertNil` checks after line 67 pass trivially there,
     because the file they are meant to refuse does not exist. This is the round-1 review's "the D-019 test could not
     fail" concern again.
   - **A fix belongs in the test.** For example, build the driveless path from a program fixture on the current
     drive, or set the current directory to `%SystemDrive%\` for the duration of the test and restore it afterwards.
     A skip when the drives differ would leave CI without the check.
2. **8 skip-list entries are not named in SKIPPED_TESTS.md.** TASK.md §6 G3 requires each skipped test to be listed
   by test name, with its reason and its Windows counterpart. An unregistered skip counts as a failure. The new §2
   row gives `GrokBotRoutineRunsTests ×3`, `GrokBotUsageTests ×3` and `TencentBuddyProviderTests ×2` as counts, with
   "(exact names in the list file)", and does not name these tests:
   - `GrokBotRoutineRunsTests/testRunsSurviveARelaunchAndLeaveWithTheLedgerRetention`
   - `GrokBotRoutineRunsTests/testServiceIsAskedOnlyAboutAnUnexplainedSubagentConversationOfARosteredAccount`
   - `GrokBotRoutineRunsTests/testUnlistedConversationIsAskedAboutTwiceAndAFailedReadDoesNotCount`
   - `GrokBotUsageTests/testAListedBotKeepsItsOlderRunsWhileAnOldRunNoBotClaimsLeavesTheMonth`
   - `GrokBotUsageTests/testRoutineRunBecomesASubagentOfItsBotAndCountsInItsTotalOnce`
   - `GrokBotUsageTests/testRunOfABotWithoutBillingOfItsOwnNestsAndARunOfAnUnknownBotStaysApart`
   - `TencentBuddyProviderTests/testCodeBuddyAndWorkBuddyStaySeparateAndSubagentsJoinTheirParent`
   - `TencentBuddyProviderTests/testEngineTitlesAndWorkBuddyNamesReplaceTheFolderName`

   The other 26 entries are named in §2, including the ones inside the same row's `×2` and `×3` groups that list their
   names. The counts in the row do match the list file. Fixing this means adding the 8 names to the doc, nothing else.

## G1: PASS

`Source checks` run **39030219177**: workflow_dispatch on `windows-port`, head `0bdab94`. It ended `completed` /
`success` (created 11:50:24Z, finished 12:00:04Z).

| Job | Runner | Conclusion | Steps |
| --- | --- | --- | --- |
| `test` (117389009760) | macos | success | Check source boundaries: success. Test: success (11:50:36Z to 11:59:53Z). |
| `app` (117389009564) | macos | success | Build application: success (11:50:36Z to 11:57:13Z). Verify local signature and resources: success. |
| `macos` (117390677854) | ubuntu | success | Tests and application passed: success. |

What the `test` log shows:

- XCTest: `Executed 2086 tests, with 8 tests skipped and 0 failures (0 unexpected) in 361.073` s. This is the same as
  M2, M3 and M4 round 1.
- **The 8 skips have not changed:**
  - the four `…Probe` tests
  - `ArtworkMemoryTests.testProbeWritesEveryBakedMarkBotAndAccent`
  - `BotFrameTests.testFrameCost`
  - `BotMarkTests.testAReminderMarkOpensAsItsLogoAndTurnsIntoItsBotOnceItsCardHasOpened`
  - `IslandAnimationTests.testAGlowThatClosesStopsItsFrames`
- swift-testing: `✔ Test run with 10 tests passed after 1.129 seconds`.
- `Source boundaries and ignore rules passed.`
- **No shared test is skipped on macOS without a record.** Each of the 34 `skipped-tests.txt` entries has a `passed`
  line in the macOS log. This includes the 14 new Windows skips and `ClaudeEngineTests/testLocatorFallsBackToTheDesktopAppsEngine`.
- `PlatformSupport` going from `public` to `package` access breaks nothing on macOS: `AgentHUDDesktop` (its
  `SourceDetector`) and the app built, and their tests passed.
- **macOS test-build warnings: round 1's new warning is gone.** `ClaudeEngineTests.swift:115` (`result of 'try?' is
  unused`) is no longer in the log. Every remaining warning is on a file the port did not change since `c258093`, or
  on the baselined `AntigravityCLI.swift:18`. They are:
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

`Windows port` run **39030218591** was a push of head `0bdab94`. Job `swift` (117389005231, windows-latest) ended
`completed` / **`failure`**, at step 11 (see G3).

| # | Step | Conclusion |
| --- | --- | --- |
| 1–4 | Set up, checkout, Check source boundaries, System SQLite version | success |
| 5–6 | Cache the Swift installer / Download (skipped by design) | success / skipped |
| 7–9 | Verify and install Swift, Toolchain, Cache the Swift build | success |
| 10 | **Build (release)**: `scripts/windows/build.ps1 -c release`, 11:53:03Z to 12:01:56Z | **success** |
| 11 | Test: `scripts/windows/test.ps1`, 12:01:56Z to 12:09:00Z | **failure** (G3) |
| 12 | Compile a smoke package | skipped (after the failure) |

- **No retry.** Step 10 built on its first attempt: `Build complete! (514.85 secs)`.
- The log has no "being used by another process" and no "hit a file in use".
- Release-build warnings in step 10 (ANSI stripped) are **exactly the 6 baseline warnings, each once**:
  - `MCPStdio.swift:54` `strerror`
  - `PermissionHookClient.swift:38` `close`
  - `ZstandardReader.swift:46` `close`
  - `AntigravityCLI.swift:18` `init(cString:)`
  - `CodexDesktopStream.swift:170` `wait(until:)`
  - `DeepSeekQuestions.swift:106` `await`

  There is no `wchar_t` line this time.

### Local

- Command: `swift build -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build`, with the PROGRESS.md Swift
  environment, run from the junction `%LOCALAPPDATA%\agenthud-dev\src` (→ `E:\桌面项目\agent-hud-open`) at `0bdab94`.
  Output was redirected through `cmd /c "… > log 2>&1"`.
- Result: exit 0, `Build complete! (261.43 secs)`. Wall clock was 263 s, 07:51:40 to 07:56:03.
- The build was incremental: Support and Core were recompiled.
- No file-in-use line, and no `error:`.
- **Warnings: exactly the same 6 baseline warnings, each once.** No new library warning. None of the round-2 source
  files warns: `PlatformSupport`, the locators, `CursorClient`, `OpenAgent*`, `Grok*`, `LocalSessionLayout`,
  `AdditionalUsageProvider`, `PermissionHooks`.

### Test-build warnings (G3's build; outside G2 since D-033)

- **Round 1's two warnings on port-written lines are fixed.** They are absent from the local build-first log and from
  CI step 11:
  - `ClaudeEngineTests.swift:115` now reads `_ = try? TestEngine.write(…)`.
  - `SessionProjectWindowsTests.swift:71` now uses `String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)`.
- The test build recompiled the whole Core test target: the warnings of unchanged upstream files are printed too.
  So this absence covers every M4 test file.
- The new code in `ProviderPathsWindowsTests` and `WindowsExecutablesTests` warns nothing.
- **What remains are the upstream lines from M3, unchanged:** `MCPStdioTests.swift` (`close`/`dup`/`dup2`, 19 sites),
  `PanelToolsSpanTests.swift:91`, `CollectionSignalTests.swift:331`, `UsageRefreshTests.swift:73`,
  `DeepSeekProviderTests.swift:525` (×2). The list is the same in CI and locally.

## G3: FAIL

### CI (step 11 of run 39030218591)

- The build-first step (`build.ps1 --build-tests`) took 1 attempt: `Build complete! (226.52 secs)`.
- Support: `Test run with 9 tests in 0 suites passed after 0.667 seconds`.
- Core, 9 batches: 113 + 126 + 127 + 166 + 188 + 221 + 59 + 240 + 98 = **1338 executed: 1333 passed, 4 skipped, 1
  failed**. The failure is in the last batch: `Executed 98 tests, with 1 failure`, then `Process completed with exit
  code 1`.
- The failed test is `WindowsExecutablesTests.testADrivelessPathIsRefusedEvenWhereAProgramExists` (BLOCKING 1).
- `Removed 6 test preference file(s) from C:\Users\runneradmin\AppData\Local`.

### Local

- Command: `scripts\windows\test.ps1 -ScratchPath %LOCALAPPDATA%\agenthud-dev\build -Log %TEMP%\g3.log`.
- Setup: Windows PowerShell 5.1, the PROGRESS.md environment, the junction, `0bdab94`. test.ps1 makes its own fresh
  `agenthud-testprofile-<guid>` under `%TEMP%` and removes it afterwards.
- Result: exit 0 in **192 s** (07:56:27 to 07:59:39).
- The build-first step took 1 attempt: `Build complete! (27.40 secs)`.
- Support: `Test run with 9 tests in 0 suites passed after 0.379 seconds`.
- Core: the same 9 batch sizes as CI, **1338 executed: 1334 passed, 4 skipped, 0 failed**.
- `Removed 6 test preference file(s) from C:\Users\suzume\AppData\Local`.
- The CI and local sets of 1338 test cases are **identical**: a sorted diff finds no local-only and no CI-only case.
- **Reproducing the failure.** I ran `swift test --skip-build --filter
  WindowsExecutablesTests.testADrivelessPathIsRefusedEvenWhereAProgramExists`, with `APPDATA` and `LOCALAPPDATA` in a
  temporary folder, twice:
  - from the junction;
  - from `E:\桌面项目\agent-hud-open`, with `--package-path` set to the junction.

  It passed both times, because the test process ran in the package folder on `C:`. That matches the analysis in
  BLOCKING 1: here the package's drive is the system drive, and on the runner it is not.

### Compared with round 1 (1350 / 1346 / 4 / 0)

1350 − 14 + 2 = 1338:

- 14 tests are newly registered skips. None of them is in either run's log.
- 2 tests are new, and both pass locally:
  - `ProviderPathsWindowsTests.testTheMacDesktopAppsLocationsAreNeverUsed`
  - `WindowsExecutablesTests.testADrivelessPathIsRefusedEvenWhereAProgramExists`

  In CI only the first passed.
- `testClientsWithoutAWindowsSourceAreNeverRead` now also checks the session layouts, the local store's roots,
  `PermissionHooks.Source.isInstalled` and WorkBuddy's `models.json`. It passed in both places.
- `SessionProjectWindowsTests.testAWorkingDirectoryRecordedInItsShortSpellingBelongsToTheMainRepository` passed in
  both places.

### Skips

**Runtime skips: 4, the same in CI and locally.** All are in SKIPPED_TESTS.md §3:

- `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe`
- `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe`
- `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe`
- `SessionUsageProbeTests.testReportedSessionsUsageProbe`

§3's conditional Node skips did not trigger, because `node.exe` is on `PATH` in both places.

**Skip list: `scripts/windows/skipped-tests.txt` has 34 unique entries.**

- None of them appears in the local or the CI log.
- Each class's count matches §2.
- **8 of them are not named in §2** (BLOCKING 2). The other 26 are named.
- In the other direction, every name in §2 is in the file.

**Excluded files:** the 9 entries of `windowsSkippedTests` match §1's 9 rows, and all 9 are unchanged from `c258093`.

**The state line is not met as a whole.** SKIPPED_TESTS.md says: "State at M4 round 2 …: 1334 pass, 4 runtime
skips, 34 listed skips, 9 excluded files, 0 failures".

- It matches the local run exactly.
- CI measured 1333 pass and 1 failure.

### M4 (c), D-021: the real `%LOCALAPPDATA%` (`C:\Users\suzume\AppData\Local`)

| When | `Debug-windows-x86_64` | `*.plist` |
| --- | --- | --- |
| before G2 (07:51:28) | **absent** | 0 |
| just before G3 (07:56:26) | **absent** | 0 |
| after G3 (07:59:39) | **absent** | 0 |
| after the reproductions (08:11:24) | **absent** | 0 |

The real `%APPDATA%\Agent HUD Open` still has only its folders dated 2026-10-16 17:20 (from before D-021). Nothing in
it changed during the gates.

## G4: PASS

The Support golden tests ran in all three places:

- `recordIdentitiesMatchTheGoldenSamples`
- `digestsMatchTheNISTVectors`
- `millisecondDatesRoundTripTheGoldenSamples`
- `theRecordEncoderWritesTheGoldenSample`
- the other RecordCoding tests

| Where | Result |
| --- | --- |
| macOS CI | 10/10 passed, including `portableDigestsEqualCryptoKit` |
| Windows CI | 9/9 passed |
| Windows local | 9/9 passed |

`git diff 469bc44 0bdab94 -- Sources/AgentHUDSupport Tests/AgentHUDSupportTests` is empty.

## G6: PASS

- `python scripts\check-source-boundaries.py` at `0bdab94`: `Source boundaries and ignore rules passed.`, exit 0, 2.1 s.
- It also passed in CI: step 3 of the macOS `test` job and step 3 of the Windows job.

## M4 (a): provider tests use temporary fixtures only — PASS

Every fixture in the round-2 tests is under `FileManager.default.temporaryDirectory`:

- `ProviderPathsWindowsTests.directory()`, including the fake `claude.exe`/`codex.exe` under fixture
  `Library/…`/`.claude/local`/`Applications/…` folders.
- The WorkBuddy `models.json` with `"apiKey":"fixture-key"`.
- The locators are given `home:`, `path: ""` and `registered: []`.
- `WindowsExecutablesTests` copies nothing. It reads only `SystemRoot` and `whoami.exe` from System32, which are not
  user data.

**Observation (non-blocking, for the reviewer).** `testTheMacDesktopAppsLocationsAreNeverUsed` ends with
`ClaudeCodeProvider.standard(ledger: .inMemory(), persistent: false).watchedDirectories`. That is the production
wiring, with its defaults, against the **real `%USERPROFILE%`**. D-021 does not redirect `%USERPROFILE%`. Building it:

- **calls `ClaudeEngineLocator.find()`.** That checks for the real `%USERPROFILE%\.local\bin\claude.exe` (present on
  this machine) and the real `.local\share\claude\versions` folder. `WindowsExecutables.program` reads the head of the
  file found, to check that it is a PE image. The engine is not started.
- **makes a `ClaudeTranscriptStore(watchesChanges: true)` over the default roots.** On Windows its
  `FileChangeMonitor` opens a recursive directory watch on the real `%USERPROFILE%\.claude\projects` (present here)
  for as long as the value lives. It reads no transcript.
- **calls `ClaudeSessionOrigins.prepare()`.** This creates `%APPDATA%\Agent HUD Open\session-origins\claude`. Under
  test.ps1 that is the temporary profile, but a bare `swift test` would create it in the real `%APPDATA%`.

No credential or session content is read, so this does not break "tests never read real credentials". It is still
the only round-2 test that touches the real profile. The assertion only needs `desktopSessions == nil`, which a
provider built with injected values would check without the real home.

## M4 (b): D-006 and the excluded tests — PASS

- `git diff c258093 0bdab94 -- Sources/AgentHUDCore/<file>` is **0 bytes** for all six `windowsReplaced` files, and all
  six exist:
  - `System/UnixSocket.swift`
  - `System/UnixSocketListener.swift`
  - `System/ChildProcess.swift`
  - `System/FileChangeMonitor.swift`
  - `System/InstanceLock.swift`
  - `Providers/Codex/CodexDesktopIPC.swift`
- All 9 `windowsSkippedTests` files diff to 0 bytes against `c258093`.
- `Package.swift` did not change in round 2.

## G7 (observations, for the reviewer)

- **The round-2 gates are in Core, and the absent clients are exercised as absent:**
  - `AdditionalSource.layout` is nil, so `AdditionalLocalStore.roots` is `[]`.
  - `readQuota` returns an empty `ProviderQuota`.
  - `PermissionHooks.Source.isInstalled` is false.
  - `OpenAgentCredentials` returns `.null` for WorkBuddy's `models.json`.
  - `supportsDesktopApps` gates `ClaudeEngineLocator.candidates`, `CodexLocator.desktop`, `GrokBotLocator.isInstalled`,
    `GrokClient.fetchBot`, `GrokBotRoutineRuns.refresh`, `GrokLocalSessions.roots`, `ClaudeCodeProvider.standard`'s
    desktop sessions and `DeepSeekScriptRuntime.desktopApplication`.
- **`ClaudeEngineLocator.cli` on Windows** is now `.local\bin\claude`, the newest under `.local\share\claude\versions`,
  then `PATH`. This matches the SUPPORT_MATRIX Executables table, so round 1's G8 note 4 is resolved.
  `CodexLocator.cli` on Windows is `WindowsCodex.engines()` + `PATH`.
- **One ungated item, and it is harmless.** `AdditionalUsageProvider` still passes `grok.botDirectory` (the macOS
  `~/Library/Application Support/Grok Bot/…` path) as `botQuotaDirectory` on Windows.
  `GrokBotQuota.isQuotaChange` only resolves and compares that path with the changed paths it is given. It reads
  nothing, and the folder is not watched there.
- **Coverage note.** `TencentBuddyProviderTests.testCodeBuddyAndWorkBuddyStaySeparateAndSubagentsJoinTheirParent`
  also covers CodeBuddy, which is supported on Windows. With the test skipped there, CodeBuddy's subagent-joining is
  covered on Windows only by the 3 remaining TencentBuddy tests.

## G8: PASS, with non-blocking notes

**What matches the code:**

- **The revised D-036.** Every item in it matches the round-2 code:
  - the `package` access
  - layout, quota, hooks and `models.json` for Antigravity, ZCode and WorkBuddy
  - `supportsDesktopApps` for Claude's desktop app, the Codex `.app`, Grok Bot and DeepSeek's app
  - `.claude/local`, Cursor's `~/.cursor`, `~/.kimi/sessions` and Bun's global folder not used on Windows
- **D-034 now says** that packaging (M8) never ships `AgentHUDFakeEngine`.
- **SUPPORT_MATRIX:**
  - footnotes 2, 7 and 8, and the Kimi "older `~/.kimi` is not read" row, match `PlatformSupport`, `OpenAgentPaths`
    and `CursorClient`
  - the Executables table matches `ClaudeEngineLocator.cli`/`CodexLocator` on Windows
  - the new OpenCode config row has a source in §Sources
- **SKIPPED_TESTS** §1 and §3 match. §2 matches except for the 8 unnamed entries (BLOCKING 2). The state line matches
  the local run, but not CI (G3).
- **PROGRESS** is updated: the status line ("review round 2"), the milestone row with round 1's results and the
  round-2 fixes, and next steps. The BEL byte is gone. No control byte (0x00–0x1F other than tab/LF/CR) is left in
  PROGRESS, SKIPPED_TESTS, SUPPORT_MATRIX or DECISIONS.
- **`build.ps1`** now exits 1 with `swift is not on PATH` before its retry loop when swift is missing.

**Non-blocking notes:**

1. SUPPORT_MATRIX footnote 9 ("No source gives the shell Cursor runs a hook's command in on Windows …; D-037, M5")
   cites **D-037, which does not exist yet**. DECISIONS.md ends at D-036, and PROGRESS lists D-037 as "to write" in
   M5's work.
2. SKIPPED_TESTS §3 still has `DeepSeekProviderTests ×3 (compressed logs)` without names. It did not trigger in either
   run. This is the same issue as BLOCKING 2, in the runtime-skip list.
3. `SessionProjectWindowsTests` (no 8.3 names) and the new `WindowsExecutablesTests` test (no `whoami.exe`) have
   conditional `XCTSkip`s that are not in §3. Neither triggered here or in CI.

## Skipped tests

| Kind | Count | Registered |
| --- | --- | --- |
| Excluded files (`windowsSkippedTests`) | 9 files | yes, §1, an exact match; all unchanged from `c258093` |
| Skip list (`skipped-tests.txt`) | 34 tests | 26 named in §2; **8 only as counts** (BLOCKING 2); none ran; all 34 pass on macOS |
| Runtime skips (`XCTSkip`) | 4 tests, the same in CI and locally (the 4 opt-in probes) | yes, §3 |
| Conditional runtime skips (no `node.exe`; no 8.3 names; no `whoami.exe`) | 0 triggered | Node: §3; the other two are not listed (G8 note 3) |
| Support `portableDigestsEqualCryptoKit` (compiled only with CryptoKit) | 1 | yes (the AgentHUDSupportTests section) |

## Verdict summary

| Gate | Verdict |
| --- | --- |
| G1 | PASS (run 39030219177: 2086 XCTest / 8 skipped / 0 failed + 10 swift-testing; all 34 Windows-skipped tests pass on macOS; the macOS test warning is fixed) |
| G2 | PASS (run 39030218591 step 10, build.ps1, 1 attempt, no retry; local release build 261.4 s; warnings equal the baseline; no warning in port-written tests) |
| G3 | **FAIL** (CI: 1338 executed, 1333 passed, 4 skipped, **1 failed**, `testADrivelessPathIsRefusedEvenWhereAProgramExists`; local: 1338 / 1334 / 4 / 0; 8 skip-list entries not named in SKIPPED_TESTS.md) |
| G4 | PASS |
| G5 | N/A |
| G6 | PASS |
| M4 (a) fixtures only | PASS (observation: `ClaudeCodeProvider.standard` against the real home in one new test) |
| M4 (b) D-006 | PASS |
| M4 (c) `Debug-windows-x86_64` | absent before and after G3 |
| G7 | observations only |
| G8 | PASS with 3 non-blocking notes |

BLOCKING findings:

1. The Windows CI run for `0bdab94` fails. `WindowsExecutablesTests.testADrivelessPathIsRefusedEvenWhereAProgramExists`
   assumes that the process's current drive is the system drive. On the runner the package is on `D:`, so the test
   fails there every time. On that drive its refusal checks also pass trivially.
2. 8 entries of `skipped-tests.txt` (`GrokBotRoutineRunsTests` ×3, `GrokBotUsageTests` ×3,
   `TencentBuddyProviderTests` ×2) are not named in SKIPPED_TESTS.md, which TASK.md §6 G3 requires.

TESTS: FAILURES
