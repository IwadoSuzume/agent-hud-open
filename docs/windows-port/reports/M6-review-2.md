# M6 review, round 2 (port-reviewer)

Range: `git diff 0f51d89...9d00cc2`, with a close read of `80fb737...HEAD`. The review was read-only: I built nothing, ran no tests and wrote nothing. The root and bundled `THIRD_PARTY_NOTICES.txt` are byte-identical (`cmp`).

## Round-1 BLOCKING items

1. **Hooks and hold time re-applied on every 10 s tick: resolved.**
   - `EngineServer.swift:134-189` replaces the single `observe()` with per-value `track` helpers. They copy macOS `trackChanges` and its `Equatable` variant: the first value is read at arm time, the watch re-arms inside the same main-actor task, and a change of A→B→A before the task runs does nothing, as on macOS.
   - `approvalWaitMinutes` sets `holdTime` only when it changes, so the `didSet` rescheduling no longer runs per tick.
   - `clientHooks` calls `configure` and the DeepSeek observer only when it flips.
   - `installObserversForNewClients` runs on a new report (`:161-166`), the same as macOS.
   - Events run only when the report, the agents or `disabledLiveStatusSources` change (`:156`).
   - After `stop` nothing re-arms (`:170`, `:173`).
   - Language change: `SettingsStore.update` has already called `L10n.setLanguage` before the observed write, so the call at `:144` is redundant but harmless. `hello` is queued at once and the new-language `state` follows at least 100 ms later. A queued old `state` is replaced and moves behind the new `hello`. The order is correct.
   - The real-engine end-to-end test checks: hook set at start, kept out through a tick and an unrelated setting, set again on a flip.
2. **Labels not Core's own rules: resolved.**
   - `resetText` now comes from `AgentRow.resetLabel(now:)`, `phaseText` from `UsageStore.sessionStatusLabel`, and `project` from `SessionProject(...).title`.
   - The fixture time zone is pinned to UTC in `ShellProtocolTests.setUp`.
   - The state fixture shows "Needs approval", and both the C# and Swift tests assert it.
   - `state`/`panel` are `@MainActor`, and `store.view` is cached, so the per-session `sessionStatusLabel` calls do not rebuild the view.
3. **Protocol writes blocking the main actor: resolved.**
   - `ProtocolWriter` (`EngineServe.swift:131-198`) writes on its own thread. All of its state is behind the `NSCondition` lock, and `FlushFileBuffers` is gone from the protocol path.
   - Coalescing never moves a `state` earlier: the replacement is appended at the end, so `hello` and `event` lines queued before it stay before it. That is acceptable, and better for a language change.
   - The queue holds at most one replaceable line, so when it overflows a non-`state` line is always available to drop.
   - `drain` waits until the queue is empty and nothing is being written, or until the shell is gone or 2 s pass. `lock-held` is therefore written before status 3.
   - The `_dup2` path fails closed: descriptor 1 goes to stderr, otherwise to NUL, otherwise the engine exits 2. The kept handle stays open until exit, and the inherited handle is closed by `_dup2`.
   - The never-read test is meaningful because the 14 kB demo `state` is larger than an anonymous pipe's buffer.
4. **Round-1 tests BLOCKING (fixtures CR LF on the runner): resolved.**
   - `.gitattributes` sets `windows/protocol/** -text`.
   - The Swift, C# and Python readers all now refuse a CR.

## Entries

- [BLOCKING] `Tests/AgentHUDCoreTests/WindowsSupport/EngineServeEndToEndTests.swift:128-131` — The test only replaces `USERPROFILE` before starting a **non-demo** engine (and the hook child). Every other client-home variable is inherited: `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `COPILOT_HOME`, `QWEN_HOME`, `CODEBUDDY_CONFIG_DIR`, `DSH_HOME`, `GEMINI_CLI_HOME`, `XDG_CONFIG_HOME`, `GH_CONFIG_DIR`, and the others read through `ClientHome.variable`. `PermissionHooks.Source.home(_:)` (`PermissionHooks.swift:118-125`) and `SessionObservers.configure` follow these variables even when a home is given. On a machine where any of them is set, the engine therefore installs hooks pointing at the build's `agenthud-engine.exe` into the real client configuration, removes them, installs them again, and leaves them installed at `quit`. This breaks TASK.md §8 ("all tests involving these directories override the environment variables with temporary directories") and G7. `APPDATA`/`LOCALAPPDATA` also come only from the gate (D-021). Run as a plain `swift test --filter`, the test would write the real `settings.json` (`hoverDelayMs`, `clientHooks`), claim the real instance lock and open the real ledger. M5's end-to-end test passed `home:` explicitly; this is the first test that hands the whole environment to a non-demo engine. — Fix: build the child environment from a small allowlist (`SystemRoot`, `PATH`, `TEMP`/`TMP`, `USERNAME`…). Point `USERPROFILE`, `APPDATA` and `LOCALAPPDATA` at subfolders of `home`, and remove every `ClientHome.variable` name, ideally from one list Core exposes for tests. Optionally assert that no variable in the child points outside `home`.
- [NON_BLOCKING] `Sources/AgentHUDCore/Platform/Windows/Shell/EngineServe.swift:153` — Under a stall, the 256 bound drops the oldest non-`state` line, which can be a language-change `hello` (the shell keeps old strings next to a new-language `state`) or a quota alert. PROTOCOL.md does not say a `hello` can be lost. — Fix: make `hello` replaceable within its own kind and drop `error` lines first, or document it.
- [NON_BLOCKING] `Sources/AgentHUDCore/Platform/Windows/Shell/EngineServer.swift:25-31` — The `Hooks` seam is public and its comment says "a test counts them", but no test uses it. `holdTime` being set only on change, and `installObserversForNewClients`, have no test. — Fix: add an in-process `EngineServer` test with counting `Hooks` (configure once at start, not on a tick or unrelated setting, once per flip; `installObservers` only for a new client), or remove the seam and its comment.
- [NON_BLOCKING] `Sources/AgentHUDCore/Platform/Windows/Shell/EngineServer.swift:101-104` — The `hello` before `lock-held` is sent before `options.language` is applied, so with `--language zh` on an English system it carries English strings. — Fix: apply `options.language` (`L10n.setLanguage`) before the lock check.
- [NON_BLOCKING] `Sources/AgentHUDCore/Platform/Windows/Shell/ShellProtocol.swift:107` — `SessionProject(live)` runs for every session on every `state` (at least every 10 s, up to 10/s), on the main actor. Each call walks the folder chain, reads `.git` pointers and, on Windows, calls `finalPath`. On a slow, OneDrive or network folder with many sessions this delays the main actor, which also takes hook requests. — Fix: memoise by `workingDirectory` per report generation.
- [NON_BLOCKING] `Sources/AgentHUDCore/Platform/Windows/Shell/ShellProtocol.swift:117`, `docs/windows-port/PROTOCOL.md:78-82` — PROTOCOL says every `…Text` follows "the rules the macOS panel uses". But:
  - `tokensText` is `TokenFormat.inOut`, while the panel row shows `TokenFormat.short(in+out) + " tok"`.
  - The panel title (`HoverPanelView.sessionTitle`: short task · terminal) has no field, so the shell cannot show it without rebuilding a Desktop rule.
  - On Windows, weekday/time resets are formatted in GMT (PROGRESS known issue, deferred to M7) although the engine already ships them.
  - Fix: name which macOS surface each text mirrors. Add a Core-made `title`, or record its omission in D-043. Set `NSTimeZone.default` from the Windows zone in `EngineServe.run` now, or state the GMT limitation in PROTOCOL.md/D-043.
- [NON_BLOCKING] `docs/windows-port/DECISIONS.md:50-57` — The D-043 table row is split across 8 physical lines (round-2 insertion after "live-status"). Markdown ends the row there: the rest, including the Reason cell, renders as a stray paragraph with pipes (G8). — Fix: join the row onto one line.
- [NON_BLOCKING] `Tests/AgentHUDCoreTests/WindowsSupport/EngineServeEndToEndTests.swift:175-176` — `readDataToEndOfFile()` and `waitUntilExit()` on the hook have no bound of their own. A regression would hang the test until the engine's 10-minute hold time. — Fix: wait with a deadline and terminate, as `Served.exitStatus` does.
- [NON_BLOCKING] `scripts/check-source-boundaries.py:118-140` — A project can still add feeds outside `windows/nuget.config` through the `RestoreSources`, `RestoreAdditionalProjectSources` or `RestoreConfigFile` properties, or a `Directory.Build.rsp`. — Fix: refuse those properties and `*.rsp` files under `windows/`.
- [NON_BLOCKING] `windows/protocol/fixtures/engine-state.demo.json` — Still missing an `unverified` session, a session `message`, a "Pending update" or "Live status off" label (round-1 item, partly done: question, plan and both events were added). — Fix: add a store case for these in `testTheStateIsTheSharedFixture`.
- [NON_BLOCKING] `docs/windows-port/DECISIONS.md` D-042 — It still does not say that `dotnet test` run outside `test-dotnet.ps1` or CI is not opted out of telemetry (round-1 item). — Fix: one sentence.

## Checked and fine

- **Watches:** `track` is equivalent to macOS `trackChanges`, with no lost or duplicated reactions; the two watches on `store.report` are separate, as on macOS.
- **Events:** sent only on report, agents or `disabledLiveStatusSources` changes, guarded by paused/`lastError` as on macOS.
- **Reader:** an over-limit line is now dropped up to its end and answered with the right error.
- **C# side:**
  - `Parse` maps `Overflow`/`Argument`/`InvalidOperation`/`Format` exceptions to `ProtocolRejectedException`.
  - It reads the shared envelope-invalid fixtures.
  - The event and question/plan fixtures and the schema for `resetCredits.provider`/`accountLabel` agree.
- **Boundary check:** `Version` given as an element, `Update`, `.props`/`.targets`, SDK attributes and `<Sdk>`/`<Import Sdk>`, `PackageVersion`/`GlobalPackageReference`/`PackageDownload`, `packages.config`, and an exact `windows/nuget.config` (CR LF tolerated) are all handled, and all fail closed.
- **Telemetry and fixtures:** telemetry is off job-wide in `windows.yml`; `.gitattributes` scopes only `windows/protocol/**`.
- **End-to-end tests:**
  - The real-approval test does run hook → engine pipe → `state` → `answer` → hook output `allow` with status 0.
  - The first `hooked()` check is deterministic: `configure` runs before the first `state` is sent.
  - The 11 s sleep crosses one tick; the test is slow but not flaky.
  - The never-read test does tell the two designs apart.
- **Docs:**
  - PROTOCOL.md matches the writer (replaceable `state`, 256 bound, 2 s drain, `lock-held` before 3) and the reader.
  - D-041 and D-043 describe the code, apart from the broken table row.
  - PROGRESS and SKIPPED_TESTS counts add up: 1445 + 4 = 1449, 9 + 6 new Swift tests, 10 C# tests.
- **macOS:** it sees only the notices, `.gitignore`, `.gitattributes` and the boundary script. `AgentHUDEngine` exists only in the Windows manifest.

VERDICT: CHANGES_REQUESTED
