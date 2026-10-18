# M6 test report, round 3

- Branch: `windows-port`. Head under test: `f531b63` ("Windows port M6 round 3: an isolated real-engine test, a lock
  holder found through a junction"). M6 range `0f51d89...f531b63`: 74 files, +3282/−49.
- Run by: port-tester, 2026-10-18, 16:40–17:00 local time (UTC−4). Machine: Windows 11 Pro 10.0.26200, not elevated.
- The working tree was clean at `f531b63` before and after the gates. The only untracked file is
  `docs/windows-port/reports/M6-review-3.md`, which the reviewer wrote in parallel; it is not mine. I wrote only this
  report. I committed nothing, pushed nothing, and made only read calls to the GitHub API (no re-run was needed).
- Local gates ran through the junction `%LOCALAPPDATA%\agenthud-dev\src` (→ `E:\桌面项目\agent-hud-open`) with
  `--scratch-path %LOCALAPPDATA%\agenthud-dev\build`. Since 2026-10-18, `%LOCALAPPDATA%\agenthud-dev` is itself a
  junction to `E:\agenthud-dev`, so both the source and the build folder are reached through a junction (D-044's
  situation). Logs are in `%LOCALAPPDATA%\agenthud-dev\tester6`.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | **PASS**: `Source checks` run 39164577291, attempt 1, `test`/`app`/`macos` success; 2087 XCTest, 8 skipped, 0 failures; swift-testing 10 passed |
| G2 Windows build | **PASS** locally (release, 169 s, exactly the 6 baseline lines) and in CI (run 39164570245 step 11, same 6 lines) |
| G3 Windows tests | **PASS** locally (1451 executed, 1447 passed, 4 skipped, 0 failed), under an 8.3 `TEMP` (65/65), and in CI (1451 / 4 / 0) |
| G4 determinism | **PASS**: `RecordCodingGoldenTests` 4/4 locally, in Windows CI, and in macOS CI |
| G5 UI (protocol) | **PASS**: C# 11/11, `check-protocol.py` 19 valid + 15 invalid, 0 failures, locally and in CI. `--demo` snapshot: **N/A** (joins in M7) |
| G6 boundaries | **PASS** locally and in both CI runs |
| G7/G8 | notes below; nothing blocking |

## G1: PASS

`Source checks` run **39164577291**:

- Trigger: workflow_dispatch on `windows-port`, head `f531b6328f03dbd4ce4eeb7cb898c98b76b5fbe6`.
- Result: `completed` / `success`, `run_attempt` 1, 20:43:04Z to 20:53:53Z.
- Runner image: `macos-15-arm64` 20260907.0337.1, provisioner 20260828.587. Same as rounds 1 and 2.

| Job | Id | Conclusion | Time |
| --- | --- | --- | --- |
| `test` | 117784733650 | success | 20:43:12Z to 20:53:47Z |
| `app` | 117784733921 | success | 20:43:16Z to 20:51:06Z |
| `macos` | 117787143047 | success | 20:53:49Z to 20:53:52Z |

- `test` job:
  - `Source boundaries and ignore rules passed.`
  - `Executed 2087 tests, with 8 tests skipped and 0 failures (0 unexpected) in 410.945 (411.082) seconds`.
  - `✔ Test run with 10 tests passed after 1.184 seconds.`
- **The upstream flaky test passed on attempt 1.**
  `StatsWindowLifecycleTests.testNativeRestoreFitsContentUpdatedWhileMiniaturized` passed in 1.741 s, so no
  `rerun-failed-jobs` was needed.
- **The 8 macOS skips are the same as in rounds 1 and 2.**
  - The four `…Probe` tests.
  - `ArtworkMemoryTests.testProbeWritesEveryBakedMarkBotAndAccent`.
  - `BotFrameTests.testFrameCost`.
  - `BotMarkTests.testAReminderMarkOpensAsItsLogoAndTurnsIntoItsBotOnceItsCardHasOpened`.
  - `IslandAnimationTests.testAGlowThatClosesStopsItsFrames`.
- All 34 entries of `scripts/windows/skipped-tests.txt` have a `passed` line in this macOS log (checked by script:
  34/34).
- **macOS warnings: the same file:line set as round 1, nothing new.**
  - Core: `DeepSeekQuestions.swift:106`, `AntigravityCLI.swift:18`.
  - Core tests: `PermissionHookTests` 435/442/453, `PanelToolsSpanTests:91`, `DeepSeekProviderTests:525`,
    `CollectionSignalTests:331`, `UsageRefreshTests:73`.
  - Desktop tests: `AgentSeparationTests` 136/209/243, `JoinedGlassTests` 192/246, `ScreenStyleHUDTests:254`.
- M6 changes no Desktop or Support code. `git diff --stat 0f51d89 f531b63` over `Sources/AgentHUDDesktop`,
  `Sources/AgentHUDOpenApp`, `Tests/AgentHUDDesktopTests`, `Sources/AgentHUDSupport` and `Tests/AgentHUDSupportTests`
  shows only `Resources/THIRD_PARTY_NOTICES.txt` (+30). The root notices file and that copy are identical (`cmp`).

## Windows CI (push run 39164570245): success

- Job `swift` (117784710677), head `f531b63`, attempt 1, `success`, 20:43:01Z to 20:56:19Z.
- Every step succeeded. The only exception is step 7, "Download the Swift installer", which was skipped because the
  installer was cached.

| Step | Result |
| --- | --- |
| 3 Check source boundaries | `Source boundaries and ignore rules passed.` |
| 4 Shell protocol and .NET tests (G5) | `Passed!  - Failed: 0, Passed: 11, Skipped: 0, Total: 11` and `Protocol fixtures: 19 valid, 15 invalid, 0 failure(s).` |
| 11 Build (release) | `Build complete! (291.69 secs)`; warnings: exactly the 6 baseline lines (listed under G2), each once; no `wchar_t` line |
| 12 Test | Support `Test run with 9 tests … passed`; Core batches 113 + 126 + 125 + 201 + 201 + 255 + 71 + 252 + 107 = **1451 executed, 4 skipped, 0 failures**; `Removed 6 test preference file(s)` |
| 13 Compile a smoke package | success |

- The tests that failed only on the runner in earlier rounds all passed in CI:
  - `HookFormsWindowsTests.testTheLongFormOfAPathBeyondMaxPath` (round 2's CI failure)
  - `HookFormsWindowsTests.testAZipsCopyIsTransientWhicheverWayTheTemporaryFolderIsSpelled`
  - `InstanceLockWindowsTests.testAHolderNamedThroughAJunctionCountsAsRunning` (new, D-044)
  - `EngineServeEndToEndTests.testARealRequestGoesThroughTheProtocolAndHooksChangeOnlyWithTheirSwitch` (11.7 s)
  - `EngineServeEndToEndTests.testAShellThatNeverReadsCannotHoldTheEngine`
  - `FileChangeMonitorWindowsTests.testAWatchedDirectoryThatGoesAwayAsksForAFullScan` (the known flaky test)
- The CI runtime skips are the same 4 `…Probe` tests as locally.

## G2: PASS

- **Command:** `scripts\windows\build.ps1 -Log <tester6>\g2.log -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build`.
  It ran in the PROGRESS environment, from the junction, at 16:45:00.
- **Result:** exit 0, **173 s** wall clock, `Build complete! (169.32 secs)`. It took a single attempt, with no file-in-use
  line. `release\agenthud-engine.exe` was rebuilt at 16:47:55 (29,112,832 bytes).
- **Errors:** no `error:` line.
- **Warnings:** exactly the 6 baseline lines (D-033), each once, and nothing else:
  - `MCP\MCPStdio.swift:59:110` `'strerror' is deprecated`
  - `Hooks\Permission\PermissionHookClient.swift:38:17` `'close' is deprecated`
  - `Providers\Kit\Zstandard\ZstandardReader.swift:46:9` `'close' is deprecated`
  - `Providers\Antigravity\AntigravityCLI.swift:18:44` `'init(cString:)' is deprecated`
  - `Providers\Codex\CodexDesktopStream.swift:170:83` `result of call to 'wait(until:)' is unused`
  - `Hooks\Permission\DeepSeekQuestions.swift:106:20` `no 'async' operations occur within 'await' expression`

  Core was recompiled in full, so this count is complete. The `wchar_t` toolchain line did not appear, which is under
  the baseline. None of round 3's changed files printed a warning (`InstanceLock+Windows.swift`, `EngineServe.swift`,
  `EngineServer.swift`, `ShellProtocol.swift`).
- **.NET:** `dotnet build windows\AgentHUD.sln -c Release --no-incremental`, with the telemetry opt-outs: exit 0,
  `0 个警告 / 0 个错误` (0 warnings, 0 errors). The solution formally joins G2 from M7; it is reported here for
  completeness.
- **Test build (outside G2, D-033):** the G3 build was incremental (`Build complete! (18.30 secs)`). Its only test-file
  warning is the upstream `DeepSeekProviderTests.swift:525` (columns 13 and 17), which is known from M5. None of the
  port's test files printed a warning.

## G3: PASS

### Full run

- **Command:** `& scripts\windows\test.ps1 -ScratchPath %LOCALAPPDATA%\agenthud-dev\build -Log <tester6>\g3.log`.
  It ran in Windows PowerShell 5.1, in the PROGRESS environment, with the real `TEMP`.
- **Result:** exit 0 in **213 s** (16:48:07 to 16:51:40).
  - Build-first step: 1 attempt.
  - Support: `Test run with 9 tests in 0 suites passed after 0.384 seconds.`
  - Core, 9 batches: 113 (2 skipped) + 126 + 125 + 201 (1 skipped) + 201 + 255 + 71 + 252 (1 skipped) + 107 =
    **1451 executed: 1447 passed, 4 skipped, 0 failed**.
  - `Removed 6 test preference file(s) from C:\Users\suzume\AppData\Local`.
- **This matches** PROGRESS's local round-3 line and the SKIPPED_TESTS.md state line ("1447 pass, 4 runtime skips, 34
  listed skips, 7 excluded files, 0 failures"). It also matches the Windows CI count exactly.
- **D-044 (the build and source behind a junction) holds.** All 6 `InstanceLockWindowsTests` passed, including the new
  `testAHolderNamedThroughAJunctionCountsAsRunning` (0.068 s). All 6 `EngineServeEndToEndTests` passed, including
  `testAnEngineThatFindsAnotherCopyRunningSaysWhichAndExits` (0.156 s), whose lock holder is the engine started from
  `…\agenthud-dev\build` (a junction).
- **The known flaky test** `FileChangeMonitorWindowsTests.testAWatchedDirectoryThatGoesAwayAsksForAFullScan` passed.

### The changed classes under an 8.3 `TEMP` (as the runner's `RUNNER~1`)

- **Setup:** I created `C:\Users\suzume\AppData\Local\Temp\agenthud tester6 LongNamedTemporaryFolder`. Its 8.3 name,
  from `dir /x` and `Scripting.FileSystemObject.ShortPath`, is `C:\Users\suzume\AppData\Local\Temp\AG657C~1`.
- **Command:** `TEMP` and `TMP` set to `…\Temp\AG657C~1`, then
  `& scripts\windows\test.ps1 -ScratchPath <build> -Log <tester6>\g3short.log -Filter @(…7 classes…)`. The filter
  was a real array; the result is one batch.
- **Result:** exit 0 in 32 s. **65 executed, 0 failures, 0 skipped.** The tests' `TemporaryDirectory.*` folders were
  created inside that folder, so the short spelling was in effect.

| Class | 8.3 `TEMP` | Full run |
| --- | --- | --- |
| `HookFormsWindowsTests` | 24/24 | 24/24 |
| `InstanceLockWindowsTests` | 6/6 | 6/6 |
| `EngineServeEndToEndTests` | 6/6 | 6/6 |
| `ShellProtocolTests` | 10/10 | 10/10 |
| `SessionProjectWindowsTests` | 6/6 | 6/6 |
| `WindowsExecutablesTests` | 7/7 | 7/7 |
| `WindowsProcessesTests` | 6/6 | 6/6 |

Every short-spelling-dependent test **ran rather than skipped**:

- `HookFormsWindowsTests.testTheLongFormOfAPathBeyondMaxPath`
- `…testAZipsCopyIsTransientWhicheverWayTheTemporaryFolderIsSpelled`
- `SessionProjectWindowsTests.testAWorkingDirectoryRecordedInItsShortSpellingBelongsToTheMainRepository`
- `WindowsExecutablesTests.testClaudesEngineIsRecognisedAmongAHooksAncestors`

The first attempt at this run passed `-Filter` through `powershell -File` as one comma-joined string. That gave `No
matching test cases were run` with exit 0. It is my invocation error, not a test result, and I discarded it. Note G8-2
is about this pitfall.

## G4: PASS

- **Local:** `swift test --skip-build --scratch-path <build> --filter RecordCodingGoldenTests` gave exit 0 and
  `Test run with 4 tests in 0 suites passed`. The four tests are `recordIdentitiesMatchTheGoldenSamples`,
  `digestsMatchTheNISTVectors`, `millisecondDatesRoundTripTheGoldenSamples` and `theRecordEncoderWritesTheGoldenSample`.
  They also passed inside G3's Support batch (9/9).
- **Windows CI:** Support 9/9 passed.
- **macOS CI:** swift-testing 10/10 passed, including `portableDigestsEqualCryptoKit`.
- **No change since M5:** `git diff 0f51d89 f531b63 -- Sources/AgentHUDSupport Tests/AgentHUDSupportTests` is empty.

## G5: PASS (`--demo` snapshot N/A until M7)

- **Command:** `powershell -File scripts\windows\test-dotnet.ps1`, which runs `dotnet test windows\AgentHUD.sln -c
  Release` with warnings as errors and telemetry off, then `check-protocol.py`.
- **Result:** exit 0 in 7 s.
  - `已通过! - 失败: 0，通过: 11，已跳过: 0，总计: 11` (passed 11, failed 0, skipped 0).
  - `Protocol fixtures: 19 valid, 15 invalid, 0 failure(s).`
- **CI step 4:** the same output (11/11; 19 + 15, 0 failures).
- **Compared with round 1:** 7 → 11 C# tests, and 16 → 19 valid fixtures. The new `engine-state.later.json` is among
  them. The SKIPPED_TESTS.md line "C# … 11 pass, none skipped" matches.
- **The `--demo` snapshot smoke test:** N/A. It joins G5 in M7 (PROGRESS).

## G6: PASS

`python scripts\check-source-boundaries.py` → `Source boundaries and ignore rules passed.`, exit 0, 1.0 s. It also
passed in Windows CI step 3 and in the macOS `test` job.

## Other checks

- **D-006:** `git diff c258093 f531b63` is 0 bytes over the six `windowsReplaced` sources: `UnixSocket`,
  `UnixSocketListener`, `ChildProcess`, `FileChangeMonitor`, `InstanceLock`, and `CodexDesktopIPC`. Round 3's lock
  change is in `InstanceLock+Windows.swift` only.
- **Tracked build output:** `git ls-files` lists 0 paths under `bin/`, `obj/` or `TestResults/`.
- **The real profile:**

  | Check | Before | After |
  | --- | --- | --- |
  | `*.plist` directly in the real `%LOCALAPPDATA%` | 0 | 0 |
  | `%LOCALAPPDATA%\Debug-windows-x86_64` | absent | absent |
  | `agenthud-testprofile-*` in `%TEMP%` | 0 | 0 |

- **Client folders:** `.claude\settings.json` (16:26:26, before I started; that is the running client),
  `.codex\config.toml` and `hooks.json` (2026-09-29) are unchanged.
- **My own leftovers:** I removed my long-named 8.3 test folder.

## G7 (observations, for the reviewer)

- **D-044 is exercised for real on this machine.** Both the build folder and the source folder now sit behind two
  junctions (`%LOCALAPPDATA%\agenthud-dev` → `E:\agenthud-dev`, and `src` → the repository). The new junction test and
  the "another copy running" end-to-end test both pass here and on the runner, where no junction is involved.
- **The isolated real-engine test passes in both places.** The round-2 review blocker was
  `testARealRequestGoesThroughTheProtocolAndHooksChangeOnlyWithTheirSwitch`, which now has an allowlisted environment
  and a bounded hook wait. It took 13.2 s locally, 11.7 s in CI, and passed under the 8.3 `TEMP` as well.
- **The client configuration was untouched,** as far as the modification times show (see "The real profile").

## G8 (non-blocking notes)

1. **The real `%TEMP%` still grows.** It went from 1630 to 1712 top-level folders (+82) over G3 and the 8.3 run. This
   is the existing known issue for M9.
2. **`test.ps1 -Filter` from `powershell -File` cannot take several filters.** A comma list arrives as one string, and
   the run "passes" with `No matching test cases were run` and exit 0. PROGRESS already says to use `&`.
   - **Suggestion:** test.ps1 could fail when a filtered batch runs 0 tests. A silent pass is the risk.
3. **Windows PowerShell 5.1 expands an 8.3 `TEMP`.** `[IO.Path]::GetTempPath()` returns the long form, so test.ps1's
   own `agenthud-testprofile-*` folder is spelled in full, while the tests' children inherit the short `TEMP`. In CI,
   pwsh 7 keeps the short form. Both pass; this is noted only so that a future difference between local and CI is
   not a surprise.

## Skipped tests

| Kind | Count | Registered |
| --- | --- | --- |
| Excluded files (`windowsSkippedTests`) | 7 files | yes, SKIPPED_TESTS.md §1; the six replaced sources are unchanged from `c258093` (D-006) |
| Skip list (`skipped-tests.txt`) | 34 tests | yes, §2: none ran on Windows; all 34 passed on macOS (run 39164577291) |
| Runtime skips, local and CI | 4: `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe`, `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe`, `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe`, `SessionUsageProbeTests.testReportedSessionsUsageProbe` | yes, §3 |
| Conditional runtime skips (no `node.exe`/`git.exe`/8.3 names/PowerShell/Git Bash) | 0 triggered (all ran, including under the 8.3 `TEMP`) | yes, §3 |
| C# tests skipped | 0 of 11 | n/a |
| macOS skips | 8 (the same as in M5 and in M6 rounds 1–2) | upstream |

## Verdict summary

| Gate | Verdict |
| --- | --- |
| G1 | PASS (run 39164577291, attempt 1; 2087 XCTest / 8 skipped / 0 failures; 10 swift-testing; flaky test passed) |
| G2 | PASS (local 169 s and CI: the 6 baseline warnings only; .NET 0 warnings) |
| G3 | PASS (local and CI 1451 / 1447 / 4 skipped / 0 failed; 8.3 `TEMP`: 65/65; D-044 holds through the junction) |
| G4 | PASS (Windows local and CI, macOS CI) |
| G5 | PASS (11/11 C#, 19 + 15 fixtures, local and CI); `--demo` snapshot N/A until M7 |
| G6 | PASS |

TESTS: ALL_PASS
