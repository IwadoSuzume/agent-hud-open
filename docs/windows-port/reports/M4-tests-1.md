# M4 test report, round 1

- Branch: `windows-port`. Head under test: `c1d64a0` ("Windows port M4: retry the CI release build on Swift Build's
  file-in-use race"), on `696284b` ("Windows port M4: providers on Windows"). M4 range: `469bc44...c1d64a0`: 51 files,
  +1095/−143.
- Run by: port-tester, 2026-10-17 (local times below are the machine's, UTC−4), Windows 11 Pro 10.0.26200.
- The working tree was clean at `c1d64a0` before and after the gates. Only this report was written in the repository.
  Nothing was committed or pushed.
- **Concurrent activity.** Other worktrees were building and testing with their own scratch paths and profiles while
  my gates ran: `wt5build` and `testprofile-wt5` changed at 07:25 and 07:30, `wtbuild` and `wtrel` at 07:43 and 07:44,
  and a `swift-build.exe` that was not mine was running at 07:45. None of my runs printed "being used by another
  process". All my builds used `%LOCALAPPDATA%\agenthud-dev\build` only.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | PASS: 2086 XCTest (8 skipped, 0 failures) + 10 swift-testing, the same as M3; every converted shared test ran and passed on macOS |
| G2 Windows build | PASS: CI green (build.ps1, 1 attempt, no retry); local release build green; library warnings equal the PROGRESS baseline exactly |
| G3 Windows tests | PASS: CI and local both 1350 executed, 1346 passed, 4 skipped, 0 failed (M3: 1310 / 1301 / 9 / 0); the test-case sets are identical |
| G4 determinism | PASS (macOS CI, Windows CI, Windows local) |
| G5 UI | N/A (M7+) |
| G6 boundaries | PASS |
| M4 (a): provider tests use temporary fixtures only | PASS: no read of the real profile; observations below |
| M4 (b) D-006: the six replaced files equal upstream `c258093` | PASS |
| M4 (c) D-021: stray `%LOCALAPPDATA%\Debug-windows-x86_64` | absent before and after G3 |
| Excluded test files (9) equal upstream `c258093` | PASS |
| G7 security review | review gate; observations below |
| G8 docs | PASS, with non-blocking notes (stale summary lines; two unsourced home-relative program places not in SUPPORT_MATRIX) |

## BLOCKING findings

None.

## G1: PASS

`Source checks` run **39028601964**: workflow_dispatch on `windows-port`, head `c1d64a06a17b…`, `completed` /
`success` (11:24:56Z to 11:36:03Z).

| Job | Runner | Conclusion | Steps |
| --- | --- | --- | --- |
| `test` (117384407874) | macos-15 | success | Check source boundaries: success. Test: success (11:25:10Z to 11:35:51Z). |
| `app` (117384407764) | macos-15 | success | Build application: success. Verify local signature and resources: success. |
| `macos` (117386393201) | ubuntu-latest | success | Tests and application passed: success. |

Totals from the `test` log:

- XCTest: `Executed 2086 tests, with 8 tests skipped and 0 failures (0 unexpected) in 425.752` s. This equals M2 and
  M3 (2086 / 8 / 0).
- The 8 skips are the same as before: the 4 `…Probe` tests, plus 4 in `AgentHUDDesktopTests`
  (`ArtworkMemoryTests`, `BotFrameTests`, `BotMarkTests`, `IslandAnimationTests`).
- swift-testing: `✔ Test run with 10 tests passed after 1.395 seconds`.
- `Source boundaries and ignore rules passed.`
- 0 `failed` test cases in the log.

**The converted shared tests ran on macOS.** Each one has a `passed` line in the macOS log:

- `AntigravityCLITests`: `testTheRunningAgyIsAskedForItsUsageInPrintMode`, `testOnlyARunningAgyProgramIsAsked`.
- `ClaudeCodeProviderTests`, 5 tests: `testBuildsReportFromMocks`, `testEngineFailureThrows`,
  `testEngineModeUsesGetUsageAndDiscoversFromTranscripts`, `testQuotaFailureAndMissingEngineStillReportLocalCompletions`,
  `testUnavailablePlanLimitsKeepLocalDataWithNotice`.
- `ClaudeEngineTests`, 6 tests: `testClientRunsAFakeEngine`, `testClientTimesOut`,
  `testLocatorFallsBackToTheDesktopAppsEngine`, `testLocatorPrefersNewestVersion`,
  `testProviderKeepsExpiredReadingUntilEngineConfirmsReset`, `testSignedOutIsToldApartFromALoginWithoutPlanLimits`.
- `OpenCodeSessionObserverTests.testNativePluginRecordsOnlyFinishedTurnsOfTopLevelSessions` and
  `PiSessionObserverTests.testNativeExtensionLifecycleRetriesHeartbeatAndPrivacy` (now through `TestNode`).
- `ProviderAccountTests.testClaudeLoginChangeDuringTheQueryDiscardsTheReading`,
  `SubscriptionTests.testClaudeProviderCarriesTheDetailedPlanIntoItsReport`,
  `UsageInsightsTests.testClaudeSessionAndWeeklyWindows`.
- `CopilotProviderTests.testTokenSourcesInOrder`.
- `DeepSeekQuestionObserverTests.testCancellingIdleWebSocketClosesTheConnectionWithoutAHostFrame`. This is the macOS
  `IdleQuestionHost`, which is now inside `#if !os(Windows)`.

None of them was skipped on macOS, so the `TestEngine` shell scripts work there.

## G2: PASS

**CI.** `Windows port` run **39028601296**: push, head `c1d64a0`, `completed` / `success` (11:24:55Z to 11:43:14Z).
Job `swift` (117384403700, windows-latest).

| # | Step | Conclusion |
| --- | --- | --- |
| 1–4 | Set up, checkout, Check source boundaries, System SQLite version | success |
| 5–6 | Cache the Swift installer / Download (skipped by design) | success / skipped |
| 7–9 | Verify and install Swift, Toolchain, Cache the Swift build | success |
| 10 | **Build (release)**: `scripts/windows/build.ps1 -c release`, 11:27:11Z to 11:36:08Z | **success** |
| 11 | **Test**: `scripts/windows/test.ps1`, 11:36:08Z to 11:42:35Z | **success** |
| 12 | Compile a smoke package | success |
| 22–25 | Post steps, Complete job | success |

- **Retry: none.** Step 10 built on its first attempt: `Build complete! (526.43 secs)`. The log has no "hit a file in
  use" line and no "being used by another process".
- **The D-032 extension is justified.** The previous run, 39028057775 on `696284b`, failed in step 10, Build
  (release). Its log says: `The process cannot access the file because it is being used by another process.` /
  `error: Touch D:\\a\\…\\Release-windows-x86_64\\AgentHUDOpen_AgentHUDCoreTests.bundle failed with a nonzero exit
  code`.

**Local.** I ran `swift build -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build` with the PROGRESS.md Swift
environment, from the junction `%LOCALAPPDATA%\agenthud-dev\src`, at `c1d64a0`. The output was redirected through
`cmd /c "… > log 2>&1"`. Result: exit 0, `Build complete! (166.53 secs)` (169 s wall-clock, 07:26:17 to 07:29:06). No
file-in-use line.

**Library warnings: exactly the PROGRESS baseline (D-033), locally and in CI's step 10.** Each warning appears once.

| Warning | Where | In baseline |
| --- | --- | --- |
| `'strerror' is deprecated` | `Sources/AgentHUDCore/MCP/MCPStdio.swift:54` | yes |
| `'close' is deprecated` | `Hooks/Permission/PermissionHookClient.swift:38`, `Providers/Kit/Zstandard/ZstandardReader.swift:46` | yes |
| `'init(cString:)' is deprecated` | `Providers/Antigravity/AntigravityCLI.swift:18` | yes |
| `result of call to 'wait(until:)' is unused` | `Providers/Codex/CodexDesktopStream.swift:170` | yes |
| `no 'async' operations occur within 'await' expression` | `Hooks/Permission/DeepSeekQuestions.swift:106` | yes |
| `WinSDK.swiftmodule … 'wchar_t' broken by a context change` | toolchain: not in either release build this time; 4× in CI's test build | yes |

**No new library warning.** None of the M4 source files warns: `WindowsExecutables`, `WindowsCodex`,
`PlatformSupport`, `Win32.environment`, and the locators.

- **The release build now also builds `AgentHUDFakeEngine.exe`.** The log shows `AgentHUDFakeEngine-product`, and
  the file is at `release\AgentHUDFakeEngine.exe`. The test helper is an `executableTarget` of the Windows manifest,
  so a plain `swift build -c release` produces it.
- This is harmless for G2. M8's packaging must leave the file out (see G7).

**Test-build warnings (G3's build, not part of G2 since D-033).** CI and local show the same list:

- **Upstream test lines** that warn only on Windows, unchanged since M3: `MCPStdioTests.swift` (`close`, `dup`,
  `dup2`), `PanelToolsSpanTests.swift:91`, `CollectionSignalTests.swift:331`, `UsageRefreshTests.swift:73`,
  `DeepSeekProviderTests.swift:525`.
- **Two new warnings on lines M4 wrote.** D-033 says "the port's own test files are kept warning-free". Non-blocking
  note 1 covers both.
  - `Tests/AgentHUDCoreTests/Providers/Claude/ClaudeEngineTests.swift:115:9: warning: result of 'try?' is unused`.
    The line is `try? TestEngine.write([.sleep(30)], to: fake)`: `@discardableResult` does not cover the `Optional`
    that `try?` makes. Upstream's line, `try? "…".write(…)`, returned `Void` and did not warn. This line is shared, so
    the warning **also appears in the macOS `test` job's log** (repeated per compile job). It is a new macOS test-build
    warning.
  - `Tests/AgentHUDCoreTests/WindowsSupport/SessionProjectWindowsTests.swift:71:21: warning: 'init(decodingCString:as:)'
    is deprecated` (new in M4: `testAWorkingDirectoryRecordedInItsShortSpellingBelongsToTheMainRepository`).

## G3: PASS

**CI (step 11 of run 39028601296).**

- The build-first step (now `build.ps1 --build-tests`) took 1 attempt: `Build complete! (186.15 secs)`.
- Support: `Test run with 9 tests in 0 suites passed after 0.678 seconds`.
- Core, 9 batches: 115 + 127 + 127 + 174 + 188 + 221 + 58 + 242 + 98 = **1350 executed: 1346 passed, 4 skipped, 0
  failed**.
- `Removed 6 test preference file(s) from C:\Users\runneradmin\AppData\Local`.
- Node.js is on the runner's `PATH`, so the Node-dependent tests ran there too.

**Local.**

- Command: `scripts\windows\test.ps1 -ScratchPath %LOCALAPPDATA%\agenthud-dev\build -Log %TEMP%\g3.log`.
- Setup: Windows PowerShell 5.1, the PROGRESS.md environment, the temporary profile
  `%LOCALAPPDATA%\agenthud-dev\testprofile` (APPDATA/LOCALAPPDATA redirected), through the junction, at `c1d64a0`.
- Result: exit 0 in **177 s** (07:30:37 to 07:33:34).
- The build-first step took 1 attempt: `Build complete! (24.85 secs)`.
- Support: `Test run with 9 tests in 0 suites passed after 0.379 seconds`.
- Core, 9 batches, the same as CI: **1350 executed: 1346 passed, 4 skipped, 0 failed**. The set of 1350 test cases is
  identical to CI's: a sorted-list diff found no local-only and no CI-only cases.
- `Removed 6 test preference file(s) from C:\Users\suzume\AppData\Local`.
- Node.js v24.18.1 is on `PATH` here.

**Compared with M3 (1310 / 1301 / 9 / 0).**

- 40 more tests run.
- 14 entries left the skip list and now run and pass on Windows through `TestEngine`/`TestNode`: every name the
  removed lines of `skipped-tests.txt` listed.
- The 5 Node-dependent runtime skips no longer skip here: the DeepSeek compressed-log tests ×3, and the OpenCode and
  Pi plugin tests.
- `DeepSeekQuestionObserverTests` is no longer excluded. 10 of its 11 tests ran and passed on Windows, and the 11th is
  on the skip list.
- New Windows tests, all passed:
  - `ProviderEnginesWindowsTests` ×4
  - `ProviderPathsWindowsTests` ×3
  - `WindowsExecutablesTests` ×5
  - `ChildProcessWindowsTests.testAGivenEnvironmentKeepsTheSystemFolders` and
    `…testNodeStartsInAnOtherwiseEmptyEnvironment`
  - `SessionProjectWindowsTests.testAWorkingDirectoryRecordedInItsShortSpellingBelongsToTheMainRepository` (it ran
    here, not skipped: `C:` keeps 8.3 names)

**Skips: all registered, in both directions.**

- **Runtime skips, 4, identical in CI and locally.** All are in SKIPPED_TESTS.md §3:
  - `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe`
  - `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe`
  - `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe`
  - `SessionUsageProbeTests.testReportedSessionsUsageProbe`
- **The rest of §3** lists conditional skips that did not trigger, because `node.exe` is on `PATH` in both places: the
  `DeepSeekProviderTests` ×3, and the `OpenCodeSessionObserverTests`/`PiSessionObserverTests` plugin tests (`TestNode`).
  §3 says they run where Node is, which matches.
- **Skip list:** `scripts/windows/skipped-tests.txt` has **20** entries. SKIPPED_TESTS.md §2 names exactly these 20
  (1 + 2 + 3 + 1 + 1 + 3 + 2 + 3 + 1 + 1 + 2), and every §2 name is in the file. None of the 20 names appears in the
  local or the CI log.
- **Excluded files:** the 9 in `windowsSkippedTests` are §1's 9 rows, and all 9 are unchanged from `c258093`.
- **New Windows variants named in §2 exist and ran:**
  - `ProviderEnginesWindowsTests.testOnlyARunningAgyProgramIsAsked`
  - `…testCodexClientPerformsHandshakeWithoutStartingSession`
  - `…testAClientIsFoundWhereItsCommandIsInstalled`
  - `…testACommandRunsFromTheHomeFolderAndIsStoppedWhenItTakesTooLong`
  - `WindowsExecutablesTests.testCodexIsFoundWhereNpmInstallsItsEngine`
  - `ProviderPathsWindowsTests.testClientsWithoutAWindowsSourceAreNeverRead`

**M4 (c), D-021: the real `%LOCALAPPDATA%` (`C:\Users\suzume\AppData\Local`).**

| When | `Debug-windows-x86_64` | `*.plist` |
| --- | --- | --- |
| before G2/G3 (07:26:00) | **absent** | 0 |
| just before G3 (07:30:31) | **absent** | 0 |
| after G3 (07:33:34, and again at 07:45) | **absent** | 0 |

`DeepSeekQuestionObserverTests` is no longer excluded, and its 10 Windows tests did not create the folder. The one
test that opens a `URLSession` WebSocket is on the skip list (D-021's M4 wording).

## G4: PASS

The Support golden tests ran in all three places:

- `recordIdentitiesMatchTheGoldenSamples`
- `digestsMatchTheNISTVectors`
- `millisecondDatesRoundTripTheGoldenSamples`
- `theRecordEncoderWritesTheGoldenSample`
- plus the other RecordCoding tests

| Where | Result |
| --- | --- |
| macOS CI | all passed (10/10, including `portableDigestsEqualCryptoKit`) |
| Windows CI | 9/9 passed |
| Windows local | 9/9 passed |

M4 does not touch `Sources/AgentHUDSupport` or the fixtures.

## G6: PASS

- `python scripts\check-source-boundaries.py` at `c1d64a0`: `Source boundaries and ignore rules passed.`, exit 0,
  0.9 s.
- It also passed in both CI runs: the macOS `test` job's step 3, and step 3 of the Windows job.

## M4 (a): provider tests use temporary fixtures only — PASS

**Method.** I grepped the whole M4 test diff (`git diff 469bc44...c1d64a0 -- Tests/`, 1042 lines) for `USERPROFILE`,
`APPDATA`, `LOCALAPPDATA`, `homeDirectoryForCurrentUser`, `NSHomeDirectory`, `.claude`, `.codex`, `.copilot`,
`.cursor`, `ProcessInfo…environment`, `getenv`, `"HOME"` and `~/`. I also read every changed and new test.

**Fixtures.**

- Every fake engine, profile and folder is created under `FileManager.default.temporaryDirectory` and removed in
  teardown: `agenthud-engine-…`, `agenthud-home-…`, `agenthud 引擎 …`, `agenthud 路径 …`, `agenthud 程序 …`.
- The `.claude.json` hits are fixtures in those folders, passed as `accountProfileURL:`.
- The Copilot tests inject `file:`/`keychain:` closures and an `APPDATA` pointing at a temporary folder.
- `ClaudeEngineLocator`/`MCPClient` are given `home:`, `path:`, `applications:` and `registered: []`.

**No M4 test reads the user's real client data.** The hits that touch the real profile only compute paths or set a
working directory:

- **Path computations, nothing read:**
  - `CopilotProviderTests` (Windows branch) and `ProviderPathsWindowsTests` compare a path with
    `WindowsFolders.roamingAppData…GitHub CLI/hosts.yml`. The file reader is the injected closure.
  - `testCursorIsReadFromItsRoamingFolder` compares `CursorClient.defaultDatabase` with a path.
- **Working directory only:** `ProviderEnginesWindowsTests.testACommandRunsFromTheHomeFolder…` runs the fake recorder
  with `UserHome.directory` (the real `%USERPROFILE%`, which D-021 does not redirect) as its working directory. The
  recorder writes only into the temporary folder. This is the behaviour under test (`MCPClientCommand` runs from home).
- **System variables only:** `SystemRoot` is read in `ChildProcessWindowsTests` and `WindowsExecutablesTests`, and
  `whoami.exe` is copied from System32. Neither is user data.

**Observation (non-blocking, reviewer to judge).** Some Windows defaults in Core are not injectable. Under the gates
they resolve into the temporary profile, through `APPDATA`/`LOCALAPPDATA`, which `WindowsFolders` reads first:

- `WindowsCodex.engines()`, called by `CodexLocator.cli` with no `appData:`
- `DeepSeekCredentialLocator.module`'s npm roots (`%AppData%\npm\node_modules`, `%LocalAppData%\npm-cache\_npx`)
- `CursorClient.defaultDatabase`

So `ProviderEnginesWindowsTests.testAClientIsFoundWhereItsCommandIsInstalled`'s `XCTAssertNil(found(.codex))` probes
for existence in `%APPDATA%\npm\node_modules\@openai\codex…`. Under `test.ps1` that is the temporary profile. A bare
`swift test` would probe the real one: here that folder has no `@openai\codex` (checked for existence only), so it
would still pass. This is existence probing, not reading data, and the gate commands redirect it.

## M4 (b): D-006 and the excluded tests — PASS

- `git diff c258093 c1d64a0 -- Sources/AgentHUDCore/<file>` is **empty** (0 bytes) for all six `windowsReplaced` files,
  and all six still exist:
  - `System/UnixSocket.swift`
  - `System/UnixSocketListener.swift`
  - `System/ChildProcess.swift`
  - `System/FileChangeMonitor.swift`
  - `System/InstanceLock.swift`
  - `Providers/Codex/CodexDesktopIPC.swift`
- All 9 remaining `windowsSkippedTests` files diff empty against `c258093`.
- `DeepSeekQuestionObserverTests.swift` left the exclusion list. Its shared-file change is 10 lines: guarded imports,
  and the macOS `IdleQuestionHost` inside `#if !os(Windows)`.

## G7 (observations, for the reviewer)

- **D-019 is now enforced centrally.** On Windows, `Executables.first` → `WindowsExecutables.program` accepts only an
  absolute drive/UNC path to an existing regular file that is a PE image (`MZ`) and not `.cmd`/`.bat`.
  - Tests cover this: `testOnlyExistingProgramImagesAtAbsolutePathsAreStarted` refuses `/usr/bin/env`,
    `/opt/homebrew/bin/node`, `shim.cmd`, `shim.bat. .`, a text file named `.exe`, and a folder.
  - `ProviderEnginesWindowsTests` checks that npm `.cmd` shims and extensionless batch files are never chosen.
  - The presence checks that read `/Applications` are compiled out on Windows: `ProviderData`, `GrokBotLocator`,
    `AntigravityService`, `DeepSeekScriptRuntime`.
- **D-035.** Only `SystemRoot`/`windir`/`SystemDrive` are added to a given environment. The test checks that nothing
  else is added (no `PATH`, no `USERPROFILE`) and that a caller's value wins in any case.
- **`AgentHUDFakeEngine.exe` is a release product.** It runs any steps in a `<name>.fake.json` beside it, including
  writing files. It is a test helper that `swift build -c release` now builds. M8's packaging must not ship it. The
  alternative is to build it only with the tests.

## G8: PASS, with non-blocking notes

**What matches.**

- **D-034, D-035, D-036 are recorded and match the code:**
  - `TestEngine`/`TestNode`/`AgentHUDFakeEngine`
  - `ChildProcess.systemVariables` and the `GetEnvironmentVariableW`-based `Win32.environment`
  - `PlatformSupport.supports` is false exactly for `.antigravity`, `.zcode`, `.workbuddy`, and
    `supportsDeepSeekDesktop` is false
  - `isInstalled` is guarded
  - Antigravity's `running`/`permissionEndpoints` are gated
  - `DeepSeekScriptRuntime.desktopApplication` returns nil
- **D-019 and D-032 are revised to match.** `build.ps1` is used by `test.ps1` and by `windows.yml` step 10, and it
  retries only on "being used by another process".
- **SUPPORT_MATRIX claims match the code:**
  - Copilot `hosts.yml`: `GH_CONFIG_DIR` → `XDG_CONFIG_HOME\gh` → `%AppData%\GitHub CLI`, an `APPDATA` without a folder
    falling back to the known folder
  - Cursor `%APPDATA%\Cursor\User\globalStorage\state.vscdb`
  - Codex npm engine places, in the order listed
  - Node `node.exe` on `PATH`
  - the DeepSeek npm roots
  - Antigravity/ZCode/WorkBuddy 🔶, and the DeepSeek and Grok Bot desktop apps 🔶
  - Qwen and Grok are supported, and `ProviderPathsWindowsTests` asserts it
- **SKIPPED_TESTS §1–§3 match** `Package.swift`, `skipped-tests.txt` and the observed runtime skips exactly (see G3).
- PORTING_PLAN's DeepSeekQuestionObserverTests row is updated.

Non-blocking notes:

1. **Two port-written test lines warn** (G2 above), against D-033's "port's own test files are kept warning-free".
   - `ClaudeEngineTests.swift:115` warns on **macOS as well**. A shared upstream test file gained a warning, and
     `_ = try? …` would fix it.
   - `SessionProjectWindowsTests.swift:71` uses the deprecated `String(decodingCString:as:)`.
2. **SKIPPED_TESTS.md "State at M3"** still says "1301 pass, 9 runtime skips, 34 listed skips, 10 excluded files". The
   lists below it now have 20 listed skips and 9 excluded files. The measured M4 state is **1346 pass, 4 runtime skips,
   20 listed skips, 9 excluded files, 0 failures**.
3. **PROGRESS.md was not changed by M4**, so it is stale. Its last edit is `469bc44`.
   - Status still says "M4 … implementation … in the worktree".
   - The milestone table has "M4 Providers | todo".
   - Next steps item 1 says "To do: squash into one M4 commit on `windows-port`, full G3, push, CI", which is done at
     `c1d64a0`.
   - Line 76 also contains a literal **BEL control byte (0x07)** where `\a` was meant: `%LOCALAPPDATA%<BEL>genthud-dev\wt`
     should be `%LOCALAPPDATA%\agenthud-dev\wt`. This line predates M4.
4. **Unsourced home-relative program places are still searched on Windows, and SUPPORT_MATRIX does not list them.**
   D-019/D-036 drop only POSIX-root places. The macOS layouts under the user's home still pass `Executables.first` on
   Windows when a PE image sits there:
   - **Claude Code:** `ClaudeEngineLocator.cli` still lists `%USERPROFILE%\.claude\local\claude(.exe)`. `desktop(home:)`
     still lists `%USERPROFILE%\Library\Application Support\Claude\claude-code\<v>\<b>\claude.app\Contents\MacOS\claude`.
     `ClaudeEngineTests.testLocatorFallsBackToTheDesktopAppsEngine` now runs on Windows and asserts that the second is
     found.
   - **Codex:** `CodexLocator.desktop` still lists `%USERPROFILE%\Applications\{Codex,ChatGPT}.app\Contents\Resources\…`,
     **before** npm's engine.
   - SUPPORT_MATRIX's Executables table gives Claude Code as `.local\bin`, `versions`, `PATH`, and Codex as npm, then
     `PATH`. It says the desktop apps are not supported on Windows.
   - This is not a security issue: the places are inside the user's own profile. It is a matrix-versus-code mismatch
     and a path without a source (TASK.md §7.2). Either document these places or drop them on Windows (reviewer to
     judge).
5. **`skipped-tests.txt` grouping.** The two `MCPClientTests` entries sit under the "Approvals (M5): …
   URLSessionWebSocketTask…" comment. SKIPPED_TESTS §2 has them as permanent, with `ProviderEnginesWindowsTests`
   variants. The comment does not describe them.

## Skipped tests

| Kind | Count | Registered |
| --- | --- | --- |
| Excluded files (`windowsSkippedTests`) | 9 files | yes, §1 (exact match, all unchanged from `c258093`) |
| Skip list (`skipped-tests.txt`) | 20 tests | yes, §2 (exact match both ways, none ran) |
| Runtime skips (`XCTSkip`) | 4 tests, the same in CI and locally (the 4 opt-in probes) | yes, §3 |
| Conditional runtime skips (no `node.exe` on `PATH`) | 0 triggered (Node present locally and on the runner) | yes, §3 |
| Support `portableDigestsEqualCryptoKit` (compiled only with CryptoKit) | 1 | yes (AgentHUDSupportTests section) |

## Verdict summary

| Gate | Verdict |
| --- | --- |
| G1 | PASS (run 39028601964: 2086 XCTest / 8 skipped / 0 failed + 10 swift-testing; converted tests ran on macOS) |
| G2 | PASS (run 39028601296 step 10 via build.ps1, 1 attempt, no retry; local release build 166.5 s; warnings = baseline) |
| G3 | PASS (CI and local: 1350 executed, 1346 passed, 4 skipped, 0 failed; all skips registered both ways) |
| G4 | PASS |
| G5 | N/A |
| G6 | PASS |
| M4 (a) fixtures only | PASS (no real-profile read; non-injectable Windows defaults rely on the D-021 redirect) |
| M4 (b) D-006 | PASS |
| M4 (c) `Debug-windows-x86_64` | absent before and after G3 |
| G7 | observations only |
| G8 | PASS with 5 non-blocking notes |

BLOCKING findings: none.

TESTS: ALL_PASS
