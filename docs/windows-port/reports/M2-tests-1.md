# M2 test report, round 1

- Branch: `windows-port`. Head under test: `887c949` ("keep the Info.plist Swift Build writes on Windows out of the
  tree"), on top of `f1ec309` ("AgentHUDSupport on Windows"). Milestone start: `ffc8dba`. The working tree was clean
  when the gates ran.
- Diff `ffc8dba..887c949`, 16 files:
  - Support: `PortableDigest.swift` and `CryptoKitShim.swift` (new), and a guarded import in `RecordCoding.swift`.
  - Core: guarded CryptoKit imports in 3 files.
  - Tests: the golden fixture and `RecordCodingGoldenTests.swift`.
  - Generator: `scripts/make-record-coding-golden.py`.
  - Other: `windows.yml`, `Package.swift`, `.gitignore` (`/Info.plist`) and docs (PROGRESS, DECISIONS, SKIPPED_TESTS,
    reports/M1-tests-1.md).
- Run by: port-tester, 2026-10-16/17, Windows 11 Pro 10.0.26200. Only this report was written in the repository;
  nothing was committed or pushed. One side effect is listed under G2 (an ignored `Info.plist`).

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | PASS |
| G2 Windows build | PASS (CI and local) |
| G3 Windows tests | PASS (Support 9/9; D-021 check clean for this run; see the warning below) |
| G4 determinism | PASS (golden tests on both platforms; fixture reproduced from the generator) |
| G5 UI | N/A (M7+) |
| G6 boundaries | PASS |
| G7 security review | review gate; observations below |
| G8 docs | PASS (non-blocking notes) |

### Package.swift (D-027)

`git diff ffc8dba 887c949 -- Package.swift`:

- In the macOS (`#else`) branch, exactly one line changed: `.testTarget(name: "AgentHUDSupportTests", dependencies:
  ["AgentHUDSupport"])` became `… , resources: [.copy("Fixtures")])`. That is the only difference from the original
  upstream manifest, as D-027 says.
- In the Windows branch, the same `resources:` line was added, and the comment now reads "Support first (M2), Core
  next (M3)".
- `.gitignore`: `/Info.plist` was added; it is anchored to the package root.

### G1: PASS

`Source checks` run **39000074546**: workflow_dispatch, head `887c949`, `completed` / `success` (03:46:39Z to
03:57:43Z UTC). Read with `ghapi.sh GET …/runs/39000074546`, `…/jobs`, and the log of job 117300942157.

| Job | Runner | Conclusion | Steps |
| --- | --- | --- | --- |
| `test` (117300942157) | macos-15 | success | Check source boundaries success; Test success (03:46:54Z to 03:57:31Z) |
| `app` (117300942083) | macos-15 | success | Build application success; Verify local signature and resources success |
| `macos` (117302966872) | ubuntu-latest | success | Tests and application passed success |

From the `test` job log:

- XCTest: `Executed 2086 tests, with 8 tests skipped and 0 failures (0 unexpected) in 411.392 seconds`.
- swift-testing: `✔ Test run with 10 tests passed after 1.316 seconds`. That includes
  `✔ Test portableDigestsEqualCryptoKit() passed after 0.682 seconds` and the golden tests
  `recordIdentitiesMatchTheGoldenSamples`, `digestsMatchTheNISTVectors`, `millisecondDatesRoundTripTheGoldenSamples`
  and `theRecordEncoderWritesTheGoldenSample` (all ✔).
- So on macOS, CryptoKit and the portable SHA-256/SHA-1 agree, and the fixture is read through the new `resources:`
  line.

### G2: PASS

**CI.** `Windows port` run **39000065894**: push, head `887c949`, `completed` / `success` (03:46:31Z to 03:50:37Z UTC).
Job `swift` (117300913518), windows-latest, success.

| # | Step | Conclusion |
| --- | --- | --- |
| 1 | Set up job | success |
| 2 | Run actions/checkout@v7.0.1 | success |
| 3 | Check source boundaries | success |
| 4 | System SQLite version | success (`winsqlite3 3.51.1`, `Microsoft Windows NT 10.0.26100.0`) |
| 5 | Cache the Swift installer | success (cache hit) |
| 6 | Download the Swift installer | skipped (cache hit, by design) |
| 7 | Verify and install Swift | success |
| 8 | Toolchain | success (`Swift version 6.4.1 (swift-6.4.1-RELEASE)`) |
| 9 | Cache the Swift build | success (`Cache not found` for `swift-build-6.4.1-26dd5319…-887c949…`, first run) |
| 10 | **Build (release)** | **success**, `Build complete! (22.90 secs)` |
| 11 | **Test** | **success**, see G3 |
| 12 | Compile a smoke package | success, `smoke true` |
| 22–25 | Post steps / Complete job | success (build cache saved) |

Warnings in the CI log: only the baseline `WinSDK.swiftmodule … reference to type 'wchar_t' broken by a context
change`, 5 times, in the debug test build and the smoke package. The release build shows none.

**Local.** Run from `%LOCALAPPDATA%\agenthud-dev\src` (HEAD `887c949`) with the PROGRESS.md Swift environment:

- `swift build -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build`: exit 0, `Build complete! (0.44 secs)`.
  The shared build folder was already up to date.
- To count warnings I also did a fresh build:
  `swift build -c release --scratch-path <scratch dir>\m2_freshbuild`. Exit 0, `Build complete! (9.20 secs)`,
  **0 warnings**, so no new warnings against the baseline.
- Side effect: that fresh build wrote the test resource bundle's `Info.plist` (`CFBundleName
  AgentHUDOpen_AgentHUDSupportTests`) into the package root. This is the behaviour `887c949` handles. `git
  check-ignore -v Info.plist` gives `.gitignore:32:/Info.plist`, so `git status` stays clean. The tester's attempt to
  delete it was refused by the session's permission check, so the ignored file is still in the tree. It is harmless;
  remove it if wanted.

### G3: PASS

- Command: the PROGRESS.md snippet. It recreates `%LOCALAPPDATA%\agenthud-dev\testprofile` with Roaming and Local, sets
  `APPDATA` and `LOCALAPPDATA` there, then runs
  `cmd /c "swift test --scratch-path %LOCALAPPDATA%_REAL\agenthud-dev\build > log 2>&1"`. Exit 0, about 8 s.
- Result: `√ Test run with 9 tests in 0 suites passed after 0.392 seconds`. All tests passed:
  - `preservesLargeIntegerCounters`
  - `recordIdentitiesHaveUnambiguousComponents`
  - `datesRoundTripAtMillisecondPrecision`
  - `parsingCanLeaveOutLongStringsAndKeepsEverythingAroundThem`
  - `parsingReadsWhatTheDecoderReads`
  - `millisecondDatesRoundTripTheGoldenSamples`
  - `theRecordEncoderWritesTheGoldenSample`
  - `recordIdentitiesMatchTheGoldenSamples`
  - `digestsMatchTheNISTVectors`
- The XCTest part found 0 tests (Support's tests are swift-testing).
- CI Test step (Windows, temporary profile): the same `√ Test run with 9 tests in 0 suites passed after 0.974 seconds`.
- Skips: none on Windows. The macOS run has 10 tests. The 10th, `portableDigestsEqualCryptoKit`, only compiles where
  CryptoKit exists, and SKIPPED_TESTS.md registers it as macOS-only with the NIST and golden tests as its Windows
  counterpart. **Registered.**
- **D-021 check (real `%LOCALAPPDATA%`):**
  - Before the run (23:47:32 local) I took a snapshot of the folder's top level: 158 entries, **0 `*.plist`**.
  - Right after my `swift test` run (about 23:48:40): **0 `*.plist`**, and no new top-level entries.
  - The temporary profile was still empty afterwards (only `Local` and `Roaming`).
  - So Support's tests wrote no `.plist` and nothing else into the real profile.
- **Warning, not caused by this run.** A later check (23:59) found **six `AgentHUDTests.<UUID>.plist` files** directly
  in the real `%LOCALAPPDATA%`:
  - All were created at **23:50:40 local**, which is after my test run and before my next command.
  - One holds the key `agents.v5`, a Core settings-store key; Support has no such store.
  - At that time `%LOCALAPPDATA%\agenthud-dev\` shows activity in another session's folders, `wtbuild` and
    `testprofile-wt` (recreated at 23:59:13). So these most likely come from a **Core test run in the `spike-m0`
    worktree**, not from M2's head.
  - If that run did use the temporary profile, then pointing `LOCALAPPDATA` elsewhere does **not** redirect
    CoreFoundation's `UserDefaults(suiteName:)`. D-021 would then not hold, and M3 needs D-018's `SettingsFile`, or
    another fix, before Core's G3 can pass the plist check.
  - I did not delete or change these files. The coordinator should find out which run created them and record the
    result in D-021.

### G4: PASS

- macOS (CI): the golden tests and `portableDigestsEqualCryptoKit` all pass (G1).
- Windows (CI and local): the same four golden tests pass, plus the existing Support tests.
- Locally, `swift test --filter RecordCodingGoldenTests` (temporary profile) gives `√ Test run with 4 tests in 0 suites
  passed`. The PROGRESS G4 name works as a filter: it matches the file.
- Fixture provenance: I ran `python scripts/make-record-coding-golden.py <scratch>\golden_regen.json`. Its output is
  **byte-identical** (`cmp`) to `Tests/AgentHUDSupportTests/Fixtures/record-coding-golden.json`, which is LF in index
  and work tree. It printed `ba7816bf…20015ad` (SHA-256 of "abc", the NIST value) and the WebSocket accept
  `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=` (RFC 6455 example).
- So Python's hashlib, CryptoKit (macOS) and PortableDigest (Windows) give the same results on the same samples.

### G6: PASS

- `python scripts\check-source-boundaries.py` from `%LOCALAPPDATA%\agenthud-dev\src` at `887c949`: `Source boundaries
  and ignore rules passed.`, exit 0. Run twice, before and after the `Info.plist` side effect.
- It also passed in CI on windows-latest (Windows port step 3) and macos-15 (Source checks `test` step 3).

### G7 (observations, for the reviewer)

- `windows.yml`:
  - Adds `persist-credentials: false` on checkout.
  - The signer regex is now anchored: `(^|, )O=Apple Inc\.(,|$)`.
  - The new Test step points `APPDATA` and `LOCALAPPDATA` at `$RUNNER_TEMP\testprofile`.
  - The build cache key is toolchain version, then `hashFiles('Package.swift')`, then the commit SHA, with a prefix
    restore key. All of this matches D-026.
- `CryptoKitShim.swift` compiles only under `#if !canImport(CryptoKit)`, so macOS keeps using CryptoKit.
  `CodexDaemonOriginTransport.swift` still has an unguarded `import Darwin`. That is fine while Core is not built on
  Windows; it is for M3 (D-015: the Codex daemon is unsupported on Windows).

### G8: PASS

- PROGRESS:
  - M1 is approved (`port-M1-approved` on `ffc8dba`) and M2 is in review from `ffc8dba`.
  - The G1 row now says "runs listed in the milestone table". The M1 row lists runs 38982139136 and 38982141982; the
    M2 row will need 39000065894 and 39000074546.
  - G2 applies "M1 (CI), M2+", G3 "M2 (Support)", G4 names `RecordCodingGoldenTests`.
  - The stale "Next steps" and "M0 notes" sections that M1-tests-1 flagged are replaced.
- DECISIONS:
  - D-026 matches `windows.yml` (release build, tests in a temporary profile, `.build` cache, `persist-credentials:
    false`, exact Apple org regex, tag-pinned actions).
  - D-027 matches `Package.swift` (resources in both branches, the only change to the macOS branch) and the generator
    script.
- SKIPPED_TESTS.md exists now: Support has none skipped (`portableDigestsEqualCryptoKit` is macOS-only by design), and
  Core is deferred to M3. This is consistent with PORTING_PLAN §6.
- No control characters in docs/windows-port, .github or Package.swift.

Non-blocking notes:

1. Record the M2 runs (39000065894 and 39000074546) in the milestone table, and the D-021 result: none from Support,
   but see the plist warning under G3.
2. D-021's own text ("checked after each G3 run … and recorded here") still needs its first entry. For M2 that is:
   0 new `.plist` from Support's tests.

## Skipped tests

| Test | Platform | Registered in SKIPPED_TESTS.md |
| --- | --- | --- |
| `portableDigestsEqualCryptoKit` (compiled only where CryptoKit exists) | not on Windows | yes (macOS-only by design; NIST and golden tests are the counterpart) |

No other Support test is skipped on Windows. Core is not built on Windows until M3.

TESTS: ALL_PASS
