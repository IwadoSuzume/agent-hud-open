# M3 test report, round 1

- Branch: `windows-port`. Head under test: `c8dca6e` ("AgentHUDCore and its tests on Windows"). Milestone start:
  `08bbc4a`. The diff is 125 files, +4141/−120.
- Run by: port-tester, 2026-10-17, Windows 11 Pro 10.0.26200. Only this report was written in the repository; nothing
  was committed or pushed.
- While the report was being written, the working tree began to hold the coordinator's uncommitted edits to
  `Sources/AgentHUDCore/System/InstanceLock.swift` (staged), `scripts/check-source-boundaries.py` and
  `scripts/windows/test.ps1`. They are **not** part of what this report gates. Every local result below was taken on
  the clean `c8dca6e` tree, before those edits appeared.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | PASS |
| G2 Windows build | **FAIL**: the CI run failed at Test; 9 new compiler warnings over the baseline |
| G3 Windows tests | **FAIL** in CI (no test ran); PASS locally (1294 pass, 0 failures) |
| G4 determinism | PASS (macOS CI and local Windows; Windows CI did not reach the tests) |
| G5 UI | N/A (M7+) |
| G6 boundaries | PASS |
| D-006 check | **FAIL**: `System/InstanceLock.swift` was edited |
| Excluded test files equal upstream | PASS |
| G7 security review | review gate; observations below |
| G8 docs | non-blocking inconsistencies (skip count, warning baseline, a D-006 claim) |

## BLOCKING findings

1. **Windows CI run 39003222984 failed (G2/G3).** Job `swift` (117310326380), step 11 "Test"
   (`scripts/windows/test.ps1`) ended `failure` after 20 s; steps 12 and later were skipped. Log of the job:

   ```
   Building for debugging...
   D:\a\agent-hud-open\agent-hud-open\.build\out\Products\Debug-windows-x86_64\AgentHUDOpen_AgentHUDCoreTests.bundle\Info.plist
   The process cannot access the file because it is being used by another process.
           0 file(s) copied.
   error: Touch D:\\a\\…\\Debug-windows-x86_64\\AgentHUDOpen_AgentHUDCoreTests.bundle failed with a nonzero exit code. Command line:
       C:\Windows\system32\cmd.exe /c copy /b D:\a\…\AgentHUDOpen_AgentHUDCoreTests.bundle +,,
   error: Build failed
   error: …\Debug-windows-x86_64\AgentHUDSupportTests-test-runner.exe doesn't exist in file system   (× 9, once per batch)
   Removed 0 test preference file(s) from C:\Users\runneradmin\AppData\Local
   ##[error]Process completed with exit code 1.
   ```

   No test ran in CI. I tried to reproduce it locally in the same order as CI: a fresh release build, then
   `swift build --build-tests` in a new scratch path (`<scratch>\m3_fresh`). Both passed (179 s, then 66 s). So the
   failure looks like a race or file lock in Swift Build's bundle "Touch" step on the runner, not a deterministic
   error. Separately, the script carried on with `--skip-build` after the build failed, so every batch then failed
   with "test-runner.exe doesn't exist". The coordinator reports that `test.ps1` now builds the tests first, with up
   to 3 attempts. That fix needs a new green Windows run.

2. **D-006 is not met.** `git diff 08bbc4a c8dca6e` over the six replaced files is not empty:

   ```
   Sources/AgentHUDCore/System/InstanceLock.swift | 2 +-
   -            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
   +            ?? UserHome.directory.appendingPathComponent("Library/Caches", isDirectory: true)
   ```

   The same one-line diff exists against upstream `c258093`. The other five files (`UnixSocket`, `UnixSocketListener`,
   `ChildProcess`, `FileChangeMonitor`, `CodexDesktopIPC`) are untouched. The cause is the new D-020 boundary rule.
   It rejects `homeDirectoryForCurrentUser` in every `Sources/AgentHUDCore/` file except `System/UserHome.swift` and
   `Platform/Windows/`, so the rule forced an edit to a file D-006 says is "not edited at all". There are two ways
   out:
   - Exempt the six D-006 files from the rule and restore `InstanceLock.swift` to upstream. The files are excluded
     from the Windows build anyway, so their home read only runs on macOS, where `UserHome.directory` **is**
     `homeDirectoryForCurrentUser`.
   - Or amend D-006 and D-020 to allow this one line.

   PROGRESS.md also says "the replaced macOS files restored to upstream (D-006)", which is not true at `c8dca6e`. The
   coordinator's working tree already has `InstanceLock.swift` staged and the boundary script modified, so a fix
   seems to be in progress; it is not gated here.

3. **New compiler warnings over the baseline (G2: "warnings must not increase").** PROGRESS.md's baseline lists only
   `wchar_t … broken by a context change` and `'strerror' is deprecated` in `MCP/MCPStdio.swift`. The release build of
   `c8dca6e` adds **9 distinct warnings**, identical in CI and locally:

   | File:line | Warning | Origin |
   | --- | --- | --- |
   | `Platform/Windows/SettingsFile.swift:11:59` | `'SettingsFile' inherits an unavailable 'Sendable' conformance; conforming here risks data races` | port code (strict concurrency) |
   | `Platform/Windows/PosixCompat.swift:36:12` | `'strdup' is deprecated` (use `_strdup`) | port code |
   | `Providers/Kit/Logs/LogFiles.swift:150:9` | `code after 'return' will never be executed` | port's `#if os(Windows) … return #endif` |
   | `Providers/Kit/Logs/LogFiles.swift:305:13` | `code after 'return' will never be executed` | same pattern |
   | `Hooks/Permission/PermissionHookClient.swift:38:17` | `'close' is deprecated` (use `_close`) | shared code, Windows CRT only |
   | `Providers/Kit/Zstandard/ZstandardReader.swift:46:9` | `'close' is deprecated` | shared code, Windows CRT only |
   | `Providers/Antigravity/AntigravityCLI.swift:18:44` | `'init(cString:)' is deprecated` | shared code, Windows only |
   | `Providers/Codex/CodexDesktopStream.swift:170:83` | `result of call to 'wait(until:)' is unused` | shared code against the Windows twin's API |
   | `Hooks/Permission/DeepSeekQuestions.swift:106:20` | `no 'async' operations occur within 'await' expression` | shared code against a Windows API |

   The first four are in code the port wrote: fix them. The `#if … return #endif` pattern can become
   `#if os(Windows) … #else … #endif`. For the others, either fix them inside `#if os(Windows)` or add them to the
   PROGRESS.md baseline with a reason.

## G1: PASS

`Source checks` run **39003224306**: workflow_dispatch, head `c8dca6e`, `completed` / `success`.

| Job | Runner | Conclusion | Steps |
| --- | --- | --- | --- |
| `test` (117310332157) | macos-15 | success | Check source boundaries success; Test success (04:37:05Z to 04:47:21Z) |
| `app` (117310332010) | macos-15 | success | Build application success; Verify local signature and resources success |
| `macos` (117312249301) | ubuntu-latest | success | Tests and application passed success |

Totals from the `test` job log, compared with M2:

| | M2 (`887c949`) | M3 (`c8dca6e`) |
| --- | --- | --- |
| XCTest | 2086 executed, 8 skipped, 0 failures | **2086 executed, 8 skipped, 0 failures** (399.97 s) |
| swift-testing | 10 passed | **10 passed** |

The totals are unchanged. `portableDigestsEqualCryptoKit()` passed after 0.468 s, and `digestsMatchTheNISTVectors`,
`recordIdentitiesMatchTheGoldenSamples`, `millisecondDatesRoundTripTheGoldenSamples` and
`theRecordEncoderWritesTheGoldenSample` all passed. `Source boundaries and ignore rules passed.` on macOS: the D-020
rule runs there too.

## G2: FAIL

**CI.** `Windows port` run **39003222984**: push, head `c8dca6e`, `completed` / **`failure`**. Job `swift`
(117310326380), windows-latest.

| # | Step | Conclusion |
| --- | --- | --- |
| 1–4 | Set up, checkout, Check source boundaries, System SQLite version (`winsqlite3 3.51.1`) | success |
| 5–6 | Cache the Swift installer (hit) / Download (skipped by design) | success / skipped |
| 7–8 | Verify and install Swift / Toolchain (`Swift version 6.4.1 (swift-6.4.1-RELEASE)`) | success |
| 9 | Cache the Swift build (`Cache not found` for `swift-build-6.4.1-0b65971d…`, the new key without the commit) | success |
| 10 | **Build (release)** | **success**, `Build complete! (527.63 secs)` |
| 11 | **Test** (`scripts/windows/test.ps1`) | **failure** (BLOCKING 1) |
| 12, 22, 23 | Compile a smoke package, Post cache steps | skipped |
| 24–25 | Post checkout, Complete job | success |

**Local.** `swift build -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build`, run from
`%LOCALAPPDATA%\agenthud-dev\src` at `c8dca6e` with the PROGRESS.md environment: exit 0,
`Build complete! (176.51 secs)`. It shows the same 9 extra warnings as CI plus the baseline `strerror` (BLOCKING 3).
A fresh-scratch reproduction (release, then `--build-tests`) also exited 0.

## G3: FAIL (CI) / PASS (local)

- **CI:** failed before any test ran (BLOCKING 1).
- **Local:** `scripts\windows\test.ps1 -ScratchPath %LOCALAPPDATA%\agenthud-dev\build -Log <scratch>\m3_test.log`,
  run from PowerShell with the PROGRESS.md Swift environment at `c8dca6e`. Exit 0 in 149 s; the first batch's build
  took 8.91 s.
  - Support (swift-testing): `Test run with 9 tests in 0 suites passed`.
  - Core, 9 batches (`[AB]`, `C[a-n]`, `C[o-z]`, `[D-H]`, `[I-O]`, `P[a-h]`, `P[i-z]`, `[Q-T]`, `[U-Z]`): 114 + 114 +
    127 + 166 + 187 + 221 + 42 + 240 + 92 = **1303 executed: 1294 passed, 9 skipped, 0 failures**. Every
    "Selected tests" suite passed.
  - These totals match SKIPPED_TESTS.md and PROGRESS ("1294 pass, 9 runtime skips").
  - Windows counterparts all ran and passed: NamedPipesTests 9, ChildProcessWindowsTests 13,
    InstanceLockWindowsTests 5, FileChangeMonitorWindowsTests 5, FileSharingTests 3, LedgerFileStoreWindowsTests 1,
    LogFilesWindowsTests 2, SessionProjectWindowsTests 5, WindowsFoldersTests 6, WindowsProcessesTests 6. The first
    three counts match those quoted in SKIPPED_TESTS.md §1.
- **Skips: every one is registered.**
  - The 9 runtime skips are exactly the §3 entries: the four `…Probe` tests, the two `DeepSeekDesktopTests`, the three
    `DeepSeekProviderTests` compressed-log tests and `SessionUsageProbeTests`.
  - **None** of the 34 tests in `skipped-tests.txt` appears in the log, so `--skip` took effect.
  - All 34 names exist in `Tests/` at `c8dca6e`, so no pattern is stale.
  - `skipped-tests.txt` against SKIPPED_TESTS.md §2: the 15 tests §2 names in full and the per-class counts it gives
    with ×N (AntigravityCLI 2, ClaudeCodeProvider 5, ClaudeEngine 6, CodexProvider 4, MCPClient 2) **match the list
    exactly**: 34 entries, none missing, none extra.
  - The 10 excluded files are listed in §1.
- **D-021 (real `%LOCALAPPDATA%`):**
  - Before the run, the folder's top level had 0 `*.plist`.
  - During the run the Core tests wrote 6 test-suite preference files, which the script's cleanup reported:
    `Removed 6 test preference file(s) from C:\Users\suzume\AppData\Local`.
  - Afterwards there were **0 `*.plist` and no new top-level entries**, so nothing was left behind.
  - The D-021 text at `c8dca6e` now records that swift-corelibs ignores the redirected variables and that the gate
    cleans up. That is consistent with this measurement.

## G4: PASS

- macOS (CI): the 4 golden tests and `portableDigestsEqualCryptoKit` passed (G1).
- Windows (local): the 4 golden tests passed in the Support batch.
- Windows CI did not reach its tests in this run. Re-confirm there with the next green run.
- The fixture changed only in its `about` text (`make-record-coding-golden.py` now cites FIPS 180-2 and RFC 6455);
  the values are unchanged.

## G6: PASS

- `python scripts\check-source-boundaries.py` at `c8dca6e`: `Source boundaries and ignore rules passed.`, exit 0. It
  also passed in both CI runs.
- With the new D-020 rule, the only remaining `homeDirectoryForCurrentUser` uses in Core are `System/UserHome.swift`
  and `Platform/Windows/WindowsFolders.swift`, the two exempt places.

## Excluded test files: PASS

`git diff --numstat c258093 c8dca6e` is empty for all 10 files in `windowsSkippedTests`. Each file exists unchanged:
`System/UnixSocketListenerTests`, `System/ChildProcessTests`, `System/InstanceLockTests`, `MCP/MCPAppChannelTests`,
`Hooks/Permission/PermissionHookTests`, `Hooks/Permission/DeepSeekQuestionObserverTests`, and
`Providers/Codex/CodexDaemonOriginTransportTests`, `CodexDesktopTestServer`, `CodexDesktopPermissionsTests`,
`CodexDesktopStreamTests`.

## G7 (observations, for the reviewer)

- `scripts/windows/remove-test-preferences.ps1` deletes files in the user's **real** `%LOCALAPPDATA%`. It is limited
  to `*.plist` names made of a test-suite prefix and a UUID (or `DemoClockTests.plist`), created since the run
  started. That is narrow, and D-018 says the application never writes there. Its pattern
  `AgentHUD[A-Za-z]*\.<UUID>…` would also match an `AgentHUD…`-named domain from another tool, but only one created
  during the run.
- `test.ps1` restores `APPDATA` and `LOCALAPPDATA` in `finally` and removes its GUID-named temporary profile.

## G8: consistent apart from these notes

- D-028 (Foundation workarounds) matches the `LogFiles`, `SessionProject` and `FileSharingTests` changes. D-029 matches
  `test.ps1` (Support plus nine Core batches, `--skip` list, cleanup) and `windows.yml` ("Test: run:
  scripts/windows/test.ps1"). D-030 matches PORTING_PLAN's new note on §1–§4. D-031 matches `PortableDigest.swift`
  (`public` → `package`).
- PROGRESS G3 names `scripts\windows\test.ps1 -ScratchPath $build -Log …`, which is what this gate ran.

Non-blocking notes:

1. **Skip count:** SKIPPED_TESTS.md ("State at M3") and the PROGRESS M3 row both say "**36** listed skips". The list
   and §2 hold **34**.
2. **Warning baseline:** PROGRESS.md has not been updated for the warnings in BLOCKING 3.
3. **D-006 claim:** PROGRESS step 2 (removed in this commit) and D-006 say the replaced files are untouched;
   `InstanceLock.swift` is not (BLOCKING 2).
4. The M2 approval and run ids are in PROGRESS. The M3 row should get 39003224306 and the next green Windows run.

## Skipped tests

| Kind | Count | Registered |
| --- | --- | --- |
| Excluded files (`windowsSkippedTests`) | 10 files | yes, §1 |
| Skip list (`skipped-tests.txt`, `--skip`) | 34 tests | yes, §2 (exact match) |
| Runtime skips (`XCTSkip`) | 9 tests | yes, §3 |
| Support `portableDigestsEqualCryptoKit` (compiled only with CryptoKit) | 1 | yes |

TESTS: FAILURES
