# M6 review, round 1

- Reviewer: port-reviewer (general-purpose agent following `.claude/agents/port-reviewer.md`, D-017), 2026-10-18,
  read-only: no builds or tests, nothing written.
- Range: `git diff 0f51d89...80fb737`.
- Verdict: **CHANGES_REQUESTED** — 3 BLOCKING, 17 NON_BLOCKING. All nine M5 round-2 items: fixed.

## BLOCKING

1. `Platform/Windows/Shell/EngineServer.swift:121-152` — `observe()` tracked `store.view`, which reads `store.now`
   (every 10 s), the waiting approvals and the settings; every pass, approval change and tick ran `settingsChanged()`:
   `SessionObservers.configure` again (reading every client's settings file, putting back a handler the user removed,
   rewriting the Pi/OpenCode observers) and `holdTime` again (another expiry timer per pending request). macOS acts on
   each only when its own setting changes. — Keep each watched value, act on its change only; add
   `installObserversForNewClients`; test that configure runs at start and per flip only.
2. `Platform/Windows/Shell/ShellProtocol.swift:90,104` — `resetText` from `Countdown.resetLabel` instead of
   `AgentRow.resetLabel(now:)` (a passed reset showed "0m" where macOS says "Pending update", another account's row a
   countdown where macOS shows "—", "<1m" lost); `phaseText` from `Countdown.sessionLabel` instead of
   `UsageStore.sessionStatusLabel` (a waiting session showed "1h 06m running" where macOS says "Needs approval"; no
   "Status out of date" or "Live status off"). The shell would have to re-decide these. — Use Core's own rules; pin
   the fixtures' time zone in the test.
3. `Platform/Windows/Shell/EngineServe.swift:124-145` with `PROTOCOL.md:37-38` — `WriteFile` blocked on the main actor
   and `close()` called `FlushFileBuffers` (which waits for the reader): a slow, hung or gone shell stalled the main
   actor — hook connections not taken, approval expiry not firing (a request fell back at the client's own 24 h
   timeout instead of the hold time, G7), `quit` deadlocking against a shell waiting for the exit. PROTOCOL.md promised
   the opposite. — Write on a thread of its own, coalesce `state`, bound the rest, drop `FlushFileBuffers`; test an
   engine whose output is never read.

## NON_BLOCKING

- `EngineServe.swift:42-44` — a failed `_dup2(2, 1)` left descriptor 1 on the protocol pipe (D-022 fails open).
- `EngineServe.swift:69-72` — a line over the limit was answered "not protocol version 1".
- `EngineServer.swift:80-118` — missing from start: `applyLiveStatusDefaults` (its detector is Desktop code),
  `installObserversForNewClients`, launch at login; implement or record in D-043.
- `EngineServer.swift:177-180` — `IslandEventTracker.update` on every state; macOS runs it on a new report, agents or
  `disabledLiveStatusSources` only.
- `ShellProtocol.swift:102` — `project` from `lastPathComponent`; Core's rule is `SessionProject`.
- `ShellProtocol.swift:48-52` — `resetCredits` does not say whose account.
- `ShellProtocol.swift:71-79`, `PROTOCOL.md:68-74` — no balances, account grouping, notices or 24 h token columns;
  record that 1.0 omits them and the shell must not derive them, or add them.
- `ShellProtocol.swift:235-244`, `PROTOCOL.md:101` — unknown keys are refused (undocumented); Core's decoder corrects
  some values instead of refusing (`appearance`, `approvalWaitMinutes`, `glowStyle`); duplicated doc comment.
- `windows/AgentHUD.Protocol/Protocol.cs:75-95` — `OverflowException` and duplicate-key `ArgumentException` escape
  `ProtocolRejectedException`.
- `ProtocolTests.cs:96-107` — the C# side does not read the shared `fixtures/invalid` envelope cases.
- `windows/protocol/fixtures/` — no engine fixture with a question or a plan, a `quotaAlert` or `resetCredits`, the
  `unverified` phase or a session message.
- `scripts/windows/check-protocol.py:21` — `answer-empty-id.json` listed as semantic though the schema expresses it.
- `scripts/check-source-boundaries.py:70-90` — the allowlist misses `Version` before `Include`, `*.props`/`.targets`
  and files outside `windows/`, and SDK packages (`Project Sdk=`, `<Sdk>`); also `PackageVersion`.
- `DECISIONS.md` D-042 — "no feed but nuget.org" while the boundary check forbids the one file that could enforce it.
- `scripts/windows/test-dotnet.ps1`, `.github/workflows/windows.yml` — telemetry off only inside the script; set it
  job-wide and say runs outside it are not opted out.
- `EngineServeEndToEndTests.swift` — no real approval through the protocol (a hook asking a non-demo engine, answered
  by the shell).

## Checked and fine

No business logic in C#; version, type, field kinds and the line limit refused on both sides; partial lines; end of
input and `quit` end with 0 after `PermissionRequests.stop()`; a held lock answered `hello`, `lock-held`, status 3; an
unknown answer id ignored, nothing resolves a request on its own, "Always allow" takes `request.alwaysAllow`; demo
isolation; observation re-arming loses nothing; schema, fixtures, encoder and reader agree; notices complete (15 MIT
packages), both copies byte-identical; macOS sees only the notices, `.gitignore` and the boundary script; ShellStrings
checked against the Desktop's sources.

VERDICT: CHANGES_REQUESTED
