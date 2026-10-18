# M5 review, round 1

- Reviewer: port-reviewer (general-purpose agent following `.claude/agents/port-reviewer.md`, D-017), 2026-10-18,
  read-only: git, grep and file reads, no builds or tests, nothing written.
- Range: `git diff 505492b...c369f8d` (46 files).
- Verdict: **CHANGES_REQUESTED** — 1 BLOCKING, 11 NON_BLOCKING. B-001: resolved (closable with M5's approval).

## Findings

[BLOCKING] Sources/AgentHUDCore/Platform/Windows/HookSettings+Windows.swift:19-31 — when `ReplaceFileW` fails the
staged file is deleted. With no backup name, `ERROR_UNABLE_TO_MOVE_REPLACEMENT` (1176) leaves "the replaced file no
longer exists and the replacement file exists under its original name", and `ERROR_UNABLE_TO_MOVE_REPLACEMENT_2`
(1177) leaves the original under another name: deleting the staged file can destroy the user's settings (G7). — Pass a
backup name in the same folder, restore on any failure where the target is gone, never delete the only copy, delete
the backup only once the target is in place; put the error branch behind a seam to test it.

[NON_BLOCKING] Platform/Windows/WindowsWebSocket.swift:41-52,85-112 — `cancel()` closes the request or socket from
another thread; the run thread can make one more call (`WinHttpSetOption`, `QueryHeaders`, `CompleteUpgrade`, the next
receive) on the closed handle, which WinHTTP may have reused. Same pattern as M4's accepted Watchdog. — Close only on
the owning thread or recheck `cancelled` under the lock before each call; note the residual race in D-040.

[NON_BLOCKING] DECISIONS.md D-037, SUPPORT_MATRIX.md:8 — Claude Code *Hooks*, *Copilot CLI hooks reference* and
CodeBuddy *Hooks reference* are cited by title only; the CodeBuddy `bash -c <line>` invocation is not sourced. — Add
URLs, retrieval date and the quoted field names.

[NON_BLOCKING] HookFormsWindowsTests.swift:353,369; MCPAppChannelTests.swift:217 — two runtime skips (no Windows
PowerShell; Git for Windows not on PATH) and one in-test `#if !os(Windows)` case are not in SKIPPED_TESTS.md. — Add
rows.

[NON_BLOCKING] SKIPPED_TESTS.md:49-50 — a literal line break splits the MCPToolsOffTests row. — Rewrite it.

[NON_BLOCKING] Platform/Windows/HookCommand+Windows.swift:193-201 — the zip-copy check compares against `TEMP`/`TMP` as
spelled; an 8.3 `TEMP` with a long engine path is not seen as transient. — Compare `GetLongPathNameW` forms; test with
a short-name temporary folder.

[NON_BLOCKING] ProviderHTTPWindowsTests.swift:82-102 — the cookie test cannot fail without `WINHTTP_DISABLE_COOKIES`
(a session per request) and the authentication test very likely passes without `WINHTTP_DISABLE_AUTHENTICATION`; the
certificate rule and fail-closed remain untested. — Extract the option decision into a pure function and test it,
including no ignored certificate errors off 127.0.0.1; say in D-039 that per-request sessions hold the cookie rule.

[NON_BLOCKING] SUPPORT_MATRIX.md:61 (footnote 10) — a headless npm `claude -p` run's request is held until the HUD's
hold time (600 s), not "the client's own limit"; on macOS such runs are let go at once. — Correct the wording;
consider matching `node.exe` plus `cli.js`.

[NON_BLOCKING] ProviderPathsWindowsTests.swift:138 — DeepSeek's npm roots were not made injectable; the assertion was
weakened instead and a bare `swift test` reads the real `%APPDATA%\npm`. — Inject the roots and restore `XCTAssertNil`.

[NON_BLOCKING] ClaudeSessionOriginsTests.swift:146 and others — on macOS the shared tests now take `HookCommand.make`
as the expected value, so they no longer pin POSIX quoting; nothing checks the `'\''` case. — Keep one macOS literal
test of `make` with an apostrophe.

[NON_BLOCKING] HookFormsWindowsTests.swift:160,166 — after `configure(enabled: false)` the file's absence is not
asserted. — Add it.

[NON_BLOCKING] HookSettings+Windows.swift:15-26 — `ReplaceFileW`/`MoveFileExW` get paths without `\\?\`; a settings
path over MAX_PATH fails unless the process is long-path aware. — Prefix long paths or record the limit.

## Checked and fine

macOS unchanged (every shared change a minimal `#if os(Windows)` or a seam whose Darwin side is the original code;
macOS manifest untouched; D-006 files not in the diff); Core runs no shell; quoting matches each client's shell with
space, CJK, `'` and `&`, and `%`, `!`, `"`, typographic quotes and control characters are refused; the installer keeps
other hooks, refuses unknown layouts, never creates a file on removal, keeps the DACL through links; the watchdog bounds
only the part before the wait, the 600 s hold is unchanged and the HUD never answers for the user; the WebSocket is
loopback-only with its limits and its quiet-stream rule tested; `--mcp` binary mode tested end to end; SUPPORT_MATRIX's
Approvals/Completion columns match the code; the 34 skip-list entries match SKIPPED_TESTS.

## B-001

Resolved: the real `WindowsHTTP.send` runs against a Winsock host on 127.0.0.1 and the real `CredReadW` against
session-only fixture credentials; no real credential or `gh:` target is read; redirects, the body limit, the timeout,
refused schemes and header names, connection refused, exact-target lookup and non-UTF-8 secrets would each fail their
test if broken.

VERDICT: CHANGES_REQUESTED
