# M3 test report, round 3

- Branch: `windows-port`. Head under test: `da470d9` ("Windows port M3 round 3: runner-account test fixes, test.ps1
  filter and retry"). M3 range: `08bbc4a...da470d9`. The round-3 fixes are `dd38fc8...da470d9`: 8 files, +263/−27.
  210 of the added lines are the round-2 report. The code changes are 3 test files and `scripts/windows/test.ps1`.
- Run by: port-tester, 2026-10-17 (local times below are the machine's), Windows 11 Pro 10.0.26200.
- The working tree was clean at `da470d9` before and after the gates. Only this report was written in the repository.
  Nothing was committed or pushed.
- **Concurrent activity.** The coordinator's worktree ran its own `swift build -c release --scratch-path
  %LOCALAPPDATA%\agenthud-dev\wtrel` from 07:05:13, overlapping my G2 and G3. Its scratch path is not mine. No "being
  used by another process" flake happened in any of my runs.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | PASS |
| G2 Windows build | PASS: CI green; local release build green; library warnings equal the PROGRESS baseline exactly |
| G3 Windows tests | PASS: CI 1301 pass / 9 skip / 0 fail; local the same |
| G4 determinism | PASS (macOS CI, Windows CI, Windows local) |
| G5 UI | N/A (M7+) |
| G6 boundaries | PASS |
| D-006: the six replaced files equal upstream `c258093` | PASS |
| Excluded test files equal upstream `c258093` | PASS |
| D-021: stray `%LOCALAPPDATA%\Debug-windows-x86_64` | not created by the main-tree G3 (absent before and after) |
| G7 security review | review gate; observations below |
| G8 docs | PASS, with non-blocking notes |

## BLOCKING findings

None.

## G1: PASS

`Source checks` run **39006577913**: workflow_dispatch on `windows-port`, head `da470d9`, `completed` / `success`.

| Job | Runner | Conclusion | Steps |
| --- | --- | --- | --- |
| `test` (117320169749) | macos-15 | success | Check source boundaries: success. Test: success (05:31:43Z to 05:39:45Z). |
| `app` (117320169818) | macos-15 | success | Build application: success. Verify local signature and resources: success. |
| `macos` (117321627113) | ubuntu-latest | success | Tests and application passed: success. |

Totals from the `test` log:

- XCTest: `Executed 2086 tests, with 8 tests skipped and 0 failures (0 unexpected) in 339.526` s. This equals M2 and
  M3 rounds 1 and 2 (2086 / 8 / 0).
- swift-testing: `✔ Test run with 10 tests passed after 0.893 seconds`. This includes `portableDigestsEqualCryptoKit()
  passed after 0.444 seconds` and the golden tests.
- `Source boundaries and ignore rules passed.`

## G2: PASS

**CI.** `Windows port` run **39006576859**: push, head `da470d9`, `completed` / `success`. Job `swift`
(117320164228, windows-latest).

| # | Step | Conclusion |
| --- | --- | --- |
| 1–4 | Set up, checkout, Check source boundaries, System SQLite version | success |
| 5–6 | Cache the Swift installer / Download (skipped by design) | success / skipped |
| 7–8 | Verify and install Swift / Toolchain | success |
| 9 | Cache the Swift build | success |
| 10 | **Build (release)** (`swift build -c release`, 05:34:12Z to 05:43:04Z) | **success** |
| 11 | **Test** (`scripts/windows/test.ps1`, 05:43:04Z to 05:49:04Z) | **success** |
| 12 | Compile a smoke package | success |
| 22–25 | Post steps, Complete job | success |

**Local.** I ran `swift build -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build` from the junction
`%LOCALAPPDATA%\agenthud-dev\src`, with the PROGRESS.md Swift environment, at `da470d9`. Result: exit 0, `Build
complete! (163.60 secs)` (167 s wall-clock).

**Library warnings: exactly the PROGRESS baseline (D-033), locally and in CI's Build step.** Each warning appears once.

| Warning | Where | In baseline |
| --- | --- | --- |
| `'strerror' is deprecated` | `Sources/AgentHUDCore/MCP/MCPStdio.swift:54` | yes |
| `'close' is deprecated` | `Hooks/Permission/PermissionHookClient.swift:38`, `Providers/Kit/Zstandard/ZstandardReader.swift:46` | yes |
| `'init(cString:)' is deprecated` | `Providers/Antigravity/AntigravityCLI.swift:18` | yes |
| `result of call to 'wait(until:)' is unused` | `Providers/Codex/CodexDesktopStream.swift:170` | yes |
| `no 'async' operations occur within 'await' expression` | `Hooks/Permission/DeepSeekQuestions.swift:106` | yes |
| `WinSDK.swiftmodule … 'wchar_t' broken by a context change` | toolchain; CI only (5×), not in the local build | yes |

**No new warning.**

The test build (G3, not part of G2 since D-033 was rescoped) warns on the same upstream test lines locally and in CI:

- `MCPStdioTests.swift`: `close`, `dup`, `dup2` at lines 23, 25, 26, 66, 80, 81, 84, 85, 87, 101, 113, 114, 187, 190.
  The port's 11 added lines in this file are not among them.
- `PanelToolsSpanTests.swift:91`, `CollectionSignalTests.swift:331`, `UsageRefreshTests.swift:73`.
- `DeepSeekProviderTests.swift:525`.

The four files other than `MCPStdioTests.swift` are unchanged from `c258093`. **`WindowsFoldersTests.swift` no longer
warns** (0 warnings locally and in CI; round 2 had 4).

## G3: PASS

**CI (step 11 of run 39006576859).**

- The build-first step took 1 attempt: `Build complete! (199.82 secs)`, with no "hit a file in use" line.
- Support: `Test run with 9 tests in 0 suites passed after 0.696 seconds`.
- Core, 9 batches: 114 + 114 + 127 + 166 + 187 + 221 + 49 + 240 + 92 = **1310 executed: 1301 passed, 9 skipped, 0
  failed**.
- `Removed 6 test preference file(s) from C:\Users\runneradmin\AppData\Local`.
- Round 2's four runner-only failures now pass on the runner: `NamedPipesTests.testThePipeLetsOnlyThisUserIn`,
  `…testThePipeKeyIsMadeOnceAndOnlyThisUserCanReadIt` (the `LA` alias), and
  `SessionProjectWindowsTests.testLinkedWorktreesAndTheirSubdirectoriesBelongToTheMainRepository`,
  `…testAJunctionToAWorktreeUsesTheSameRepository` (the `RUNNER~1` path).

**Local.**

- Command: `scripts\windows\test.ps1 -ScratchPath %LOCALAPPDATA%\agenthud-dev\build -Log %TEMP%\g3.log`.
- Setup: Windows PowerShell 5.1, the PROGRESS.md environment, the temporary profile
  `%LOCALAPPDATA%\agenthud-dev\testprofile` (APPDATA/LOCALAPPDATA redirected), through the junction, at `da470d9`.
- Result: exit 0 in **194 s** (07:08:08 to 07:11:23).
- The build-first step took 1 attempt: `Build complete! (54.24 secs)`.
- Support: `Test run with 9 tests in 0 suites passed after 0.382 seconds`.
- Core, 9 batches: 114 + 114 + 127 + 166 + 187 + 221 + 49 + 240 + 92 = **1310 executed: 1301 passed, 9 skipped, 0
  failed**. The set of 1310 test cases is identical to CI's (set comparison: no local-only and no CI-only cases).
- `Removed 6 test preference file(s) from C:\Users\suzume\AppData\Local`.

**The `-Filter` fix.** `& scripts\windows\test.ps1 -ScratchPath $build -Filter 'NamedPipesTests',
'SessionProjectWindowsTests'` (same environment) ran **one batch**: `Executed 14 tests, with 0 failures` (9 + 5).
Exit 0 in 25 s.

**Skips: all registered.**

- **Runtime skips, 9 (identical in CI and locally), exactly SKIPPED_TESTS.md §3:**
  - `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe`
  - `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe`
  - `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe`
  - `SessionUsageProbeTests.testReportedSessionsUsageProbe`
  - `DeepSeekDesktopTests.testWithoutACLIInstallTheDesktopAppSuppliesThePackageAndItsRuntime`
  - `DeepSeekDesktopTests.testTheBalanceHelperReadsTheCredentialThroughTheDesktopApp`
  - the three `DeepSeekProviderTests` compressed-log tests: `testAGrownCompressedLogIsDecodedFromItsLastCompleteFrame`,
    `testConcatenatedZstandardFramesAndTornFinalFrameMatchPlaintext`,
    `testLargeCompressedLogDrainsPipeAndSkipsPackedConversationContent`
- **Skip list:** `scripts/windows/skipped-tests.txt` is unchanged since round 1. It has 34 entries, which matches §2.
  None of the 34 names appears in the local or the CI log.
- **Excluded files:** the 10 in `windowsSkippedTests` are §1, and all are unchanged from `c258093`.

**D-021, the real `%LOCALAPPDATA%` (`C:\Users\suzume\AppData\Local`):**

| When | `Debug-windows-x86_64` | `*.plist` |
| --- | --- | --- |
| before G2/G3 (07:04:38) | **absent** | 0 |
| after G3 (07:11) | **absent** | 0 |
| after the `-Filter` run | **absent** | 0 |

- The only entries created or written in that folder during the run were `agenthud-dev` (my scratch path and
  testprofile) and `Temp`.
- So the main-tree G3 does not create the stray folder. This agrees with D-021's note:
  - the only Core test that opens a `URLSession` (`DeepSeekQuestionObserverTests.testCancellingIdleWebSocketClosesTheConnectionWithoutAHostFrame`)
    is in an excluded file;
  - `ProviderHTTP` uses WinHTTP on Windows.

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

The fixture's data is unchanged since `port-M2-approved`. Only its `about` text changed, in `c8dca6e`.

## G6: PASS

- `python scripts\check-source-boundaries.py` at `da470d9`: `Source boundaries and ignore rules passed.`, exit 0,
  0.9 s.
- It also passed in both CI runs (the macOS `test` job, and step 3 of the Windows job).

## D-006 and the excluded tests: PASS

- `git diff c258093 da470d9 -- Sources/AgentHUDCore/<file>` is **empty** (0 bytes) for all six files in
  `windowsReplaced`. All six still exist.
  - `System/UnixSocket.swift`
  - `System/UnixSocketListener.swift`
  - `System/ChildProcess.swift`
  - `System/FileChangeMonitor.swift`
  - `System/InstanceLock.swift`
  - `Providers/Codex/CodexDesktopIPC.swift`
- All 10 files in `windowsSkippedTests` diff empty against `c258093`.

## G7 (observations, for the reviewer)

- `NamedPipesTests.assertOwnerOnly` still requires a protected DACL (`D:P`) with exactly one ACE. It now accepts the
  user's SID or the SDDL alias Windows writes for it, which the test derives by round-tripping `O:<SID>` through
  `ConvertStringSecurityDescriptorToSecurityDescriptorW` and back.
- It now requires that ACE's trustee to be the **last field** (`hasSuffix(";;;<name>)")`). Before, any occurrence of
  the SID anywhere was enough, so the check is now stricter.
- `test.ps1` retries only when a line matched `being used by another process`. A compile error now stops after one
  attempt, and no batch runs without a build.

## G8: PASS, with non-blocking notes

- PROGRESS "Gates — exact commands" matches what exists:
  - `scripts/windows/test.ps1` takes `-ScratchPath`, `-Log` and `-Filter`;
  - `scripts/windows/remove-test-preferences.ps1` exists;
  - `scripts/check-source-boundaries.py` exists;
  - `.github/workflows/ci.yml` and `windows.yml` exist, and `windows.yml` calls `swift build -c release` and
    `scripts/windows/test.ps1`;
  - `RecordCodingGoldenTests` exists.
- D-032 (retry only on a file in use) matches `test.ps1`. D-033 (library build only) matches the measurements above.
- SKIPPED_TESTS.md "State at M3" now says **1301 pass, 9 runtime skips, 34 listed skips, 10 excluded files, 0
  failures**, which equals both runs. The PROGRESS milestone row records round 2's results and fixes.

Non-blocking notes:

1. **PROGRESS "Next steps" item 1** still reads "M3 review round 2 on `08bbc4a...HEAD` (the round-1 fixes)". It should
   name round 3.
2. **D-021's new sentence** says the idle WebSocket test "is skipped on Windows". It is in an **excluded file**
   (`DeepSeekQuestionObserverTests.swift`, SKIPPED_TESTS §1), not in the skip list. "excluded" would be exact.
3. **PORTING_PLAN.md line 69** says "tests keep their suites in the temporary profile (D-021)". D-021's own
   measurement is that the suites land in the real `%LOCALAPPDATA%` and are removed afterwards by
   `remove-test-preferences.ps1`. This wording predates round 3.

## Skipped tests

| Kind | Count | Registered |
| --- | --- | --- |
| Excluded files (`windowsSkippedTests`) | 10 files | yes, §1 |
| Skip list (`skipped-tests.txt`) | 34 tests | yes, §2 (exact match, none ran) |
| Runtime skips (`XCTSkip`) | 9 tests (the same in CI and locally) | yes, §3 |
| Support `portableDigestsEqualCryptoKit` (compiled only with CryptoKit) | 1 | yes (AgentHUDSupportTests section) |

TESTS: ALL_PASS
