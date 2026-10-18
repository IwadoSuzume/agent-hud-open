# M6 review, round 3 (port-reviewer)

**Scope.** I reviewed all of `git diff 0f51d89...f531b63` and read the round-3 commit (`9d00cc2...HEAD`) line by line. Before the diff I read TASK.md §4–8, PROGRESS, DECISIONS, PORTING_PLAN and the architecture Rules and invariants. The review was read-only: I built nothing, ran no tests and wrote no files. The root and bundled `THIRD_PARTY_NOTICES.txt` are byte-identical (`cmp`).

## Round-2 BLOCKING item

**The real-engine end-to-end test inherited client-home variables and the real APPDATA/LOCALAPPDATA: resolved.**
- `isolatedEnvironment` (`EngineServeEndToEndTests.swift:85-106`) builds the child environment from an allowlist of system variables. `USERPROFILE`, `HOME`, `APPDATA` and `LOCALAPPDATA` point inside `home`, and the folders are created.
- That matters because `WindowsFolders.folder` only takes the variable when the folder exists. Otherwise it falls back to the known folder.
- No `ClientHome.variable` name gets through, because the list allows rather than removes: `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `XDG_*`, `GH_CONFIG_DIR`, `DSH_HOME` and the rest are all absent.
- So everything the engine and the hook resolve lands in `home`:
  - `UserHome.directory`
  - `PermissionHooks.Source.home`
  - `SessionObservers`' client folders
  - `settings.json`, the ledger, `InstanceLock.sharedURL` and the pipe key
- I also checked the paths that do not go through the environment:
  - The Copilot Credential Manager read is gated by `readCopilotQuota`, which defaults to false in the fresh settings.
  - DeepSeek process discovery is gated by `DeepSeekLocator.isInstalled` under the isolated home.
  - `codex app-server` is given `CODEX_HOME` from the isolated home.
  - `ANTHROPIC_*` and `GH_TOKEN` are not passed through.
- The hook child gets the same environment.
- The bounded wait (`:201-203`) leaves no process behind. On timeout the hook is terminated and the defers terminate the engine. On success the output is read only after the hook has exited.

## Round-2 CI failure and round-3 local G3 failure

- **`HookFormsWindowsTests.testTheLongFormOfAPathBeyondMaxPath` under `RUNNER~1`: resolved.** The base is now expanded with `GetLongPathNameW`, so `long` is long throughout and `GetShortPathNameW` gives the short form throughout. The test still tests both directions. It skips only on a volume without 8.3 names, as before.
- **The 4 tests that failed once the build folder sat behind a junction (D-044): resolved.**
  - `runningApplication` keeps the string comparison as a fast path and falls back to `WindowsPaths.finalPath` on both sides.
  - Cost: two handle opens, and only on a mismatch (`--mcp` asks once).
  - G7: both paths come from the system or from the user-only lock record. I see no spoofing or privacy concern.
  - Hard links stay distinct, which is the conservative choice.
  - `testAHolderNamedThroughAJunctionCountsAsRunning` cannot pass vacuously: `:89` asserts that the spelling written differs from the image name, so the string comparison alone would fail.
  - Teardown order is guaranteed: `defer` runs first, and teardown blocks run last in, first out, so the unlink comes before the folder removal. Only the unlink's own success is unchecked (see the entry below).

## Entries

- [NON_BLOCKING] `Tests/AgentHUDCoreTests/WindowsSupport/EngineServeEndToEndTests.swift:86-88` — `PATH` comes over whole, and it is needed for the Swift runtime DLLs. The test creates `home\.claude`, so Claude counts as installed, and the engine's account step can run the machine's real `claude` (`ClaudeEngineUsageClient`: `auth status`, `-p … get_usage`) or `codex app-server` from the user's PATH. It runs inside the isolated home, so no real sign-in is reachable. But a test still starts installed clients, which the invariant "the only probe that touches installed clients is opt-in" reserves for the opt-in probe. — Fix: reduce PATH to `%SystemRoot%\System32` plus the folder(s) that hold `swiftCore.dll`.
- [NON_BLOCKING] `Tests/AgentHUDCoreTests/WindowsSupport/EngineServeEndToEndTests.swift:100-104` — the "would reach the real profile" assertion cannot fail. Every value it checks is either an allowlisted system variable or built from `native`, and `PATH`/`TEMP`/`TMP` are exempt. It also compares against the parent's `USERPROFILE`, which under G3 (D-021) is already the gate's temporary profile, not the real one. — Fix: assert that the keys are a subset of the allowlist plus the four profile variables, or drop the assertion and keep the comment.
- [NON_BLOCKING] `Tests/AgentHUDCoreTests/WindowsSupport/EngineServeEndToEndTests.swift:109, 240, 250, 271` — the demo, lock-held and input-end engines still inherit the whole environment. They rely on the gate's D-021 profile: run as a plain `swift test`, the demo writes `settings.demo.json` (language zh-Hans) into the real `%APPDATA%`, and the lock test takes the real `%LOCALAPPDATA%` lock. — Fix: pass `isolatedEnvironment` to these engines too (the lock test then claims the lock under the child's `LOCALAPPDATA`).
- [NON_BLOCKING] `Sources/AgentHUDCore/Platform/Windows/Shell/EngineServe.swift:154` — a replaced `hello` moves to the end of the queue. If the first `hello` is still queued when a language change arrives, the queue becomes `[state1, hello2]`. The shell then reads a `state` before any `hello`, which breaks PROTOCOL.md step 1 ("answers hello, then … its first state"). This is a narrow race: the writer thread must not yet have taken the first line, or must be stuck behind an earlier `error`. The drop rule removes the oldest line that is neither `state` nor `hello`, which includes `lock-held`, while PROTOCOL.md:41-43 says "the oldest `event`"; in practice `lock-held` cannot overflow. Otherwise the ordering is sound: at most one of each replaceable kind is queued, so something droppable always exists, and losing an `error` first is the right priority. — Fix: replace a queued `hello` in place (keep its index); `state` may keep moving to the end. Write "the oldest other line (an `event`)" in PROTOCOL.md.
- [NON_BLOCKING] `Sources/AgentHUDCore/Platform/Windows/Shell/EngineServe.swift:150-161`, `Sources/AgentHUDCore/Platform/Windows/Shell/ShellProtocol.swift:108-119` — neither the writer's new policy (hello replaceable, error dropped first, the 256 bound) nor the `projectTitle` memo has a test of its own; the only coverage is indirect (the never-read test, fixture equality). The memo itself is correct: `SessionProject` depends only on `workingDirectory`; nil and empty both map to unassigned, with no localised title; the `String??` lookup caches nil correctly; it is reset per `generatedAt`, so it grows by at most the session count and its staleness lasts at most one report; main-actor static state is fine under Swift 6. — Fix: add a `ProtocolWriter` test over an anonymous pipe with a stalled reader, and a memo test (the same report gives no second walk, a new `generatedAt` recomputes).
- [NON_BLOCKING] `Tests/AgentHUDCoreTests/WindowsSupport/InstanceLockWindowsTests.swift:85` — `RemoveDirectoryW`'s result is ignored. If unlinking ever failed, the `directory()` teardown's `FileManager.removeItem` would run with the junction still in the folder. Whether swift-corelibs then recurses through the junction into the build folder is not established here. — Fix: `XCTAssertTrue` the unlink, and have the folder teardown skip removal while `link` still exists (or delete only the lock file).
- [NON_BLOCKING] `Tests/AgentHUDCoreTests/WindowsSupport/InstanceLockWindowsTests.swift:77` — `cmd /d /c mklink …` is an argument array, but `cmd` parses the command line again. The link path is quoted, because it contains a space. The build-folder target is quoted only if it contains a space, so a path with `&`, `^` or `%VAR%` would be interpreted by cmd (G7: no shell strings). It is test-only and the paths are unlikely, but it does not follow the letter of G7. — Fix: create the junction with `DeviceIoControl(FSCTL_SET_REPARSE_POINT)`, or refuse a target containing `&|^%<>` before calling cmd.
- [NON_BLOCKING] `Tests/AgentHUDCoreTests/WindowsSupport/HookFormsWindowsTests.swift:243` — `XCTAssertNotEqual(baseWritten, 0)` does not stop the test. On failure `folder` becomes `URL(fileURLWithPath: "")`, which is the working directory, and the test creates a 300-character `深层 …` folder tree there that teardown never removes. — Fix: `guard baseWritten > 0 else { return XCTFail(...) }`.
- [NON_BLOCKING] `Tests/AgentHUDCoreTests/WindowsSupport/WindowsProcessesTests.swift:17` — comparing by final path no longer checks that `imagePath` writes forward slashes, the format its doc promises and that `HookProcessOrigins`/`proc_pidpath` rely on. `finalPath` normalises the slashes, so a regression would pass. — Fix: add `XCTAssertFalse(image.contains("\\"))`.
- [NON_BLOCKING] `windows/AgentHUD.Protocol.Tests/ProtocolTests.cs:157` — the C# test of `engine-state.later.json` does not check the `unverified` phase it was added for. — Fix: `Assert.IsTrue(state.Panel.Sessions.Any(s => s.Phase == SessionPhase.Unverified && s.PhaseText == "Status out of date"))`.

## Checked and fine

- **`EngineServer.start`:** `--language` is applied before the lock check, so `lock-held`'s `hello` is in the requested language. Without the option it uses the system language, as macOS's single-instance alert does (it comes before preferences are opened).
- **`Hooks` seam:** removed cleanly. There are no references in `Sources`, `Tests` or the docs, and the `send` signature `(Data, String)` matches its only caller in `EngineServe.swift:72`.
- **Fixtures and boundary check:** `engine-state.later.json` was generated by the Swift test (`now` = `generatedAt` + 8 days, UTC). It holds "Pending update", "Live status off" and an `unverified` session. The schema allows `unverified`, `check-protocol.py` globs it, and both sides read it. The boundary check refuses `.rsp` files repo-wide (none exist) and the six `Restore*` properties in every MSBuild file. It still runs on macOS without effect there.
- **Docs (G8):** D-042 now names the telemetry gap. D-043 is one row and records the session title, the token text and GMT. D-044 matches the code and tests. PROTOCOL.md matches the writer, apart from the "event" wording above. The counts add up: 1449 + 2 = 1451 executed (1447 passed + 4 skipped), and 10 + 1 = 11 C# tests. SKIPPED_TESTS needs no new exclusion. PROGRESS records the unfiled round-2 tester report and the CI failure honestly.
- **macOS:** it still sees only the notices, `.gitignore`, `.gitattributes` and the boundary script. `AgentHUDEngine` exists only under `#if os(Windows)` in `Package.swift`. Nothing in round 3 touches shared Core files.
- **Core rules:** no business logic in C#, and no new dependency.

VERDICT: APPROVE
