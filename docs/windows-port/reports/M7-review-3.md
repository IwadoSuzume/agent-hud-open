# M7 review, round 3 (port-reviewer): `git diff 5ab51fc...e7bd816`

**Milestone:** M7, Windows UI shell. **Round:** 3. **Range:** `5ab51fc...HEAD`, HEAD = `e7bd816` on `m7-work`, worktree `E:\agenthud-dev\wt7`.

**What I read:**
- Role definition, TASK.md brief, PROGRESS, DECISIONS (D-043, D-047, D-049, D-051, D-053, D-054), BLOCKERS (B-002 to B-005), PROTOCOL.md, SUPPORT_MATRIX, SKIPPED_TESTS, `reports/M7-review-2.md`.
- All of `git show e7bd816`. Since round 2's HEAD (`96bdd61`) the range has gained two commits:
  - `bd1cdd8`: reports only.
  - `e7bd816`: round 3's code and docs.

  The rest of the range was reviewed in rounds 1 and 2.

**Compared against:**
- `Sources/AgentHUDDesktop/System/SourceDetector.swift` (whole file, against `ShellSources.swift`)
- `PermissionAlertViews.swift` (`PermissionOpenRow`'s branch order)
- `DesktopApplication.applyAppearance`
- Core's `AppearanceMode`, `SettingsStore.update`/`persist`
- `WindowsFolders`, `CodexLocator`, `WindowsCodex`, `DeepSeekLocator`

**Method:** read-only. Nothing was built or run. A separate tester runs round 3's gates.

## Checks that hold

**1. macOS is unchanged (shared files).**
- `MCPServer.swift`: the original `case .off:` line is untouched inside `#else`. The Windows `case .off:` sits in an `#if os(Windows)` branch within the switch, and the switch stays exhaustive on both sides.
- `MCPTools.swift`: the original five-line `instructions` literal is untouched inside `#else`.
- `MCPToolsOffTests.swift`: the macOS assertion is untouched inside `#else`.
- `MCPServerTests.swift`: the expectation is now built as `"… sessions \(place). "`, with `place = "at the Mac's notch"` on macOS. The source line changed, but the string asserted on macOS is the same, byte for byte.
- Neither test branch leaves a case out on any platform, so neither needs a SKIPPED_TESTS entry.
- Untouched in the range: `Package.swift`, `ci.yml`, `check-source-boundaries.py`.
- The root and bundled `THIRD_PARTY_NOTICES.txt` are byte-identical (`cmp`).
- No new packages.

**2. Appearance change (C#): no Core rule.**
- `Appearance.IsDark` maps `light`/`dark`/anything else (`system`) to the Windows app mode.
- This is the same presentation mapping the Desktop does in its own UI layer (`DesktopApplication.applyAppearance`: `.system` → `NSApp.appearance = nil`).
- The setting itself, its values and its default (`.system`) stay Core's. C# holds no default; before the first state it follows Windows, and that case is tested.
- `ShellModel.StringSetting` only reads the engine's settings.

**3. Appearance change (C#): lifecycle.**
- `App.OnStartup` subscribes `SystemEvents.UserPreferenceChanged` and `App.OnExit` removes it, next to the existing `DisplaySettingsChanged` removal. The early `Shutdown(...)` returns in `OnStartup` still pass through `OnExit`.
- `SettingsWindow` and `StatisticsWindow` subscribe `App.AppearanceChanged` and remove it in their `Closed` handlers. WPF closes both windows at shutdown, and `App.settingsWindow` is nulled on `Closed`. No handler outlives its window.
- The OS callback is marshalled with `Dispatcher.BeginInvoke`. The same method-group form, `Dispatcher.BeginInvoke(OpenSettings)`, already compiles in this file.
- Ordering: `App.OnModelChanged` is subscribed before either window's `Refresh`. Even in the other order, `AppearanceChanged` re-themes after `FollowAppearance`, so every path settles on the right theme.
- The statistics window now takes `IsLight` from `App.IsDark` and redraws on change. Round 2's defect (dark until Settings had been opened) is gone.
- The registry read (`AppsUseLightTheme`) moved verbatim from `SettingsWindow`.

**4. `CardRules.Diff` (C#).**
- It returns `[]` for `CardKind.Question` and `CardKind.Plan` and still shows the change for `PlanElsewhere`.
- This matches `PermissionOpenRow`, which checks `isQuestion`, then `answersPlan`, then the diff, then the detail, and adds `PlanNotice` for `isPlan && !answersPlan`.
- `HasDiff` drives the border's visibility, so the out-of-`IsPlain` border now collapses on those cards.
- Tested, including the `PlanElsewhere` case.

**5. `testTheSourcesRulesAreTheDesktopsCopy` can fail on a drift.**
- It cuts each function from `static func <name>(` to its matching closing brace in both files and squeezes whitespace runs to one space. It replaces `fileManager.homeDirectoryForCurrentUser` with `UserHome.directory` in the Desktop's text only, then compares the two strings exactly.
- What fails it:
  - any token change in either body, including comments and spacing between tokens;
  - a rename or removal of either function (`XCTUnwrap` fails);
  - a reintroduced `homeDirectoryForCurrentUser` in the engine copy, because the replacement is one-sided.
- I compared the two files: today the bodies are identical apart from that one line, so the test passes and is not vacuous.
- No brace appears inside a string literal in either body.
- Limit, inherent and accepted in round 2 for the other source checks: it runs only in the Windows workflow.

**6. End-to-end additions read no real user data.**
- The engine runs under `isolatedEnvironment`: allow-listed system variables only; `USERPROFILE`, `HOME`, `APPDATA` and `LOCALAPPDATA` inside the test's temporary home (created, so `WindowsFolders` takes them over the known folders); `Path` limited to System32, Windows and the Swift runtime folders; no client-home variables.
- Every locator `detect` calls resolves under that home:
  - Claude, Grok Bot and the Additional and OpenAgent sources take `home`;
  - Codex uses `WindowsCodex.engines()` under `%APPDATA%`, then the restricted `Path`;
  - DeepSeek uses `~/.dsh`, with `DSH_HOME` not passed.
- Core references no `ProgramFiles`.
- The test process reads back only `<temp home>\Profile\Roaming\Agent HUD Open\settings.json`.
- `SettingsStore.update` persists synchronously before the first `state`, so reading the file after the `sources` answer is not racy.

**7. Round 2's BLOCKING item is resolved.**
- **B-004** (OPEN) owns the panel's balances (`ReportView.billing`), account grouping (`rowGroups`/`accountSections`), account and source notices, the token panel and its periods, and replies beside a waiting request (D-047). Each has a protocol addition proposed: `panel.billing[]`, `panel.accounts[]`, a `tokens` request and answer, and `state.replies[]`.
- **B-005** (OPEN) owns:
  - the Simple panel;
  - logo size, spacing and edge distance;
  - the bounds shown while dragging;
  - moving the HUD to another display;
  - the other settings panes;
  - the other statistics pages.
- References now point at these entries:
  - D-043's round-3 note points at B-004 and B-005; its wrong D-049/D-051 cross-reference is superseded.
  - PROTOCOL.md:96 names B-004 as the owner.
  - PROGRESS item 11 now lists B-002 to B-005 with every item.
- TASK's finish condition (every unfinished item in BLOCKERS.md) is met for M7's scope.

## Entries

- [NON_BLOCKING] docs/windows-port/SKIPPED_TESTS.md:12 — **The round-3 count is not measured.** "State at M7 round 3 … 1461 pass" reads as a measured full `test.ps1` run, but PROGRESS item 12 (PROGRESS.md:121) records only the four changed classes run locally (32/32). The 1461 is round 2's 1460 plus the one new test, inferred rather than measured. — Replace the line with the round-3 tester's measured G3 figures, or mark it as expected until that run is filed.
- [NON_BLOCKING] docs/windows-port/BLOCKERS.md:45 — **The entries are out of order.** B-004 and B-005 are inserted between B-002 (line 28) and B-003 (line 78), so the file reads B-001, B-002, B-004, B-005, B-003. — Move B-004 and B-005 after B-003.
- [NON_BLOCKING] Sources/AgentHUDCore/MCP/MCPTools.swift:15-17 — **A doc comment is detached on macOS.** The `/// What a client's model is told…` doc comment now sits above `#if os(Windows)`, so on macOS it no longer directly precedes the `instructions` declaration in the `#else` branch. Code and words are unchanged; only the comment's attachment differs, which matters only to Quick Help, since the property is internal. — Optionally move the doc comment inside both branches, or put the `#if` around the literal alone, so the macOS declaration keeps its comment directly above it.

No other problems found in round 3's changes against checklist items 1–10:
- C# holds no Core rule.
- No swallowed errors were added.
- No new process starts, shell strings, listeners or stored credentials.
- No unlisted test exclusions.
- No dependencies.
- The docs match the code: D-054, SUPPORT_MATRIX's new wording, PROTOCOL.md's B-003 and B-004 pointers, and the PROGRESS row.

## Round 2's items

**BLOCKING (unowned M7 work): resolved.** See check 7 above.

**NON_BLOCKING:**
1. **`--mcp`'s words on Windows — fixed.** One `#if os(Windows)` each in `MCPServer.swift` and `MCPTools.swift`. On Windows it now says "Agent HUD's agent tools are not available on Windows yet." and "at the top of the screen". macOS's words are unchanged, and both upstream tests branch the same way. B-002 records what `--mcp` says meanwhile, and PROGRESS Known issues marks it resolved.
   - Remark, not an entry: "at the top of the screen" describes the default dock. A user can dock any edge (D-051), just as macOS's "at the Mac's notch" describes its default.
2. **PROTOCOL.md:91 — fixed.** It now reads "later, BLOCKERS B-003".
3. **SUPPORT_MATRIX:4-8 — fixed.** It now says the Agents list has rows only for the clients the Desktop's source list names. It names the unsupported parts without a row (the Claude and Codex desktop apps, DeepSeek Harness's app, Qoder CN, QoderWork) and leaves them to `docs/windows.md` (M9).
4. **`CardRules.Diff` by card kind — fixed and tested.** See check 4.
5. **Source rules can drift — fixed.** `testTheSourcesRulesAreTheDesktopsCopy`, see check 5.
6. **Untested non-demo paths — fixed.** The end-to-end test now sends `sources` to a real engine in the isolated home. It asserts that only `claude-code` is detected and reads back the saved `liveStatusPreferences` (only `claude` on, others present and off). See check 6.
7. **Statistics window ignores appearance — fixed.** The appearance is owned by the application (`App.FollowAppearance`) and `Appearance.IsDark` is tested. See checks 2 and 3.
8. **LoginItem's path-test gate — deferred to M8, as the task says.** It is recorded in PROGRESS Known issues ("For M8: … the packaging script should write a marker beside the shell and the gate should require it") and in D-054. That is acceptable for this milestone.
9. **Misplaced test doc comment — fixed.** The 1.3 comment is back above `testTheStatisticsAreTheSharedFixture`.

## G7

Round 3's changes are covered by checks 3 and 6; nothing in them adds a G7 risk:
- No credentials are touched.
- The only new registry access is the HKCU `AppsUseLightTheme` read, moved from `SettingsWindow`.
- No new process starts, shell strings or listening ports.
- The C# tests read only repository sources and fixtures.

VERDICT: APPROVE
