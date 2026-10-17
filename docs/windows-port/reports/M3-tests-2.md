# M3 test report, round 2

- Branch: `windows-port`. Head under test: `dd38fc8` ("M3 round 2: build-first tests, D-006 restored, review
  fixes"). M3 range: `08bbc4a...dd38fc8`. The round-2 fixes are `c8dca6e...dd38fc8`: 15 files, +445/−31.
- Run by: port-tester, 2026-10-17, Windows 11 Pro 10.0.26200. The working tree was clean at `dd38fc8` when the gates
  started. Only this report was written in the repository; nothing was committed or pushed.
- **Concurrent activity.** While the local G3 ran (01:10–01:16 local), the coordinator's worktree build and tests were
  also running (`%LOCALAPPDATA%\agenthud-dev\wtbuild\debug` written 01:14:04; `testprofile-wt` 01:16:12;
  `swift-test` started 01:16:13). See the G3 note on the real `%LOCALAPPDATA%`.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | PASS |
| G2 Windows build | PASS: release build green in CI and locally; library warnings equal the PROGRESS baseline exactly. The workflow run is red because of its Test step (G3). |
| G3 Windows tests | **FAIL in CI** (4 tests fail on the runner); PASS locally (1301 pass, 9 runtime skips, 0 failures) |
| G4 determinism | PASS (macOS CI; Windows locally and in CI) |
| G5 UI | N/A (M7+) |
| G6 boundaries | PASS |
| D-006: six replaced files equal upstream `c258093` | PASS |
| Excluded test files equal upstream `c258093` | PASS |
| G7 security review | review gate; observations below |
| G8 docs | PASS with non-blocking notes |

## BLOCKING findings

**1. Windows CI run 39005191736: 4 Windows-only tests fail on the GitHub runner (G3).** Job `swift` (117316102181),
step 11 "Test" failed. The build-first retry of D-032 worked:

```
The process cannot access the file because it is being used by another process.
error: Touch D:\\a\\…\\Debug-windows-x86_64\\AgentHUDOpen_AgentHUDCoreTests.bundle failed with a nonzero exit code.
error: Build failed
swift build --build-tests failed with status 1 (attempt 1 of 3)
Build complete! (113.21 secs)
```

The batches then ran: XCTest **1297 passed, 9 skipped, 4 failed**, and Support 9/9 passed. Two independent causes,
both from how the runner's account differs from a normal user:

**(a) `NamedPipesTests.testThePipeLetsOnlyThisUserIn` (line 119) and
`NamedPipesTests.testThePipeKeyIsMadeOnceAndOnlyThisUserCanReadIt` (line 140).**

```
NamedPipesTests.swift:119: error: … XCTAssertTrue failed - D:P(A;;FA;;;LA)
NamedPipesTests.swift:140: error: … XCTAssertTrue failed - D:P(A;;FA;;;LA)
```

- The runner's account (`runneradmin`) is the built-in Administrator (RID 500). SDDL writes that SID as the
  well-known alias `LA` instead of `S-1-5-21-…-500`, so `assertOwnerOnly`, which looks for the user's SID string, fails.
- The DACL itself is what D-010 asks for: protected (`P`), a single ACE, full access, for the current user only.
  This is a **test** defect, not a security defect.
- Fix: compare the ACE's SID with `EqualSid` (or `ConvertStringSidToSidW` on the trustee), or map the well-known
  aliases before comparing.

**(b) `SessionProjectWindowsTests.testLinkedWorktreesAndTheirSubdirectoriesBelongToTheMainRepository` (line 56, 4
assertions) and `SessionProjectWindowsTests.testAJunctionToAWorktreeUsesTheSameRepository` (line 71).**

```
XCTAssertEqual failed: ("Optional("c:/users/runneradmin/appdata/local/temp/hud project 项目 01599f66-…/main")")
 is not equal to ("Optional("c:/users/runner~1/appdata/local/temp/hud project 项目 01599f66-…/main")")
 - C:/Users/RUNNER~1/AppData/Local/Temp/HUD Project 项目 01599F66-…/main
```

- On the runner `%TEMP%` is the **8.3 short** spelling (`C:\Users\RUNNER~1\…`). `SessionProject` returns the
  repository in its long form (`runneradmin`, from Git or the final path). The test expects the short spelling it
  started from, lower-cased. At line 73–74, `WindowsPaths.finalPath(fixture.main.path)` did not give the long form
  either.
- This machine has no short-name difference (`C:\Users\suzume`), so it passes locally. Real users can hit the same
  thing: any profile folder longer than 8 characters or containing spaces has an 8.3 alias, and clients may record
  either spelling.
- Decide the canonical form (the long name, `GetLongPathNameW` / `GetFinalPathNameByHandleW`), make the test expect
  it, and check that every path SessionProject and D-023's comparisons see is normalised the same way.

Neither failure appears locally. The gate needs a green Windows run.

## G1: PASS

`Source checks` run **39005199779**: workflow_dispatch, head `dd38fc8`, `completed` / `success`.

| Job | Runner | Conclusion | Steps |
| --- | --- | --- | --- |
| `test` (117316127726) | macos-15 | success | Check source boundaries success; Test success (05:09:16Z to 05:18:16Z) |
| `app` (117316127930) | macos-15 | success | Build application success; Verify local signature and resources success |
| `macos` (117317823690) | ubuntu-latest | success | Tests and application passed success |

Totals from the `test` log:

- XCTest: `Executed 2086 tests, with 8 tests skipped and 0 failures` (361.0 s). Unchanged from M2 and M3 round 1
  (2086 / 8 / 0).
- swift-testing: `✔ Test run with 10 tests passed`, unchanged. It includes `✔ portableDigestsEqualCryptoKit() passed
  after 0.523 seconds` and the four golden tests.
- `Source boundaries and ignore rules passed.` This is with the new `windowsReplaced` exemption.

## G2: PASS (build)

**CI.** `Windows port` run **39005191736**: push, head `dd38fc8`, conclusion `failure` (from step 11).

| # | Step | Conclusion |
| --- | --- | --- |
| 1–4 | Set up, checkout, Check source boundaries, System SQLite version (`winsqlite3 3.51.1`) | success |
| 5–6 | Cache the Swift installer (restored) / Download (skipped by design) | success / skipped |
| 7–8 | Verify and install Swift / Toolchain (`Swift version 6.4.1 (swift-6.4.1-RELEASE)`) | success |
| 9 | Cache the Swift build (`Cache not found` for `swift-build-6.4.1-0b65971d…`) | success |
| 10 | **Build (release)** | **success** (05:11:24Z to 05:16:30Z) |
| 11 | Test (`scripts/windows/test.ps1`) | **failure** (BLOCKING 1) |
| 12, 22, 23 | Smoke package, post cache steps | skipped |

**Local.** `swift build -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build`, run from
`%LOCALAPPDATA%\agenthud-dev\src` at `dd38fc8`: exit 0, `Build complete! (175.19 secs)`.

**Warnings: exactly the PROGRESS baseline (D-033), locally and in CI.**

| Warning | Where | In baseline |
| --- | --- | --- |
| `'strerror' is deprecated` | `MCP/MCPStdio.swift:54` | yes |
| `'close' is deprecated` | `Hooks/Permission/PermissionHookClient.swift:38`, `Providers/Kit/Zstandard/ZstandardReader.swift:46` | yes |
| `'init(cString:)' is deprecated` | `Providers/Antigravity/AntigravityCLI.swift:18` | yes |
| `result of call to 'wait(until:)' is unused` | `Providers/Codex/CodexDesktopStream.swift:170` | yes |
| `no 'async' operations occur within 'await' expression` | `Hooks/Permission/DeepSeekQuestions.swift:106` | yes |
| `WinSDK … 'wchar_t' broken by a context change` | toolchain, test and smoke compiles (CI) | yes |

The four port-code warnings from round 1 are gone: `SettingsFile` Sendable, `PosixCompat` `strdup`, and the two
`LogFiles` "code after 'return'".

## G3: FAIL (CI) / PASS (local)

- **CI:** BLOCKING 1.
- **Local:** `scripts\windows\test.ps1 -ScratchPath %LOCALAPPDATA%\agenthud-dev\build -Log <scratch>\m3r2_test.log`,
  run from PowerShell with the PROGRESS.md Swift environment through the junction at `dd38fc8`. Exit 0 in 156 s; the
  build-first step `Build complete! (14.93 secs)` succeeded on attempt 1.
  - Support: `Test run with 9 tests in 0 suites passed`.
  - Core, 9 batches: 114 + 114 + 127 + 166 + 187 + 221 + 49 + 240 + 92 = **1310 executed: 1301 passed, 9 skipped, 0
    failed**.
  - That is +7 over round 1, from the new `PlatformGapsTests`, all 7 of which passed.
- **Skips: all registered.**
  - The 9 runtime skips are exactly SKIPPED_TESTS.md §3.
  - `skipped-tests.txt` is unchanged since round 1 (34 entries, an exact match with §2, checked in round 1). None of
    the 34 ran.
  - The 10 excluded files are in §1.
- **Real `%LOCALAPPDATA%` after the run:**
  - **0 `*.plist`.** The script's cleanup reported `Removed 6 test preference file(s)`.
  - **One new, empty directory** appeared: `%LOCALAPPDATA%\Debug-windows-x86_64` (created 01:14:06, no content).
    `Debug-windows-x86_64` is the name of the test bundle (`Debug-windows-x86_64.xctest`).
  - It was not there before this run, nor before rounds 1 and 2 of M3 or M2 (all snapshots: 0 matches).
  - It appeared while my `C[o-z]` batch and the coordinator's worktree tests were both running, so I cannot tell which
    run made it. Most likely swift-corelibs made a per-bundle folder through the known folder, as with the plists
    (D-021).
  - **Not removed** (not mine to delete). Find out which test or run creates it and either clean it up the way
    `remove-test-preferences.ps1` does or prevent it. Record the result in D-021.

## G4: PASS

- macOS (CI): the golden tests and `portableDigestsEqualCryptoKit` pass (G1).
- Windows: the golden tests pass locally and in CI. The Support batch ran in CI after the retried build:
  `Test run with 9 tests in 0 suites passed`.

## G6: PASS

- `python scripts\check-source-boundaries.py` at `dd38fc8`: `Source boundaries and ignore rules passed.`, exit 0. It
  also passed in both CI runs.
- The D-020 rule now skips the files `Package.swift` lists in `windowsReplaced`. The list is parsed from the manifest,
  so there is one source of truth.

## D-006 and the excluded tests: PASS

- `git diff --stat c258093 dd38fc8` over `System/UnixSocket.swift`, `UnixSocketListener.swift`, `ChildProcess.swift`,
  `FileChangeMonitor.swift`, `InstanceLock.swift` and `Providers/Codex/CodexDesktopIPC.swift` is **empty**.
  `InstanceLock.swift` is back to upstream.
- All 10 files in `windowsSkippedTests` are unchanged from `c258093`.

## G7 (observations, for the reviewer)

- The pipe DACL on the runner is `D:P(A;;FA;;;LA)`: protected and single-trustee, as D-010 requires (BLOCKING 1a is a
  test-only issue).
- `windows.yml` is unchanged since round 1. The test step still calls `scripts/windows/test.ps1`.
- D-032's retry rebuilds only when `swift build --build-tests` fails, and no batch runs without a successful build.
  If all 3 attempts fail, the script keeps the build's status.

## G8: PASS with notes

- D-032 matches `test.ps1`: build first, 3 attempts, `--skip-build` batches. D-033 matches the PROGRESS baseline and
  the warnings measured.
- D-006 is restored, and the boundary rule follows `windowsReplaced`.
- SKIPPED_TESTS.md now says "34 listed skips", which matches.
- PROGRESS records round 1's results and fixes.

Non-blocking notes:

1. **SKIPPED_TESTS.md "State at M3"** still says **1294 pass**. With `PlatformGapsTests` it is now **1301**.
2. **D-033 says "code the port wrote warns nothing"**, but the **test** build in CI shows warnings in port-written test
   code: `WindowsSupport/WindowsFoldersTests.swift:32, 36, 46, 51`, "no calls to throwing functions occur within
   'try'". The test build also warns on upstream test lines that only Windows compiles this way: `MCPStdioTests`
   (`close`, `dup`, `dup2`), "mutated after capture by sendable closure" in `PanelToolsSpanTests:91`,
   `CollectionSignalTests:331` and `UsageRefreshTests:73`, and `DeepSeekProviderTests:525`. Either fix the
   `WindowsFoldersTests` ones and baseline the upstream ones, or say in D-033 that the baseline covers the library
   build only.
3. The new empty folder in the real `%LOCALAPPDATA%`, `Debug-windows-x86_64` (see G3).

## Skipped tests

| Kind | Count | Registered |
| --- | --- | --- |
| Excluded files (`windowsSkippedTests`) | 10 files | yes, §1 |
| Skip list (`skipped-tests.txt`) | 34 tests | yes, §2 (exact match) |
| Runtime skips (`XCTSkip`) | 9 tests | yes, §3 |
| Support `portableDigestsEqualCryptoKit` (compiled only with CryptoKit) | 1 | yes |

TESTS: FAILURES
