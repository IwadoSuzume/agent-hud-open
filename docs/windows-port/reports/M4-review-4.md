# M4 review, round 4

- Reviewer: port-reviewer (general-purpose agent following `.claude/agents/port-reviewer.md`, D-017), 2026-10-18,
  read-only: git and grep only, no builds or tests, nothing written.
- Range: `git diff 469bc44...4cdf931` (head `4cdf931`). CI on the head: Windows run 39047601254 success, macOS
  `Source checks` run 39047601576 success.
- Verdict: **CHANGES_REQUESTED** — every BLOCKING item of rounds 1–3 is fixed; 2 new BLOCKING items (two Windows
  implementations M4 owns have no test). Round 4 is the last round TASK.md §5.5 allows: both go to BLOCKERS.md.

## Findings

[BLOCKING] Sources/AgentHUDCore/Platform/Windows/ProviderHTTP+Windows.swift:34 — `WindowsHTTP.send`, the WinHTTP
transport every Windows quota request goes through (D-014), has no Windows test. PORTING_PLAN.md:73 makes M4 finish and
test it (D-030 deferred it from M3). The only test touching the file is `PlatformGapsTests.testAHeaderWithALineBreakIsRecognised`
(`breaksLine` only); every provider test replaces the transport with its own `ProviderHTTP.send`. None of its rules is
tested on Windows: no redirects, no cookies or WinHTTP auth, fail closed when an option cannot be set, self-signed
certificates for 127.0.0.1 only, the 16 MB body limit, the timeout watchdog. SUPPORT_MATRIX's ✅ for the Quota column is
therefore not true of the transport (checklist 7, G3). — Fix: `WindowsSupport/ProviderHTTPWindowsTests` with a Winsock
HTTP/1.1 host on 127.0.0.1: a 200 returns its body and the request's headers reach the host; a 302 to a second loopback
host gives `ProviderHTTPError(status: 302)` and the second host gets no connection; after `Set-Cookie` the next request
has no `Cookie`; a body over `WindowsHTTP.bodyLimit` gives `ProviderFailure.limit`; a silent host with timeout 1 gives
`URLError(.timedOut)` within about 2 s; a non-http scheme gives `ProviderFailure.format`.

[BLOCKING] Sources/AgentHUDCore/Platform/Windows/WindowsCredentials.swift:13 — `WindowsCredentials.genericSecret` /
`CopilotCredentials.genericPassword` (Credential Manager `CredReadW`, target `gh:github.com:`) has no test anywhere
(PORTING_PLAN.md:74, checklist 7). — Fix: `WindowsSupport/WindowsCredentialsTests`: a unique target
`agenthud-test-<UUID>:` reads nil while absent; `CredWriteW` a fixture generic credential with a fake UTF-8 secret
(non-ASCII too), read it back through `CopilotCredentials.genericPassword(service:)`, `CredDeleteW` it in teardown;
never read `gh:` targets. If writing a temporary credential is judged unacceptable, record that in DECISIONS.md and mark
the path untested in SUPPORT_MATRIX.

[NON_BLOCKING] docs/windows-port/PROGRESS.md:7,22 — status line and M4 row still say "review (round 2)".

[NON_BLOCKING] Tests/AgentHUDCoreTests/WindowsSupport/ProviderPathsWindowsTests.swift:137 —
`DeepSeekCredentialLocator.module(home:)` reads `roamingAppData\npm\node_modules` and `localAppData\npm-cache\_npx`,
redirected only under test.ps1; a bare `swift test` with dsh installed globally would read the real profile. — Make the
two roots injectable, like `WindowsCodex.engines(appData:)`.

[NON_BLOCKING] Sources/AgentHUDCore/Hooks/ClaudeSessionOrigins.swift:53, Hooks/Permission/ClaudeHeadlessRuns.swift:22 —
on Windows the candidates are spelled without `.exe`, so a running `claude.exe` ancestor never matches. — M5 (hook
ancestry): resolve them through `WindowsExecutables.program` before comparing.

[NON_BLOCKING] Sources/AgentHUDCore/Platform/Windows/Win32.swift:136 — D-035 relies on case-insensitive lookup; no test.
— `XCTAssertEqual(Win32.environment("systemroot"), Win32.environment("SystemRoot"))`.

[NON_BLOCKING] Sources/AgentHUDCore/Providers/Kit/ProviderData.swift:51 — on Windows `AdditionalSource.cursor.isInstalled(home:)`
ignores `home` and checks the real roaming `CursorClient.defaultDatabase`. — Take the database URL as a parameter.

[NON_BLOCKING] Sources/AgentHUDCore/Hooks/Permission/PermissionHooks.swift:153 — Qoder, Qoder CN and QoderWork are
detected on Windows by `~/.qoder*`, which has no source yet; gate them before a hook installer can reach them (M5).

[NON_BLOCKING] Tests/AgentHUDCoreTests/WindowsSupport/WindowsExecutablesTests.swift:67 — the test changes the
process-wide current directory; safe with serial XCTest and the restore is asserted. Acceptable.

## Earlier BLOCKING items

- Round 1: PlatformSupport gates everywhere Core touches an absent client (layout, quota, permission-hook presence,
  WorkBuddy `models.json`, Antigravity process listing) — fixed; macOS-only home folders gated or compiled out — fixed;
  the D-019 test can fail — fixed; the four unsourced Windows places cited or marked — fixed.
- Round 2: driveless-path test on CI's `D:` — fixed (run 39047601254 green); 8 unnamed skip-list entries — fixed (31
  named); counterparts that test the gates — fixed.
- Round 3: the Grok Bot quota check can fail — fixed (fixture clock; traced: without the gate the cached bot quota is
  returned and `XCTFail` fires); the routine-run check can fail too.

## Rest of the checklist

macOS behaviour unchanged (every shared change is a `#if os(Windows)` branch or a PlatformSupport check that is always
true on macOS); D-006 files not in the diff; no shell strings, no new dependency, THIRD_PARTY_NOTICES untouched;
SUPPORT_MATRIX's Executables table and D-034…D-036 match the code.

VERDICT: CHANGES_REQUESTED
