# Blockers

Items a milestone could not finish within four review rounds (TASK.md §5.5), and work the port leaves undone with
no milestone left to own it (M7 review round 1): symptom, what was tried, suggestion.

## B-001 — CLOSED — M4 not approved after four rounds: two Windows implementations without tests (2026-10-18)

- **Symptom.** M4 review round 4 (`reports/M4-review-4.md`, on `4cdf931`) returned CHANGES_REQUESTED with two BLOCKING
  items, both new in that round. (1) `WindowsHTTP.send` (`Platform/Windows/ProviderHTTP+Windows.swift`), the WinHTTP
  transport of every Windows quota request (D-014), has no Windows test: provider tests replace the transport, so none
  of its rules (no redirect, no cookie, no WinHTTP authentication, body limit, timeout, fail closed) runs on Windows.
  (2) `WindowsCredentials.genericSecret` (Credential Manager, Copilot's `gh:github.com:`) has no test. All gates of the
  same round passed (`reports/M4-tests-4.md`: TESTS ALL_PASS; CI runs 39047601254 and 39047601576), and every BLOCKING
  item of rounds 1–3 was confirmed fixed.
- **Tried.** Rounds 1–3 fixed what their reviews found; these two were first raised in round 4, the last TASK.md §5.5
  allows, so M4 gets no `port-M4-approved` tag.
- **What follows.** M5 builds on M4 unchanged (nothing M5 does depends on the two missing tests). Both fixes land at the
  start of M5's range, so M5's review and gates cover them: `WindowsSupport/ProviderHTTPWindowsTests` (a Winsock HTTP
  host on 127.0.0.1; the self-signed certificate rule needs a TLS host and stays untested, noted in the test) and
  `WindowsSupport/WindowsCredentialsTests` (a fixture generic credential under a unique `agenthud-test-…` target, written
  and deleted by the test; `gh:` targets never read). Until M5 is approved, SUPPORT_MATRIX's ✅ in the Quota column
  rests on the provider fixtures, not on a tested Windows transport.
- **Suggestion.** Close this entry when M5 is approved with those tests in its range.
- **Closed 2026-10-18** with M5's approval (`port-M5-approved`, `bb1ce7d`): `ProviderHTTPWindowsTests`,
  `WindowsCredentialsTests` and `WindowsHTTP.rules`' test run in Windows CI and locally (`reports/M5-tests-2.md`), and
  the M5 reviews judged B-001 resolved (`reports/M5-review-1.md`, `M5-review-2.md`).

## B-002 — OPEN — The MCP agent-tools channel is not served on Windows (2026-10-18)

- **Symptom.** `agenthud-engine --mcp` answers every agent tool with "Agent HUD's agent tools are off" while the engine
  holds the lock (D-043). On macOS the Desktop serves the channel: its tools show things on the HUD and measure the
  panel, which only the shell draws on Windows.
- **Tried.** Nothing yet. M7 (the shell) was the planned owner in D-043. M7 round 1's review found it unowned, and
  neither M8 (packaging) nor M9 (wrap-up) is the place for a new protocol direction.
- **Suggestion.** Add a protocol minor version that carries the tool calls from the engine to the shell and their
  results back. The engine keeps the MCP side (Core's `MCPAppChannel`); the shell only draws and measures. Then make
  `--mcp` reach the running engine through its pipe (D-040), and test it with an MCP client fixture as the macOS tests
  do.

## B-003 — OPEN — The panel's session title and row token count are not shown on Windows (2026-10-18)

- **Symptom.** The Desktop's hover panel titles a session with its short task and terminal
  (`HoverPanelView.sessionTitle`), and each agent row shows its in/out token pair (`TokenFormat.inOut`). Protocol 1.4
  carries neither, so the Windows panel shows the project and the row's figures without them (D-043, M6 round 3).
- **Tried.** D-043 named M7 as the owner "when the shell's panel needs them". M7 round 1's review found it unowned.
- **Suggestion.** Add both to a later minor version: `title` on `panel.sessions[]` and `tokensText` on
  `panel.agents[]`, made by Core's own functions (moved from the Desktop into Core where they are Desktop-only), and
  checked as 1.1's labels are. The shell only binds them.
