# M7 test report, round 2

- Branch: `m7-work` (identical to `windows-port`). Head under test: `96bdd61` ("Windows port M7 round 2: the review's
  fixes and the CI time-zone crash").
  - M7 range `5ab51fc...96bdd61`: 89 files, +6208/−153.
  - Round 2 alone (`c6222d2...96bdd61`): 51 files, +1340/−105. Its Swift changes are 8 files, +222/−4, all under
    `Platform/Windows/` and `Tests/AgentHUDCoreTests/WindowsSupport/`.
  - Across M7, the only Swift source outside `Platform/Windows/` is `Demo/DemoData.swift`.
- Run by: port-tester, 2026-10-19, 05:10–05:25 local time (UTC−4). Machine: Windows 11 Pro 10.0.26200, not elevated,
  time zone Eastern Standard Time.
- Where it ran:
  - Worktree `E:\agenthud-dev\wt7`, reached through the junction `%LOCALAPPDATA%\agenthud-dev\wt7` (D-007).
  - Scratch build `%LOCALAPPDATA%\agenthud-dev\tester7r2build`.
  - Logs and the smoke test's pictures are in `E:\agenthud-dev\tester7r2`. The old logs there, from an interrupted
    earlier attempt, were overwritten.
- Test profile:
  - `test.ps1` and `smoke-shell.ps1` each make their own temporary `APPDATA`/`LOCALAPPDATA` (D-021).
  - For the Swift test runs I also pointed `USERPROFILE` and `HOME` at my own folder,
    `E:\agenthud-dev\testprofile-t7r2\home`. This is the real path; `%LOCALAPPDATA%\agenthud-dev` is a junction to
    `E:\agenthud-dev`. See note 3 for one side effect.
- What I changed: I wrote only this report. I committed nothing, pushed nothing, did not run `ui-check.ps1`, and
  touched no client configuration. `HKCU\…\CurrentVersion\Run` and `…\StartupApproved\Run` have the same values before
  and after, with no AgentHUD entry.
- Working tree:
  - Clean at `96bdd61` when I started.
  - At 05:17–05:19, while my G3 ran, someone else changed four documents: `BLOCKERS.md`, `DECISIONS.md`,
    `PROTOCOL.md` and `SUPPORT_MATRIX.md` (+45/−5). They also added `reports/M7-review-2.md`. Those are not mine.
  - They are documentation only, so no build or test gate depends on them. G6 passed both before and after they
    appeared.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | **PASS**: `Source checks` run 39184004326 on `96bdd61`, attempt 1, success (read by the lead). |
| G2 Windows build | **PASS** locally: release build 198 s with exactly the 6 baseline lines; `dotnet build` 0 warnings, 0 errors (also `--no-incremental`). CI: see G3's CI line. |
| G3 Windows tests | **PASS locally**: 1464 executed, 1460 passed, 4 skipped, 0 failed; the 7 changed classes also under an 8.3 `TEMP`, 65/65. **Windows CI: PASS** on attempt 2 of run 39183956058 (see below). |
| G4 determinism | **PASS**: `RecordCodingGoldenTests` 4/4 |
| G5 UI | **PASS** locally: C# 54/54 (16 protocol, 38 shell); fixtures 24 valid, 17 invalid, 0 failures; smoke test 15 pictures, status 0 after 5 s. `ui-check.ps1` **not run** (see G5). |
| G6 boundaries | **PASS** |
| G7/G8 | notes below |

Windows CI line: Windows port run 39183956058 on `96bdd61`.

- Attempt 1 failed. The one failure was the upstream timing test
  `ProcessLinesTests.testABusyMacsListingIsReadInAMoment`: 23.50 ms against its 20 ms bound. Earlier Windows runs took
  12.5–18 ms; locally it took 9.55 ms for the lead and 10.06 ms in my run.
- The lead requested one rerun of the failed job (attempt 2). **Result (filled in by the lead): attempt 2 completed `success` on 2026-10-19.**

## G1: PASS

- I did not query the API myself; these facts are as the lead read them.
- `Source checks` run **39184004326** on `96bdd61`: `success` on attempt 1.

## G2: PASS (local)

**Swift build.**

- Command: `scripts\windows\build.ps1 -Log <tester7r2>\g2swift.log -c release --scratch-path <tester7r2build>`, with
  PROGRESS.md's `Path`/`SDKROOT`, from `%LOCALAPPDATA%\agenthud-dev\wt7`.
- Duration: 198 s, `Build complete! (193.75 secs)`, exit 0, one attempt (no "being used by another process").
- Warnings: exactly the 6 baseline lines from D-033, each once, nothing new:
  - `MCPStdio.swift:59` `strerror`;
  - `PermissionHookClient.swift:38` `close`;
  - `ZstandardReader.swift:46` `close`;
  - `AntigravityCLI.swift:18` `init(cString:)`;
  - `CodexDesktopStream.swift:170` `wait(until:)` unused;
  - `DeepSeekQuestions.swift:106` `await`.
- There was no `wchar_t` line. That is the toolchain's baseline item, and its absence is not a new warning.
- Engine: `<tester7r2build>\out\Products\Release-windows-x86_64\agenthud-engine.exe`, 29,403,648 bytes.

**.NET build.**

- Command: `dotnet build windows\AgentHUD.sln -c Release`.
- Result: 7 s, `0 个警告 0 个错误`. A `--no-incremental` rebuild also gave 0 warnings and 0 errors.
- All five projects built: Protocol, Shell, both test projects and AgentHUD.

## G3: PASS locally; Windows CI PASS on attempt 2

### Full run

- Command: `& scripts\windows\test.ps1 -ScratchPath <tester7r2build> -Log <tester7r2>\g3.log`, with `USERPROFILE`/`HOME`
  set to the test home.
- Duration: 263 s, exit 0. Test build: `Build complete! (57.55 secs)`.
- Support: swift-testing `√ Test run with 9 tests … passed`.
- Core XCTest: **1464 executed, 1460 passed, 4 skipped, 0 failed**.
  - The 9 batches were 113/126/125/201/201/255/76/255/112.
  - No batch failed, and 0 `Test Case … failed` lines.
  - This equals SKIPPED_TESTS.md's state line, "1460 pass, 4 runtime skips".
- **Round 1's crash is fixed here.**
  - `WindowsTimeZoneTests` 5/5, including the new `testTheUTCZoneCanBeTheDefault` and
    `testZonesFoundationDoesNotListAreTheirOffset`.
  - `EngineServeEndToEndTests` 6/6, including `testARealRequestGoesThroughTheProtocolAndHooksChangeOnlyWithTheirSwitch`
    (12.1 s) and `testTheDemoServesStateTakesAnswersAndSettingsAndQuits` with its new `sources` check.
  - This machine is not in the `UTC` zone, so the UTC path is exercised only by `testTheUTCZoneCanBeTheDefault`. It sets
    Foundation's default to `adoptable("Etc/UTC")`, which round 1 showed traps when given unguarded.
  - CI attempt 1 ran on a `UTC` runner, and per the lead its only failure was the timing test. So the crash did not
    recur there.
- The upstream timing test passed locally: `a 414 KB process listing: 10.06 ms`, against its 20 ms bound.
  - `ProcessLinesTests.swift` is unchanged since upstream (`3712733`, an ancestor of `c258093`).

### The classes changed in M7 under an 8.3 `TEMP`

- Setup: `TEMP`/`TMP` = `C:\Users\suzume\AppData\Local\Temp\AG7865~1`, the short name of
  `…\Temp\agenthud tester7r2 LongNamedTemporaryFolder`. Drive E: makes no 8.3 names, so the folder is on C:.
- Command: `test.ps1 … -Filter EngineServeEndToEndTests, HookFormsWindowsTests, InstanceLockWindowsTests,
  ProtocolWriterTests, ShellProtocolTests, WindowsProcessesTests, WindowsTimeZoneTests`.
- Result: 31 s, exit 0, **65/65 passed**:
  - `EngineServeEndToEndTests` 6;
  - `HookFormsWindowsTests` 24;
  - `InstanceLockWindowsTests` 6;
  - `ProtocolWriterTests` 5;
  - `ShellProtocolTests` 13;
  - `WindowsProcessesTests` 6;
  - `WindowsTimeZoneTests` 5.
- The short folder held 26 items afterwards, so the short `TEMP` was in effect. I removed it.
- My first try of this run passed the filters as one string by mistake. `test.ps1` then refused it: `no test matched
  the filter …`, exit 1. That is the guard step 1 added, and it works.

### Skips

- Runtime skips, 4: the four `…Probe` tests. All are registered in SKIPPED_TESTS.md §3.
- Skip list: all 34 patterns in `scripts/windows/skipped-tests.txt` are in SKIPPED_TESTS.md §2 (checked by script,
  class and test name).
- Excluded files: all 7 in `windowsSkippedTests` are in §1.
- Nothing unregistered was skipped.

## G4: PASS

- Command: `test.ps1 … -Filter RecordCodingGoldenTests`. Duration: 9 s, exit 0.
- Result: `√ Test run with 4 tests in 0 suites passed`.
  - `theRecordEncoderWritesTheGoldenSample`.
  - `millisecondDatesRoundTripTheGoldenSamples`.
  - `recordIdentitiesMatchTheGoldenSamples`.
  - `digestsMatchTheNISTVectors`.

## G5: PASS locally (`ui-check.ps1` not run)

**`scripts\windows\test-dotnet.ps1`:** 4 s, exit 0.

- `已通过! - 失败: 0，通过: 16 … AgentHUD.Protocol.Tests.dll`.
- `已通过! - 失败: 0，通过: 38 … AgentHUD.Shell.Tests.dll`.
- `Protocol fixtures: 24 valid, 17 invalid, 0 failure(s).`
- This matches SKIPPED_TESTS' line of 54 C# tests.

**`python scripts\windows\check-protocol.py`, run on its own:** 0.3 s, exit 0, with the same line.

**`scripts\windows\smoke-shell.ps1 -Engine <tester7r2build>\…\agenthud-engine.exe -Out <tester7r2>\snapshot`:** 7 s,
exit 0. Its build gave 0 warnings and 0 errors.

- `Shell smoke test: 15 pictures in E:\agenthud-dev\tester7r2\snapshot, status 0 after 5 s.`
- Sizes:
  - island-rest 992x67, island-open 992x780, island-request 992x131, island-usage 992x1798;
  - card-edit 992x864, card-question 992x1040, card-plan 992x826;
  - event-reply-line 395x64, event-reply-card 992x364, event-quota-line 360x64, event-quota-card 992x558,
    event-credits-line 343x64, event-credits-card 992x460;
  - settings 1091x1472, statistics 1411x448.
- No `AgentHUD`/`agenthud-engine` process was left afterwards.

**What the pictures show.** I opened five, including those new in round 2.

| Picture | Shows | Matches |
| --- | --- | --- |
| `island-rest` | the dark bar with the 17 vendor marks; Claude's has its dot | yes |
| `island-request` (new) | "agent-hud · Waiting ×7" above the marks: the request's line at rest, without the panel open | yes |
| `card-edit` (new) | "Needs approval / Avatar.tsx", the red/green diff lines, "Always allow adds Edit(src/**)", Deny / Always allow / Allow, then the queue | yes: the diff shows (review round 1, item 1) |
| `card-question` | "Asks a question / Which database?", 1/2, SQLite (One file) / Postgres / Other, Skip and a disabled Next, then the queue | yes |
| `settings` | Appearance & language; Startup; Clients (hooks, "Wait for an answer: 10 minutes"); and the new **Agents** section: Claude, Codex, DeepSeek "Ready", Antigravity "Not supported on Windows / Appears once installed" | yes |

**`scripts\windows\ui-check.ps1`:** **not run**, as instructed.

- It needs an idle desktop with real clicks, and the user may be at this machine.
- The author reports 25 checks passed locally (PROGRESS.md, M7 round 2). I have not verified that.

**CI:** the C# tests, the fixtures and the `shell-snapshot` artifact of run 39183956058 depend on its rerun; the lead
fills them in with the Windows CI line.

## G6: PASS

- Command: `python scripts\check-source-boundaries.py`, 1.5 s. Output: `Source boundaries and ignore rules passed.`
- I ran it on the clean head at 05:10, and again at 05:24 with the other session's uncommitted doc edits present.
  Both passed.

## G7/G8 notes

1. **(G3, CI) A timing test with a fixed bound.**
   - The only CI failure on `96bdd61` is upstream's `testABusyMacsListingIsReadInAMoment` (20 ms bound).
   - It is not a port test, and its file is unchanged.
   - On Windows runners it has measured 12.5–23.5 ms, so its margin there is thin. If attempt 2 fails too, that is a
     finding, not a flake.
2. **(G7) The UTC fix is checked by a unit test only on this machine.**
   - `adoptable` keeps an IANA identifier Foundation lists, or one with daylight transitions. Anything else becomes a
     fixed offset.
   - The end-to-end engine start under a real `UTC` Windows zone is covered only by CI's runner. I could not change the
     system zone here (that needs elevation, and it is the user's machine).
3. **(tooling) `remove-test-preferences.ps1` follows `%USERPROFILE%`, but Foundation does not.**
   - With `USERPROFILE` pointed at a test home, the cleanup looked in `<test home>\AppData\Local` and removed 0 files.
     Meanwhile Foundation had written 6 `AgentHUDTests.<UUID>.plist` files into the real `%LOCALAPPDATA%`.
   - The cause: .NET's `GetFolderPath(LocalApplicationData)` expands the known folder with the process's
     `USERPROFILE`, while swift-corelibs-foundation does not.
   - I removed exactly those 6 files by running the script again under the real profile
     (`Removed 6 test preference file(s) from C:\Users\suzume\AppData\Local`). Later runs left none.
   - This only matters to someone who overrides `USERPROFILE`, as the tester role asks. `test.ps1` itself does not.
4. **(visual, as in round 1, not failures)**
   - `card-question` still shows "Which database?" twice: as the card's title and as question 1/2's header.
   - In the demo's settings picture, "Launch at login" is checked. That is the setting's value, not the registry.
     `LoginItem` is gated, and the real `Run` keys were unchanged after the smoke test.
5. **(known issue) The real `%TEMP%` still grows.**
   - 92 top-level items appeared during my runs (3390 → 3482), most of them `TemporaryDirectory.*` and `agenthud-*`
     folders from the tests.
   - I removed only my own 8.3 folder.

## Skipped tests and registration

| Skip | Kind | Registered |
| --- | --- | --- |
| `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe` | runtime (`AGENT_HUD_PROBE_…`) | yes, §3 |
| `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe` | runtime | yes, §3 |
| `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe` | runtime | yes, §3 |
| `SessionUsageProbeTests.testReportedSessionsUsageProbe` | runtime | yes, §3 |
| 34 patterns in `scripts/windows/skipped-tests.txt` | skip list | yes, all 34 in §2 |
| 7 files in `windowsSkippedTests` (`UnixSocketListenerTests`, `ChildProcessTests`, `InstanceLockTests`, `CodexDaemonOriginTransportTests`, `CodexDesktopTestServer`, `CodexDesktopPermissionsTests`, `CodexDesktopStreamTests`) | excluded files | yes, all 7 in §1 |
| Conditional runtime skips (no `node.exe`/`git.exe`/8.3 names/…) | runtime | none triggered locally |
| C# tests | — | none skipped |

Every gate I ran passed. G1 is green, and the Windows CI rerun (attempt 2 of run 39183956058) passed (filled in by
the lead).

TESTS: ALL_PASS
