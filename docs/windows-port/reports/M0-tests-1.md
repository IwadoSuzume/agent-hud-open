# M0 test report, round 1

- Branch: `windows-port`, head `d28f59d` (milestone start `c258093`). The working tree was clean when the gates
  started. While the run was going on, uncommitted work from another session appeared: 8 lines added to
  PORTING_PLAN.md (§8.1), and new untracked `.github/workflows/windows.yml`, `Tests/AgentHUDCoreTests/WindowsSupport/`,
  `Tests/AgentHUDSupportTests/Fixtures/` and `RecordCodingGoldenTests.swift`. None of it is committed, so it is not
  part of what this report gates. G6 was re-run with those files present (the script also scans untracked files) and
  still passes.
- Run by: port-tester, 2026-10-16, Windows 11 Pro 10.0.26200
- Diff under test: `git diff c258093...HEAD`, 12 files: docs/windows-port/**, .claude/agents/port-{reviewer,tester}.md,
  scripts/check-source-boundaries.py. Nothing changed under Sources/, Tests/, Package.swift, Makefile or .github/.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | PASS |
| G2 Windows build | N/A |
| G3 Windows tests | N/A |
| G4 determinism | N/A |
| G5 UI | N/A |
| G6 boundaries | PASS |
| G7 security review | review gate, nothing noted |
| G8 docs | PASS (non-blocking notes below) |

### G1: PASS

- Command: `ghapi.sh GET /repos/IwadoSuzume/agent-hud-open/actions/runs?branch=windows-port&per_page=5`, then
  `.../actions/runs/38969577715` polled every 60 s and `.../actions/runs/38969577715/jobs`
- Run 38969577715, `Source checks`, event `workflow_dispatch`, head_sha `d28f59d`: `completed` / `success`
  (created 21:28:09Z, done about 21:37:40Z; about 8.5 min of polling)
- Jobs:
  - `test` (macos-15): success, 21:28:22Z to 21:37:35Z. Steps: Check source boundaries success, Test success
  - `app` (macos-15): success, 21:28:18Z to 21:33:09Z. Steps: Build application success, Verify local signature and resources success
  - `macos` (ubuntu-latest): success. Step: Tests and application passed success
- Because of this run, the changed boundary script also passes on macOS (`test` job, step "Check source boundaries").

### G2, G3, G4, G5: N/A

There is no Windows Swift or .NET code on this branch in M0. The spike numbers in PORTING_PLAN.md §8 (Core builds;
AgentHUDCoreTests 1282 run / 9 skipped / 1244 pass / 38 fail) come from branch `spike-m0` (`809e047`). They are not
gates of M0 and were not re-run here.

### G6: PASS

- Command: `python scripts\check-source-boundaries.py` (from `E:\src\ahud`), duration about 1 s
- Output: `Source boundaries and ignore rules passed.`, exit 0
- Review of `git diff c258093...HEAD -- scripts/`:
  - `path.read_text()` becomes `read_text(encoding="utf-8")` for scanned files and for `Package.swift`. On macOS the
    default encoding is already UTF-8, so the behaviour there is the same. On this machine the default is cp936: with
    it only 473 of 757 files decode, and with UTF-8 719 decode. The old code silently skipped about 246 text files on
    Windows.
  - `git check-ignore --stdin` is now given bytes (`.encode()`) and its output is read with `.decode()`, instead of
    `text=True`. The content is the same LF-separated ASCII list, so macOS behaviour does not change. On Windows,
    text mode wrote CR LF.
  - For comparison, the script as it was at `c258093` fails on this machine (exit 1) with nine false
    `.gitignore: missing rule for …` failures, one for every probe path. The CR LF made git read the `\r` as part of
    each path. The fixed script passes.
  - Secret patterns, private extensions and directories, symlink rules, the THIRD_PARTY_NOTICES byte comparison and
    the `.package(` check are unchanged.

### G8: PASS

All required files are present: TASK.md, PORTING_PLAN.md, DECISIONS.md, PROGRESS.md, BLOCKERS.md and
adr/ADR-001…004 (all four `Status: accepted (M0, 2026-10-16)`).

Checks that pass:

- Every D-xxx reference (D-001…D-017) and ADR-00x reference resolves.
- The .NET 10 vs .NET 8 departure from the brief is recorded in D-002 and ADR-002.
- The G6 command in PROGRESS matches the script and the port-tester definition.
- The `.claude/agents` files exist as D-017 says.
- The 10 Windows-excluded test files match between ADR-001 ("10 test files"), PORTING_PLAN §6 and `spike-m0`'s
  `windowsSkippedTests`.
- BLOCKERS.md says "None yet".

Non-blocking inconsistencies:

1. PROGRESS.md "Gates": G1 says "Applies from M1", but the fork is pushed and G1 is being used as an M0 gate here.
   "Next steps" item 1 says "port-tester (G6 only for M0)", and item 2 ("M1: fork, enable Actions, … dispatch ci.yml
   for the macOS baseline") is already done for this head (run 38969577715).
2. PORTING_PLAN.md §7 assigns the boundary-check "UTF-8 reading" to M1, but it lands in M0 (this diff).
3. ADR-001 Evidence item 3 says the excluded test files are "each … listed in SKIPPED_TESTS.md". No SKIPPED_TESTS.md
   exists on `windows-port` or on `spike-m0`; today the list lives in PORTING_PLAN §6. G3 will require that file
   from M2/M3.
4. PROGRESS G4 names `PortableDigestTests` and `RecordCodingGoldenTests`, which do not exist on this branch yet. This
   is expected because G4 applies from M2. Noted only so M2 creates them under these names.

## Skipped tests

None. No tests were run on Windows in M0, so there are no skips to check against SKIPPED_TESTS.md.

TESTS: ALL_PASS
