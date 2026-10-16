# M0 test report, round 2

- Branch: `windows-port`. Head under test: `990426e` ("Windows port M0: answer the first review"; docs only).
  Milestone start: `c258093`.
- While this round ran, `fda2879` ("record where M0 review round 2 stands") landed on top. It changes only
  docs/windows-port/PROGRESS.md and is covered by G6 and G8 below; see G8 defect A.
- Untracked M1–M3 drafts are in the working tree but not part of M0: `.github/workflows/windows.yml`,
  `Tests/AgentHUDCoreTests/WindowsSupport/`, `Tests/AgentHUDSupportTests/Fixtures/` and
  `Tests/AgentHUDSupportTests/RecordCodingGoldenTests.swift`.
- Run by: port-tester, 2026-10-16, Windows 11 Pro 10.0.26200. This report is the only file written; nothing was
  committed or pushed.
- Since `c258093`, nothing has changed under Sources/, Tests/, Package.swift, Makefile or .github/. The only files
  that are not docs are `scripts/check-source-boundaries.py` (unchanged since round 1; `git diff d28f59d..HEAD --
  scripts` is empty) and `.claude/agents/*`.

## Results

| Gate | Result |
| --- | --- |
| G1 macOS non-regression | PASS |
| G2 Windows build | N/A |
| G3 Windows tests | N/A |
| G4 determinism | N/A |
| G5 UI | N/A |
| G6 boundaries | PASS |
| G7 security review | review gate, nothing new noted |
| G8 docs | PASS for `990426e`; one defect in `fda2879` (A) |

### G1: PASS

- Command: `ghapi.sh GET "/repos/IwadoSuzume/agent-hud-open/actions/runs?branch=windows-port&event=workflow_dispatch&per_page=5"`
  found run **38971749789** (`Source checks`, workflow_dispatch, head_sha `990426e`, created 21:47:46Z). I then
  polled `…/actions/runs/38971749789` every 60 s; it completed with success after about 11.5 min. Last, I read
  `…/runs/38971749789/jobs`.
- Jobs:
  - `test` (macos-15): success, 21:47:55Z to 21:58:45Z. Steps: Check source boundaries success, Test success
  - `app` (macos-15): success, 21:47:56Z to 21:54:03Z. Steps: Build application success, Verify local signature and resources success
  - `macos` (ubuntu-latest): success, 21:58:48Z to 21:58:52Z. Step: Tests and application passed success
- No CI run exists for `fda2879`. It changes only PROGRESS.md, which no CI job reads.

### G2, G3, G4, G5: N/A

There is no Windows code in M0. The spike results in PORTING_PLAN.md §8 and ADR-001 come from branch `spike-m0`
(`809e047`) and are not M0 gates. The Support/platform test counts that PROGRESS.md (`fda2879`) gives for worktree
commit `284fc05` were not checked here either.

### G6: PASS

- Command: `python scripts\check-source-boundaries.py`, run from `%LOCALAPPDATA%\agenthud-dev\src` (the junction to
  `E:\桌面项目\agent-hud-open`). The old junction `E:\src\ahud` no longer exists; `E:\src` is empty, as PROGRESS
  notes.
- Output: `Source boundaries and ignore rules passed.`, exit 0, about 1 s. The result is the same at `990426e` and
  again at `fda2879`, both times with the untracked drafts in the tree; the script scans untracked files, and the
  drafts do not break it.
- The script has not changed since round 1, where its UTF-8 and bytes change was reviewed and found to keep macOS
  behaviour. In CI the macOS `test` job's "Check source boundaries" step passed for `990426e`.

### G8: PASS (for `990426e`)

All required documents are present: TASK.md, PORTING_PLAN.md, DECISIONS.md (D-001…D-023), PROGRESS.md, BLOCKERS.md,
the new SUPPORT_MATRIX.md, adr/ADR-001…004, and reports/M0-tests-1.md.

How the four round-1 inconsistencies were handled:

1. **Resolved.** PROGRESS G1 now "Applies: every milestone (M0: run 38969577715 on `d28f59d`, success)". The dispatch
   and read commands are written out, and the stale "fork, enable Actions" step is gone. G6 also applies to every
   milestone.
2. **Resolved.** PORTING_PLAN §1 has the row "Boundary check … fixed in M0 (UTF-8, bytes) | M0 ✅". §7 now gives the
   script's later work as M3 (home rule) and M7 (`windows/`).
3. **Resolved.** ADR-001 Evidence 3 and PORTING_PLAN §6 now say SKIPPED_TESTS.md is "due in M3". §6 lists the 10
   excluded files plus the runtime skips seen in the spike.
4. **Resolved.** PROGRESS G4 now names only `RecordCodingGoldenTests` (M2+). `PortableDigestTests` is no longer
   referenced.

Paths and build commands:

- PROGRESS "Environment" and "Gates" and D-007 all name the per-user junction `%LOCALAPPDATA%\agenthud-dev\src` and the
  scratch path `%LOCALAPPDATA%\agenthud-dev\build`. The junction exists and points at the repository.
- No doc outside reports/ mentions `E:\src\ahud` or `ahud-build` any more.

Numbers cross-checked:

- ADR-001: 6 replaced files. This matches D-006, PORTING_PLAN §4 and `windowsReplaced` in `spike-m0`'s Package.swift.
- ADR-001: 10 of 165 Core test files are excluded. `c258093` has 165 test files, and `spike-m0` adds one test-only
  compatibility file, as ADR-001 states.
- Test totals: 1282 = 1235 pass + 38 fail + 9 skip, the same in ADR-001 and PORTING_PLAN §8.
- Every D-0xx and ADR-00x reference resolves.

Notes:

- **A (defect, in `fda2879`, not in `990426e`).** PROGRESS.md lines 76–77 contain a **BEL control character (0x07)**
  where `\a` should be. The text reads `` `%LOCALAPPDATA%<BEL>genthud-dev\wt` `` and `` `%LOCALAPPDATA%<BEL>genthud-dev\wtbuild` ``
  instead of `%LOCALAPPDATA%\agenthud-dev\wt` / `\wtbuild`. Most likely `\a` was escape-expanded when the file was
  written. These are the "resume here" instructions, so a reader resuming from them would get a wrong path. Fix the two
  lines. `git grep -P "[\x00-\x08\x0b\x0c\x0e-\x1f]" -- docs/windows-port` finds nothing at `990426e`.
- B (non-blocking, already recorded by the reviewer in PROGRESS `fda2879`). The G3 snippet in PROGRESS assigns
  `$profile`, which is PowerShell's automatic `$PROFILE`, so a rename to `$testProfile` is planned. The snippet also
  re-points `LOCALAPPDATA` after `Path`, `SDKROOT` and `$build` are computed; that order looks right, but no test has
  been run under it (G3 is N/A in M0).
- C. PROGRESS "Next steps" (`fda2879`) says to tag **`990426e`** as `port-M0-approved`. That is the commit G1 passed
  on here, so the tag target and the gate results agree.

## Skipped tests

None. No tests were run on Windows in M0.

TESTS: ALL_PASS
