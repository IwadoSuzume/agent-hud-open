# M6 test report, round 1

- Branch: `windows-port`. Head under test: `80fb737` ("Windows port M6: the engine-shell protocol v1.0 and
  agenthud-engine --serve"). M6 range: `0f51d89...80fb737`, 63 files, +2208/−44.
- Run by: port-tester, 2026-10-18. Local times are the machine's (UTC−4). Machine: Windows 11 Pro 10.0.26200.
- The working tree was clean at `80fb737` before and after the gates. I wrote only this report in the repository. I
  committed nothing, pushed nothing, and made no CI call except reads (no re-run was needed).
- One stray of my own was removed: importing `scripts/windows/check-protocol.py` from a scratch script (to validate the
  engine's live output against the schema, check (c)) wrote `scripts/windows/__pycache__/` (ignored) at 05:10:08. I
  deleted it; it did not exist before.
- Local builds used `%LOCALAPPDATA%\agenthud-dev\build` through the junction `%LOCALAPPDATA%\agenthud-dev\src` (→
  `E:\桌面项目\agent-hud-open`). Throwaway clones and builds were under the session scratch `m6r1\` and are deleted.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | **PASS** on attempt 1: `Source checks` run 39113715915, head `80fb737`; `test`, `app`, `macos` success; 2087 XCTest, 8 skipped, 0 failures; swift-testing 10 passed. No re-run was needed. |
| G2 Windows build | **PASS locally** (release build 195.0 s, the 6 baseline warning lines, each once; `dotnet build windows\AgentHUD.sln -c Release`: 0 warnings, 0 errors). **CI: not run** — run 39113715719 stopped at step 4 (G5), so `Build (release)` was skipped. |
| G3 Windows tests | **PASS locally**: 1445 executed, 1441 passed, 4 skipped, 0 failed (Support 9/9). **CI: not run** (step `Test` skipped). |
| G4 determinism | PASS on macOS CI and Windows local. Windows CI: not run. |
| G5 UI (protocol) | **FAIL**: in CI, `AgentHUD.Protocol.Tests` **0 of 7 passed** (all 7 failed on the fixtures' line ends, see BLOCKING 1). Locally `test-dotnet.ps1` passes (7/7; 16 valid + 15 invalid fixtures). Reproduced locally in a clone checked out with `core.autocrlf=true`: 7/7 fail, and `check-protocol.py` reports 16 failures. |
| G6 boundaries | PASS locally and in both CI jobs |
| M6 (a) `ShellProtocolTests` (7), `EngineServeEndToEndTests` (4) | Local: **11/11 passed**, none skipped. CI: **did not run** (the Windows job never reached `Test`; both classes are `#if os(Windows)`, so macOS does not run them). |
| M6 (b) engine fixtures reproducible | **PASS**: rewritten with `AGENT_HUD_WRITE_PROTOCOL_FIXTURES=1` in a scratch clone (05:17, 16 minutes after the committed files' checkout time); `git status` in the clone empty, the five `engine-*.json` blob hashes equal the committed ones. CI's UTC run is not available (see (a)); see note 2 on time zones. |
| M6 (c) protocol output is protocol only | **PASS**: `agenthud-engine.exe --serve --demo` in a temporary profile; every stdout line is a JSON object with `"v":1`; nothing on stderr; exit 0 at end of input and on `quit`; the live lines validate against `v1.schema.json`. |
| M6 (d) telemetry off, package allowlist | **PASS**: no telemetry variable persisted (User/Machine scope empty before and after); `check-source-boundaries.py` passes; the restore resolves exactly the 15 packages named in THIRD_PARTY_NOTICES.txt. The allowlist has two gaps (note 1). |
| M6 (e) notices identical | **PASS**: `THIRD_PARTY_NOTICES.txt` and `Sources/AgentHUDDesktop/Resources/THIRD_PARTY_NOTICES.txt` byte-identical (`cmp`; SHA-256 `958fc85b…1fd00` both) |
| M6 (f) real profile, tracked build output | **PASS**: no `%LOCALAPPDATA%\Debug-windows-x86_64`, 0 `*.plist` in the real `%LOCALAPPDATA%` before and after (test.ps1 removed its 6); 0 tracked paths under `bin/`, `obj/`, `TestResults/` |
| G7 | observations below |
| G8 | notes below |

## BLOCKING findings

### 1. G5 fails in CI: the protocol fixtures are checked out with CR LF on the Windows runner

- **Where:** `Windows port` run 39113715719, job `swift` (117635051363), step 4 "Shell protocol and .NET tests (G5)",
  09:01:56Z–09:02:26Z.
- **What failed:** all 7 C# tests, each on the same assertion in `ProtocolTests.Line`
  (`windows/AgentHUD.Protocol.Tests/ProtocolTests.cs:35`):

  ```
  Failed TheEnginesHelloIsRead [30 ms]
  Assert.IsFalse failed. 'condition' expression: 'text.Contains('\n') || text.Contains('\r')'. engine-hello.json: one line
  ...
  Failed!  - Failed:     7, Passed:     0, Skipped:     0, Total:     7, Duration: 93 ms - AgentHUD.Protocol.Tests.dll (net10.0)
  dotnet test failed with 1
  ```

  Restore and build were clean (no warning line), so the failure is the data, not the code.
- **Cause:**
  - The repository has no `.gitattributes`.
  - Git for Windows' system configuration sets `core.autocrlf=true`. The runner's `actions/checkout` therefore writes
    every fixture as `…}\r\n`. `git ls-files --eol` shows `i/lf w/crlf` in such a checkout.
  - `ProtocolTests.Line` removes the final `\n` and then refuses the remaining `\r`. `check-protocol.py` refuses it too
    ("more than one line, or a CR").
  - This machine's repository has `core.autocrlf=false` (PROGRESS "Environment"), which is why the local G5 passes.
    The user's own global setting is `true`, so a fresh clone on this machine fails the same way.
- **Reproduced locally:**
  - `git clone -c core.autocrlf=true` of `80fb737` into the scratch folder, then `scripts\windows\test-dotnet.ps1`
    there: `失败! - 失败: 7，通过: 0`.
  - `python scripts\windows\check-protocol.py` in the same clone: `Protocol fixtures: 16 valid, 15 invalid, 16
    failure(s).` All 16 valid fixtures fail.
- **Consequence:**
  - The Windows job ends at step 4. Steps 5–13 were skipped: Swift install, `Build (release)`, `Test`, and `Compile a
    smoke package`.
  - So for `80fb737` there is **no Windows CI evidence for G2, G3 or G4**.
  - CI also never ran `ShellProtocolTests` or `EngineServeEndToEndTests`, so M6 check (a) and the "CI on UTC" half of
    (b) cannot be shown from CI.
- **Suggestion (for the implementer):** pin the fixtures' bytes in git, for example a `.gitattributes` line
  `windows/protocol/fixtures/** -text` (or `eol=lf`). Then re-run the Windows workflow.
- **Related asymmetry:** the Swift reader of the same files strips any trailing `0x0A`/`0x0D`
  (`ShellProtocolTests.fixture`, line 34). It would not have caught this. With CR LF fixtures the 7 Swift tests still
  pass: I ran them in the clone, 7/7.

## G1: PASS

`Source checks` run **39113715915**:

- Trigger: workflow_dispatch on `windows-port`, head `80fb73757d046b03a8d98853561b5358e3d0f38a`.
- Final state: `completed` / `success`, `run_attempt` 1, 09:01:38Z to 09:11:04Z.
- Runner image: `macos-15-arm64` 20260907.0337.1, provisioner 20260828.587. This is the same image as M5.

| Job | Conclusion | Steps |
| --- | --- | --- |
| `test` (117635054128) | success | Check source boundaries: success (`Source boundaries and ignore rules passed.`); Test: success, 09:01:49Z to 09:10:59Z |
| `app` (117635054230) | success | Build application: success; Verify local signature and resources: success |
| `macos` (117636894303) | success | Tests and application passed |

- `Executed 2087 tests, with 8 tests skipped and 0 failures (0 unexpected) in 395.198 (395.335) seconds`.
- `✔ Test run with 10 tests passed after 1.130 seconds.` This includes `portableDigestsEqualCryptoKit`.
- **The upstream flaky test passed on attempt 1.** `StatsWindowLifecycleTests.testNativeRestoreFitsContentUpdatedWhileMiniaturized`
  passed in 1.734 s. No `rerun-failed-jobs` was needed or made.
- **The 8 skips are the same as in M5:**
  - the four `…Probe` tests;
  - `ArtworkMemoryTests.testProbeWritesEveryBakedMarkBotAndAccent`;
  - `BotFrameTests.testFrameCost`;
  - `BotMarkTests.testAReminderMarkOpensAsItsLogoAndTurnsIntoItsBotOnceItsCardHasOpened`;
  - `IslandAnimationTests.testAGlowThatClosesStopsItsFrames`.
- All 34 `skipped-tests.txt` entries have a `passed` line on macOS.
- **macOS warnings: the same file:line set as M5, nothing new.**
  - Core: `DeepSeekQuestions:106`, `AntigravityCLI:18`.
  - Core tests: `PermissionHookTests` 435/442/453, `PanelToolsSpanTests:91`, `DeepSeekProviderTests:525`,
    `CollectionSignalTests:331`, `UsageRefreshTests:73`.
  - Desktop tests: `AgentSeparationTests` 136/209/243, `JoinedGlassTests` 192/246, `ScreenStyleHUDTests:254`.
- **The M6 change to Desktop is the notices file only.** `git diff 0f51d89 80fb737 -- Sources/AgentHUDDesktop
  Sources/AgentHUDOpenApp Tests/AgentHUDDesktopTests` changes only `Resources/THIRD_PARTY_NOTICES.txt` (+30 lines).
  The `app` job's resource verification passed with it.

## G2: PASS locally; CI not run

### CI

- Run 39113715719 (push of `80fb737`, job `swift`) ended `failure` at step 4 (BLOCKING 1).
- Step 11 `Build (release)` and step 13 `Compile a smoke package` were **skipped**.
- The .NET build inside step 4 printed no warning: both projects built, then the tests failed.

### Local

- **Swift release build:** `swift build -c release --scratch-path %LOCALAPPDATA%\agenthud-dev\build`, from the
  junction at `80fb737`, with the PROGRESS.md environment, through `cmd /c "… > log 2>&1"`.
  - Result: exit 0, `Build complete! (195.01 secs)`. Wall clock 05:05:53 to 05:09:10.
  - `release\agenthud-engine.exe` was rebuilt (05:09, 29,064,704 bytes).
  - There was no `error:` line.
  - **Warnings: exactly the 6 baseline lines, each once.**
    - `MCPStdio.swift:59` `strerror`
    - `PermissionHookClient.swift:38` `close`
    - `ZstandardReader.swift:46` `close`
    - `AntigravityCLI.swift:18` `init(cString:)`
    - `CodexDesktopStream.swift:170` `wait(until:)`
    - `DeepSeekQuestions.swift:106` `await`

    None of the new `Platform/Windows/Shell/*.swift` files or `AgentHUDEngine/main.swift` printed a warning.
- **.NET build:** `dotnet build windows\AgentHUD.sln -c Release`, plus a `--no-incremental` rebuild, with the
  telemetry opt-outs set in the shell.
  - Result: exit 0, `0 个警告 / 0 个错误` (0 warnings, 0 errors), for `AgentHUD.Protocol` and
    `AgentHUD.Protocol.Tests`.
  - Both projects set `TreatWarningsAsErrors`.

### Test-build warnings (G3's build; outside G2 since D-033)

The local test build was incremental (`Build complete! (29.75 secs)`). It printed only the upstream test lines known
from M5:

- `PermissionHookTests` 375/435/442/453
- `MCPStdioTests` 80/81/84
- `PanelToolsSpanTests:91`
- `CollectionSignalTests:331`
- `UsageRefreshTests:73`
- `DeepSeekProviderTests:525` (×2)

None of the port's test files printed a warning. That includes `ShellProtocolTests`, `EngineServeEndToEndTests`, and
the changed `HookFormsWindowsTests` and `ProviderHTTPWindowsTests`.

## G3: PASS locally; CI not run

- **Command:** `%LOCALAPPDATA%\agenthud-dev\src\scripts\windows\test.ps1 -ScratchPath %LOCALAPPDATA%\agenthud-dev\build
  -Log <scratch>\m6r1\g3.log`.
- **Setup:** Windows PowerShell 5.1, the PROGRESS.md environment, the junction, `80fb737`.
- **Result:** exit 0 in **207 s** (05:10:42 to 05:14:08).
  - Build-first step: 1 attempt, no file-in-use line.
  - Support: `Test run with 9 tests in 0 suites passed after 0.385 seconds.`
  - Core, 9 batches: 113 + 126 + 125 + 199 + 200 + 255 + 71 + 249 + 107 = **1445 executed: 1441 passed, 4 skipped,
    0 failed**.
  - `Removed 6 test preference file(s) from C:\Users\suzume\AppData\Local`.
- **Compared with M5 round 2** (1430 executed): +15 executed, +15 passed.
  - The 7 `ShellProtocolTests` and 4 `EngineServeEndToEndTests` are new.
  - The other 4 are the changed Windows test files: batch 4 grew 191 → 199, batch 8 grew 242 → 249.
- **This matches** PROGRESS's pre-review line and the SKIPPED_TESTS.md state line "1441 pass, 4 runtime skips, 34
  listed skips, 7 excluded files, 0 failures".
- **CI:** step 12 `Test` of run 39113715719 was skipped (BLOCKING 1). There is no CI count to compare against.

### M6 (a): the new test classes, locally

| Test | Local |
| --- | --- |
| `ShellProtocolTests.testASettingsPatchIsAppliedByCoreOrNotAtAll` | passed 0.001 s |
| `ShellProtocolTests.testAnAnswerBecomesCoresOwnDecision` | passed 0.0 s |
| `ShellProtocolTests.testEngineMessagesAreTheSharedFixtures` | passed 0.156 s |
| `ShellProtocolTests.testEveryEngineMessageCarriesTheVersionAndAType` | passed 0.001 s |
| `ShellProtocolTests.testLinesAReaderMustRefuseAreRefused` | passed 0.008 s |
| `ShellProtocolTests.testShellMessagesAreTheCommandsTheyStandFor` | passed 0.001 s |
| `ShellProtocolTests.testTheShellsWordsAreTheDesktopsOwn` | passed 0.151 s |
| `EngineServeEndToEndTests.testAnArgumentServeDoesNotTakeIsRefused` | passed 1.887 s |
| `EngineServeEndToEndTests.testAnEngineThatFindsAnotherCopyRunningSaysWhichAndExits` | passed 0.155 s |
| `EngineServeEndToEndTests.testTheDemoServesStateTakesAnswersAndSettingsAndQuits` | passed 0.529 s |
| `EngineServeEndToEndTests.testTheEngineEndsWhenItsInputEnds` | passed 0.217 s |

- C#, locally: 7/7 passed (G5).
- In CI: none of the 11 Swift tests ran; the 7 C# tests failed.
- `FileChangeMonitorWindowsTests.testAWatchedDirectoryThatGoesAwayAsksForAFullScan` (the known flaky test) passed.

## G4: PASS (macOS CI and Windows local; Windows CI not run)

The four Support golden tests passed in both places:

- `recordIdentitiesMatchTheGoldenSamples`
- `digestsMatchTheNISTVectors`
- `millisecondDatesRoundTripTheGoldenSamples`
- `theRecordEncoderWritesTheGoldenSample`

| Where | Result |
| --- | --- |
| macOS CI | 10/10 passed, including `portableDigestsEqualCryptoKit` |
| Windows local | 9/9 passed |

`git diff 0f51d89 80fb737 -- Sources/AgentHUDSupport Tests/AgentHUDSupportTests` is empty.

## G5: FAIL (CI); local pass

| Where | Command | Result |
| --- | --- | --- |
| CI, step 4 of run 39113715719 | `dotnet --list-sdks`, then `scripts/windows/test-dotnet.ps1` (pwsh 7; SDK 10.0.401 present among 8.0–10.0) | restore 10.3 s, build clean, **7 failed / 0 passed**; `check-protocol.py` not reached |
| Local, the working tree | `powershell -File scripts\windows\test-dotnet.ps1` | exit 0: `已通过! - 失败: 0，通过: 7，已跳过: 0，总计: 7` (passed 7, failed 0, skipped 0); `Protocol fixtures: 16 valid, 15 invalid, 0 failure(s).` |
| Local, clone with `core.autocrlf=true` | the same script | exit 1: 7/7 failed on "one line" (BLOCKING 1); `check-protocol.py` there: 16 failures |

Every committed fixture is exactly one line, ends with one LF, has no CR and no BOM: all 16 valid and all 15
invalid files.

## M6 (b): the engine fixtures are reproducible: PASS

1. I cloned `80fb737` into the scratch folder, with LF line ends.
2. In the clone, I ran `test.ps1 -ScratchPath <scratch>\b -Filter AgentHUDCoreTests.ShellProtocolTests` with
   `AGENT_HUD_WRITE_PROTOCOL_FIXTURES=1`. The fixture path comes from `#filePath`, so the clone's own fixtures were
   written.
   - Result: 7/7 passed. `Build complete! (72.21 secs)`, exit 0 in 80 s.
   - The five `engine-*.json` files were rewritten at 05:17:35.
3. Afterwards, `git status --short` in the clone was **empty**. The blob hashes equal the committed ones:
   `f6e57f67…`, `42cfb8aa…`, `1efa934c…`, `b25c5041…`, `63dfa838…`.
4. The working tree's fixtures were not touched. They still have their 05:01:32 checkout times, and `git status` is
   clean.

The fixtures rely on a fixed `now` (`1_792_000_000`), an explicit UTC `Calendar` and `L10n.setLanguage(.en)`. On this
machine, Swift's Foundation reports `TimeZone.current` as `GMT` whatever the Windows zone or `TZ` is (note 2). So "local
passed on UTC−4" does not, on its own, show independence from the zone. CI's UTC run did not happen.

## M6 (c): the engine's standard output carries only protocol: PASS

- **The program:** `release\agenthud-engine.exe --serve --demo`, from the G2 build.
- **The temporary profile:** I started it from a Python harness (`m6r1\serve_smoke.py`), with `APPDATA`,
  `LOCALAPPDATA`, `USERPROFILE`, `HOME`, `TEMP` and `TMP` pointed into a fresh scratch folder, and `CREATE_NO_WINDOW`.
- **What the harness checks:**
  - every stdout line parses as a JSON object with integer `"v": 1` and a string `type`;
  - no CR in the output, no BOM;
  - the output ends with LF;
  - stderr.

| Mode | Lines sent | Exit | stdout | stderr |
| --- | --- | --- | --- | --- |
| end of input | `hello`, then stdin closed after 3 s | **0** | 4 lines (`hello` ×1, `state` ×3), 0 bad | 0 bytes |
| more lines, then end of input | `hello`; then `refresh`, `not json`, `{"v":2,…}`, `{"v":1,"type":"nonsense"}`, an `answer` for an unknown id, an `update-settings` patch Core cannot decode | **0** | 9 lines (`hello` 1, `state` 4, `error` 4), 0 bad | 0 bytes |
| `quit` | as above, then `{"v":1,"type":"quit"}` | **0** | 9 lines, 0 bad | 0 bytes |

- **The `hello` line:** `minor 0`, `demo true`, `language en`, 14 `strings`.
- **The four `error` messages:**
  - `not a JSON object`
  - `not protocol version 1`
  - `unknown type nonsense`
  - `settings Core does not take: DecodingError.typeMismatch …`
- **The unknown-id `answer`** was ignored without an error, as PROTOCOL.md says.
- **Exits:** the engine exited at once after end of input and after `quit`.
- **Schema check:** all 9 lines of the `quit` run validate against `windows/protocol/schema/v1.schema.json`, using
  `check-protocol.py`'s own `validate`: 0 failures.
- **Files written:** the demo wrote **no file** in the temporary profile. The real `%APPDATA%\Agent HUD Open` modification
  time is unchanged (2026-10-16 17:20:19).

## M6 (d): telemetry and the package allowlist: PASS (with gaps, note 1)

- **No telemetry setting persisted.**
  - `DOTNET_CLI_TELEMETRY_OPTOUT` and `TESTINGPLATFORM_TELEMETRY_OPTOUT` are empty at User and Machine scope, before
    and after.
  - `test-dotnet.ps1` sets them for its own process only.
  - The run left no telemetry folder in `%TEMP%`.
  - `%USERPROFILE%\.dotnet` changed only in `sdk-advertising\10.0.400`, at 05:04:34. That is the CLI's workload-update
    check, on my first `dotnet` run (note 4).
- **The boundary check:** `python scripts\check-source-boundaries.py`: `Source boundaries and ignore rules passed.`,
  exit 0. It also passed in CI: Windows step 3 and the macOS `test` job.
- **The packages restored:** `obj/project.assets.json` has exactly 15 packages, the 3 direct ones and 12 transitive:
  - `MSTest.TestFramework`/`TestAdapter`/`Analyzers` 4.0.2
  - `Microsoft.NET.Test.Sdk`, `Microsoft.CodeCoverage`, `Microsoft.TestPlatform.TestHost`/`ObjectModel`/`AdapterUtilities`
    18.0.1
  - `Microsoft.Testing.Platform`/`Platform.MSBuild`/`Extensions.Telemetry`/`Extensions.TrxReport.Abstractions`/
    `Extensions.VSTestBridge` 2.0.2
  - `Microsoft.ApplicationInsights` 2.23.0
  - `Newtonsoft.Json` 13.0.3

  That is exactly the list in THIRD_PARTY_NOTICES.txt.
- **The allowlist works where it looks.** I probed it in a throwaway clone, with staged files:

  | Probe | Result |
  | --- | --- |
  | an unknown package in a `.Tests.csproj` | refused, with 2 messages |
  | an allowed package in a non-test project | refused ("belongs in a test project only") |
  | a `windows/nuget.config` | refused |

  The two gaps it leaves are in note 1.

## M6 (e), (f): PASS

- **(e)** `cmp THIRD_PARTY_NOTICES.txt Sources/AgentHUDDesktop/Resources/THIRD_PARTY_NOTICES.txt` found the files
  identical. Both have SHA-256 `958fc85b9fc83bdf3f8f349bb6b26c1feed3eff54bc55b2d0b8a672b0c01fd00`.
- **(f) Build output:** `git ls-files` has 0 paths under any `bin/`, `obj/` or `TestResults/`.
  - `git status --short --ignored` lists only ignored `.build/`, `Info.plist` and the four `windows/**/bin|obj`
    folders.
  - The `.gitignore` rules for `windows/**/bin/`, `obj/`, `TestResults/` and `__pycache__/` match.
- **(f) The real profile:**

  | Check | Before | After G3 | End |
  | --- | --- | --- | --- |
  | `%LOCALAPPDATA%\Debug-windows-x86_64` | absent | absent | absent |
  | `*.plist` directly in the real `%LOCALAPPDATA%` | 0 | 0 | 0 |
  | `cmdkey /list` lines matching `agenthud-test` (count only) | 0 | 0 | 0 |
  | `*.agenthud-*` files under `%TEMP%`, recursive | 0 | 0 | 0 |
  | `agenthud-testprofile-*` in `%TEMP%` | 0 | 0 (1 while my clone run was going) | 0 |

- **Client folders:**
  - `.claude\settings.json` (2026-10-16), `.codex\config.toml` and `hooks.json` (2026-09-29), and `.copilot`
    (2026-10-14) are unchanged.
  - `.gemini\settings.json`, `.cursor\mcp.json`, `.qwen`, `.codebuddy` and `.qoder` are absent.
  - `.claude.json` changed at 05:14:59, after G3 ended. That is the running Claude Code client.

## D-006

`git diff c258093 80fb737` is 0 bytes for all six `windowsReplaced` files.

## G7 (observations, for the reviewer)

- **D-022's output redirection holds.** `EngineServe.takeProtocolOutput` duplicates the inherited stdout and points
  `STD_OUTPUT_HANDLE` and C descriptor 1 at stderr.
  - In (c), nothing other than protocol lines reached stdout.
  - Nothing reached stderr either: there was no stray print in demo mode.
- **The reader takes `\r\n`.** `EngineServe.readLines` splits on `0x0A` only and leaves a trailing `\r` in the line.
  JSON parsers treat `\r` as whitespace, so a CR LF shell line would be accepted, although PROTOCOL.md says "ended by
  `\n` alone". I did not send one. This is harmless, but it is a second place where the Swift side is more lenient than
  the C# side (see BLOCKING 1's asymmetry).
- **The lock test is isolated.** `testAnEngineThatFindsAnotherCopyRunningSaysWhichAndExits` uses its own lock URL, and
  the demo takes no lock. My smoke runs, the G3 end-to-end tests and the real profile did not interfere.

## G8: notes (non-blocking)

1. **The boundary check's package allowlist can be bypassed.** I probed this in a throwaway clone with staged files;
   the repository is unchanged.
   - Attribute order: `<PackageReference Version="1.0.0" Include="Evil.Pkg" />` **passes**. Both regexes need
     `Include` to come right after `PackageReference`.
   - Other MSBuild files: a package in `windows/Directory.Build.props` **passes**, because only `*.csproj` files are
     read. The same holds for `.targets` and `Directory.Packages.props`.

   The current tree is compliant. These are gaps against future changes (TASK.md G6 "依赖白名单", the dependency
   allowlist).
2. **On this machine, Swift Foundation 6.4.1 reports the local time zone as GMT.** The machine's Windows zone is
   "Eastern Standard Time", UTC−4 now.
   - A 4-line probe printed `TimeZone.current` = `GMT 0`. `Calendar.current.timeZone`, `autoupdatingCurrent` and a
     default `DateFormatter` all printed GMT.
   - The probe printed the same with and without `TZ=America/New_York`.
   - `TimeZone(identifier: "America/New_York")` works (−14400).
   - **Effect on the protocol:** `ShellProtocol.state` defaults to `calendar: .current`. `resetText` for a reset more
     than 24 h away is `ChartData.weekdayTime` ("Sun 13:00"), so on Windows it would show GMT wall-clock times.
   - Core's other `Calendar.current` uses (`CursorClient` start of day, `DemoClock`) are affected the same way.
   - This is not caused by M6, but M6 is where Core's formatting first reaches a Windows user. It belongs in PROGRESS
     "Known issues" or with M7, together with a Windows test that pins the local zone.
3. **The C# and Python fixture readers refuse a CR, but the Swift reader strips it.** This asymmetry hid BLOCKING 1 from
   the Swift tests: 7/7 Swift tests pass on CR LF fixtures. Whatever fix is chosen, the three readers could agree on the
   bytes.
4. **.NET CLI side traffic.** My first `dotnet` run refreshed `%USERPROFILE%\.dotnet\sdk-advertising\10.0.400`. That is
   the workload-update advertising check, a nuget.org request and not telemetry. `test-dotnet.ps1` does not set
   `DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE`.

   In CI, `dotnet --list-sdks` runs before the script sets the opt-outs. It is a host (`hostfxr`) command, which
   collects no CLI telemetry, so this is only for completeness.
5. **The `%TEMP%` growth known issue is unchanged.** One G3 run left 85 new top-level folders in the real `%TEMP%`:
   - 62 `TemporaryDirectory.*` folders from swift-corelibs;
   - 23 named fixtures:
     - 3 `agenthud 引擎 *` from M4's `ProviderEnginesWindowsTests`;
     - 9 `agenthud-engine-*` from the upstream `ClaudeEngineTests`, `ClaudeProviderTests` and `UsageInsightsTests`;
     - other upstream `agenthud-*` fixtures.

   None comes from M6's tests. PROGRESS already records this for M9.
6. **NuGet sources.** The restore's sources were nuget.org and this machine's Visual Studio offline folder
   (`C:\Program Files (x86)\Microsoft SDKs\NuGetPackages\`). That folder comes from the machine's NuGet configuration,
   not the repository. CI restored from nuget.org.

## Skipped tests

| Kind | Count | Registered |
| --- | --- | --- |
| Excluded files (`windowsSkippedTests`) | 7 files | yes, §1; the six replaced sources are unchanged from `c258093` |
| Skip list (`skipped-tests.txt`) | 34 unique tests | yes, §2: unchanged from M5, none ran on Windows, all 34 pass on macOS (39113715915) |
| Runtime skips (`XCTSkip`), local | 4: `AdditionalProviderTests.testInstalledSourcesReadOnlyProbe`, `AntigravityPermissionsTests.testInstalledAntigravityPermissionsReadOnlyProbe`, `GrokAccountLinkTests.testInstalledConfirmedAccountCacheProbe`, `SessionUsageProbeTests.testReportedSessionsUsageProbe` | yes, §3 |
| Conditional runtime skips (no `node.exe`/`git.exe`/8.3 names/PowerShell/Git Bash) | 0 triggered | yes, §3 |
| New M6 tests skipped | 0 (Swift 11, C# 7) | n/a; the SKIPPED_TESTS.md state line ("1441 pass, 4 runtime skips, 34 listed skips, 7 excluded files, 0 failures"; C# "7 pass, none skipped") matches the local run |
| CI runtime skips | not available: the Windows Swift tests did not run | — |

## Verdict summary

| Gate | Verdict |
| --- | --- |
| G1 | PASS (run 39113715915, attempt 1, success; 2087 XCTest / 8 skipped / 0 failures, 10 swift-testing) |
| G2 | PASS locally (Swift 195 s, baseline warnings only; .NET 0 warnings); CI not run (skipped after G5) |
| G3 | PASS locally (1445 / 1441 / 4 skipped / 0 failed); CI not run |
| G4 | PASS (macOS CI, Windows local); Windows CI not run |
| G5 | **FAIL** (CI: 0/7 C# tests, fixtures checked out CR LF; local 7/7 and 16+15 fixtures; failure reproduced locally with `autocrlf=true`) |
| G6 | PASS (local and CI) |
| M6 (a) | local 11/11 Swift + 7/7 C#; **CI: Swift not run, C# 0/7** |
| M6 (b) | PASS (rewritten fixtures byte-identical in a scratch clone) |
| M6 (c) | PASS (all stdout lines are `"v":1` protocol and schema-valid; stderr empty; exit 0 on end of input and on `quit`) |
| M6 (d) | PASS (no telemetry setting persisted; allowlist holds for the tree; 2 bypasses noted) |
| M6 (e) | PASS |
| M6 (f) | PASS |
| G7 | observations only |
| G8 | 6 non-blocking notes |

BLOCKING findings: 1. The protocol fixtures have no line-end attribute, so the Windows runner checks them out as CR LF
and G5 fails in CI (0/7). The rest of the Windows job, the CI half of G2, G3 and G4, did not run for `80fb737`.

TESTS: FAILURES
