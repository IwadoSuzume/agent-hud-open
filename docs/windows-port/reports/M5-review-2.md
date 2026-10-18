# M5 review, round 2

- Reviewer: port-reviewer (general-purpose agent following `.claude/agents/port-reviewer.md`, D-017), 2026-10-18,
  read-only: no builds or tests, nothing written.
- Range: `git diff 505492b...bb1ce7d`, with a close read of `c369f8d...bb1ce7d`.
- Verdict: **APPROVE** — both round-1 BLOCKING items resolved; 9 NON_BLOCKING.

## Round-1 BLOCKING items

1. A failed `ReplaceFileW` could delete the only copy of a settings file — **resolved**. Every outcome checked against
   the ReplaceFile documentation: success (backup removed); 1175/1176 with a backup name (both names kept, staged copy
   removed); 1177 (old file moved back from the backup, then staged and backup removed); sharing violation or other
   (names kept, staged removed); a failed restore deletes nothing, logs both paths and still throws. The no-file branch
   never overwrites a file that appears meanwhile. The `Replace` seam is tested for 1177/1176/1175 and a real held
   handle.
2. Claude's ancestry under 8.3 spellings — **resolved in the code**: both sides compared by `Win32.longPath`,
   case-insensitively (Windows branch only), tested short-ancestor/long-candidates and short-home/long-ancestor; the
   skip after the long-form assertions is registered. CI on the runner and a green `Source checks` are the tester's.

All eleven round-1 NON_BLOCKING items addressed.

## Findings

[NON_BLOCKING] Platform/Windows/HookSettings+Windows.swift:51 (also :44, :61) — `try? removeItem` silently leaves a
backup or staged copy when removal fails (an indexer or antivirus holding it); the backup keeps the original's DACL but
is unreported. — Log a failed removal through `PlatformLog`.

[NON_BLOCKING] HookSettings+Windows.swift:55-67 — the restore-failed branch is untested; if the target vanishes
between `fileExists` and the replace, the log says "could not be put back" and the staged copy stays. — Test a held
backup so the move back fails; when neither target nor backup exists, remove the staged copy and say so.

[NON_BLOCKING] HookSettings+Windows.swift:79 — `path.count` counts Characters, not UTF-16 units. — Use
`path.utf16.count`; optionally standardise before prefixing.

[NON_BLOCKING] DECISIONS.md D-023 — does not describe the backup name, the restore after 1177, the logged leftovers or
the `\\?\` threshold. — Revise it (G8).

[NON_BLOCKING] Platform/Windows/Win32.swift:134 — `longPath` fails for a path over MAX_PATH without `\\?\`, so its
8.3 spelling still does not match. — Note it or prefix as `native()` does.

[NON_BLOCKING] Platform/Windows/HookCommand+Windows.swift:191 — `hasPrefix("\\\\")` also matches a local `\\?\C:\…`
path, so an engine started through the long-path prefix counts as on a share and gets no hooks. — Strip `\\?\` (and
map `\\?\UNC\` to `\\`) first.

[NON_BLOCKING] HookFormsWindowsTests.swift:216 — the second assertion repeats the first; the reverse case (TEMP long,
engine path short) is untested. — Assert it.

[NON_BLOCKING] ProviderHTTPWindowsTests.swift:94 — for 127.0.0.1 over HTTPS only non-nil is checked; widened flags
would pass. — Assert the exact four-flag value.

[NON_BLOCKING] SUPPORT_MATRIX.md:78 — CodeBuddy Code's source is on `www.workbuddy.ai`, WorkBuddy being a separate,
unsupported client. — Confirm the page is CodeBuddy Code's own reference or cite the CodeBuddy domain.

## Checked and fine

`WindowsWebSocket` lock discipline (only non-blocking calls under the lock, no deadlock including `finish` →
`onCancel` → `cancel`, no double close, no leak, the residual race documented in D-040); DeepSeek `module(roots:cache:)`
identical on macOS; every round-2 shared change inside `#if os(Windows)` or that seam, the new shared test
`#if !os(Windows)` and listed; the "Hook forms" table matches `windowsForm`/`clientForms`; SKIPPED_TESTS complete and
its 1426 consistent; no credential logged, tests in temporary homes and profiles, no shell strings.

VERDICT: APPROVE
