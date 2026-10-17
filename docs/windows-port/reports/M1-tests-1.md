# M1 test report, round 1

- Branch: `windows-port`. Head under test: `ffc8dba` ("Windows port M1: the Windows CI skeleton"). Milestone start:
  `703ae2e`. The working tree was clean (no untracked drafts) when the gates ran.
- Diff `703ae2e..ffc8dba` touches 6 files: `.github/workflows/windows.yml` (new, 94 lines), `Package.swift` (+15/-0),
  DECISIONS.md, PORTING_PLAN.md, PROGRESS.md and ADR-001. It does not change `ci.yml`, Sources/, Tests/ or scripts/.
- Run by: port-tester, 2026-10-16, Windows 11 Pro 10.0.26200. This report is the only repository file written; nothing
  was committed or pushed. A first attempt was cut off by a connection error, and its CI polling loop hit transient
  API errors; the results below come from a fresh read of both completed runs.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | PASS |
| G2 Windows build | PASS (CI workflow, plus local `dump-package`) |
| G3 Windows tests | N/A (D-024: Support joins in M2) |
| G4 determinism | N/A (M2+) |
| G5 UI | N/A (M7+) |
| G6 boundaries | PASS |
| G7 security review | review gate; observations below |
| G8 docs | PASS (non-blocking notes) |

### Package.swift: the macOS branch is unchanged

- Command: `git diff 703ae2e ffc8dba -- Package.swift`. It removes **0 lines** and adds 15: an `#if os(Windows)` block
  after `import PackageDescription`, an `#else` before the original `let package = Package(` and an `#endif` at the end.
- Byte check: the text between `#else\n` and `#endif\n` at `ffc8dba` is **byte for byte** the text after the 3-line
  header at `703ae2e` (Python `bytes ==` comparison: True). The file has no CR.
- The Windows branch declares only the product `AgentHUDSupport`, with the targets `AgentHUDSupport` (Swift 6 language
  mode) and `AgentHUDSupportTests`. It has no `platforms`.

### G1: PASS

`Source checks` run **38982141982**: workflow_dispatch, head `ffc8dba`, `completed` / `success` (23:34:23Z to
23:45:09Z). Read with `ghapi.sh GET .../actions/runs/38982141982` and `.../jobs`.

| Job | Runner | Conclusion | Steps |
| --- | --- | --- | --- |
| `test` (117245210458) | macos-15 | success | Check source boundaries success; Test success (23:34:36Z to 23:44:56Z) |
| `app` (117245210657) | macos-15 | success | Build application success; Verify local signature and resources success |
| `macos` (117248101971) | ubuntu-latest | success | Tests and application passed success |

This shows the manifest's `#else` branch still builds and tests the macOS products.

### G2: PASS

**CI.** `Windows port` run **38982139136**: push, head `ffc8dba`, `completed` / `success` (23:34:21Z to 23:37:16Z).
Job `swift` (117245196763), windows-latest, success. Every step concluded `success`:

| # | Step | Time |
| --- | --- | --- |
| 1 | Set up job | 1 s |
| 2 | Run actions/checkout@v7.0.1 | 8 s |
| 3 | Check source boundaries | 3 s |
| 4 | System SQLite version | 6 s |
| 5 | Cache the Swift installer | 1 s (miss) |
| 6 | Download the Swift installer | 8 s |
| 7 | Verify and install Swift | 89 s |
| 8 | Toolchain | 1 s |
| 9 | Resolve the Windows package graph | 9 s |
| 10 | Compile a smoke package | 27 s |
| 19 | Post Cache the Swift installer | 13 s (saved) |
| 20 | Post Run actions/checkout@v7.0.1 | 2 s |
| 21 | Complete job | 0 s |

Key lines from the job log, downloaded from `GET /repos/IwadoSuzume/agent-hud-open/actions/jobs/117245196763/logs`
(HTTP 200 after the redirect, 28,769 bytes):

- `Source boundaries and ignore rules passed.`
- `winsqlite3 3.51.1`
- `Microsoft Windows NT 10.0.26100.0` (the runner image; this machine is 26200)
- `Cache not found for input keys: swift-installer-6.4.1-9382E149...D91D59`, then later
  `Cache saved with key: swift-installer-6.4.1-9382E149...D91D59`
- Verify and install Swift ended with success. Its hash and signature checks would have thrown if they failed, and
  no throw message appears in the log.
- `Swift version 6.4.1 (swift-6.4.1-RELEASE)` / `Target: x86_64-unknown-windows-msvc`
- Smoke package: `Build complete! (23.38 secs)`, then `smoke true`
- Warnings: one compiler warning, the baseline in PROGRESS.md: `WinSDK.swiftmodule ... reference to type 'wchar_t'
  broken by a context change`. No new warnings. Separately, the cache action prints Node deprecation notices
  (`punycode`, `url.parse`); they come from the action, not the port.

**Local.** I ran `swift package dump-package` from `%LOCALAPPDATA%\agenthud-dev\src` (HEAD `ffc8dba`) with the Swift
environment from PROGRESS.md.

- Local toolchain: `Swift version 6.4.1 (swift-6.4.1-RELEASE)`, `Target: x86_64-unknown-windows-msvc`,
  `Build config: +assertions`.
- Exit 0 in about 3 s. The output parses as JSON with `name=AgentHUDOpen`, `products=AgentHUDSupport`,
  `targets=AgentHUDSupport,AgentHUDSupportTests` and no `platforms`.

Not run: `swift build -c release` locally. D-024 says Support joins the build in M2, and the Windows branch is not
expected to compile Support before then (its CryptoKit import is guarded in M2).

### G3, G4, G5: N/A

D-024: Support's build and tests join the Windows workflow in M2 and Core's in M3. G4 starts at M2 and G5 at M7.

### G6: PASS

- Command: `python scripts\check-source-boundaries.py`, run from `%LOCALAPPDATA%\agenthud-dev\src` at `ffc8dba`.
- Output: `Source boundaries and ignore rules passed.`, exit 0, about 1 s.
- The same check passed in CI on windows-latest (Windows port, step 3) and on macOS-15 (Source checks `test`, step 3).

### G7 (observations, for the reviewer)

- `windows.yml` grants `permissions: contents: read`, uses only first-party actions (`actions/checkout@v7.0.1`,
  `actions/cache@v4`) and no third-party setup action, and has no secrets.
- The Swift installer is pinned by SHA-256 and must carry a valid Authenticode signature whose subject matches
  `O=Apple Inc\.`, both checked before it runs (D-025).
- I checked the size in D-025 with a HEAD request to the pinned URL: `Content-Length: 2097955608`, matching
  D-025's 2,097,955,608 bytes. The hash itself is checked in CI (step 7 succeeded).
- `actions/cache@v4` is pinned to a major tag, not a commit SHA; `checkout` is pinned to an exact version tag. A cache
  poisoned for that key would still be caught by the hash check, which runs after the cache is restored.

### G8: PASS

- **D-024** (how M1 reads "empty Core compile") matches the workflow: toolchain install, `dump-package`, smoke
  package against `WinSDK`, the logged winsqlite3 version and the boundary check. It also matches PROGRESS G2
  "Applies: M1 (CI), M2+" and G3 "M2 (Support), M3+ (Core)".
- **D-025** matches `windows.yml`: the URL, the SHA-256 `9382E149...D91D59`, the Apple signer check and the cache key
  of version plus hash.
- PROGRESS shows M0 approved with tag `port-M0-approved` (`990426e`), and M1 in "review" with start commit `703ae2e`.
  The `$profile` variable is renamed to `$testProfile`.
- PORTING_PLAN §1: the Package.swift row says the Windows branch gets Support (M1). PORTING_PLAN §3: "13 files (10
  not replaced)". ADR-001 now gives 20 remaining guards and 16 (18) shared files. Both match the M0 round-2 review
  notes.
- No control characters were found in docs/windows-port, .claude, .github or Package.swift (`grep -P` for
  `[\x00-\x08\x0b\x0c\x0e-\x1f]`). The BEL defect from M0 round 2 is fixed.

Non-blocking notes:

1. PROGRESS "Next steps" still lists item 2 ("M1: Windows branch of `Package.swift` ... `windows.yml` (draft in the
   worktree)") as a to-do, although that is what `ffc8dba` delivers. There is no step for the M1 tester/reviewer
   round or the `port-M1-approved` tag.
2. PROGRESS "M0 round-2 non-blocking notes (to fold in at M1/M3)" still lists, as open, items this commit has already
   folded in: D-007's non-ASCII fallback, D-010, D-011, D-018, D-020, D-021, D-023, the "8 -> 10" and ADR-001 counts,
   and the `$testProfile` rename. Mark them done or remove them.
3. The G1 row in PROGRESS still names only the M0 run. Recording this milestone's run, 38982141982, would keep the
   table current.
4. For M2: PORTING_PLAN §1 says the `#else` branch will get "Support's test fixtures (M2)". That is a change to the
   macOS manifest. It is intended (the golden fixtures must run in the macOS CI, G4), but M2's review should check it
   is limited to the resources line.

## Skipped tests

None. No tests ran on Windows in M1 (D-024).

TESTS: ALL_PASS
