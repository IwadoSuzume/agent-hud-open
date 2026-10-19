# M7 review, round 2 (port-reviewer): `git diff 5ab51fc...96bdd61`

**Milestone:** M7, Windows UI shell. **Round:** 2. **Range:** `5ab51fc...HEAD`, with HEAD = `96bdd61` on `m7-work` in worktree `E:\agenthud-dev\wt7`.

**What I read:**
- TASK.md §1, §3–§6.
- PROGRESS, DECISIONS D-043 to D-053, BLOCKERS B-002 and B-003, PROTOCOL.md 1.1 to 1.5, the v1 schema, SUPPORT_MATRIX and `reports/M7-review-1.md`.
- All of `git show 96bdd61`, plus the parts of the full range that it touches.

**What I compared against the Desktop sources they claim to mirror:**
- `PermissionAlertViews.swift`: `PermissionOpenRow`, `PermissionDiff`, `PermissionAlertCompactView`
- `ScreenHUD.swift` (`showsAlertDetails`)
- `SourceDetector.swift`
- `DesktopApplication.start`
- `LoginItem.swift`
- `AgentPalette`, `StatusPalette`, `IslandAlert`

**Method:** read-only. Nothing was built or run. I did not run the gates; a tester runs them. CI attempt 1 on `96bdd61` failed only on the upstream timing test `ProcessLinesTests.testABusyMacsListingIsReadInAMoment`, and a rerun is in progress.

**Checks that hold:**
- **macOS:** shared files are unchanged except one `#if os(Windows)` in `DemoData.permissionRequest`'s `default:` and the Windows workflow. Every new or changed Swift file is wrapped in `#if os(Windows)`. `Package.swift`, `ci.yml`, the boundary script and the notices are untouched. The root and bundled `THIRD_PARTY_NOTICES.txt` are byte-identical (`cmp`). No new packages.
- **Counts match PROGRESS and SKIPPED_TESTS:**
  - C# tests: 16 protocol + 38 shell = 54.
  - Fixtures: 24 valid and 17 invalid.
  - Smoke test: 15 pictures.
- **Protocol 1.5:**
  - The engine and the shell agree on the version: `ShellProtocol.minor` and `ProtocolVersion.Minor` are both 5.
  - The request and the answer have the same fields in `ShellProtocol`, `EngineServer`, `Protocol.cs`, PROTOCOL.md §1.5 and the schema (`sources` and `sourcesRequest` cannot both match a message).
  - Both sides read the shared fixtures. A 1.4 engine answers `sources` with `error`, as documented.
- **No Core rule in C#:**
  - `CardRules` and `IslandParts` choose what to show (presentation).
  - `DesktopColours` holds colours only.
  - `ShellModel.Hover` and `Saved` now hold no Core defaults.
  - `ParsePlacement` requires every field the schema requires.
  - Support status, status words, live-status defaults and placements all come from the engine.

## Entries

- **[BLOCKING]** `docs/windows-port/DECISIONS.md:50` (D-043's round-2 note) and `docs/windows-port/PROGRESS.md:113-116` — **Round 1's BLOCKING 3 is only partly fixed: most of the unfinished panel work still has no owner.**
  - Round 1 accepted the partial M7 items "once each is recorded with an owner". B-002 and B-003 now cover the agent-tools channel and the session title and row tokens.
  - Still without an owner:
    - **The panel's balances, account grouping, account and source notices, and 24-hour token columns.** TASK §1 goal 1 names "余额 / 24h token" in the panel explicitly.
      - D-043 now says these are "D-049/D-051's later minor versions", but neither decision mentions them. D-049 is about statistics and D-051 about placement.
      - PROGRESS item 11's "Left for later" list leaves them out.
    - **Replies listed beside a waiting request.** D-047 says "the Windows event panel does not, yet".
    - **The rest of the list:** the Simple panel, logo size and spacing, moving the HUD to another display, the other settings panes and the other statistics pages.
      - These are recorded only as "later minor versions".
      - Only M8 (packaging) and M9 (wrap-up) remain, and TASK's finish condition requires every remaining item to be in BLOCKERS.md.
  - Fix (documentation only):
    - Add a BLOCKERS entry, or extend B-003, for the panel's balances, grouping, notices and 24-hour tokens, the replies beside a request, and the dock and window items. Give each the protocol addition it needs, as B-003 does.
    - Correct D-043's cross-reference and PROGRESS item 11 to point at it.

- **[NON_BLOCKING]** `Sources/AgentHUDCore/MCP/MCPServer.swift:202`, `Sources/AgentHUDCore/MCP/MCPTools.swift:17` and `docs/windows-port/PROGRESS.md:135-136` — **`--mcp` tells Windows users things that are not true on Windows.**
  - With B-002 open, every Windows agent-tool call is told "Turn them on in Settings › Experimental", a pane the Windows shell does not have.
  - The server's instructions still say "at the Mac's notch".
  - PROGRESS gives that text to "M6/M7", and M7 is ending.
  - Fix: in B-002, record what `--mcp` says on Windows. Give the platform-aware text a named owner (M9, or a minimal `#if os(Windows)` sentence in Core).

- **[NON_BLOCKING]** `docs/windows-port/PROTOCOL.md:91` — still says the panel row's shorter total "comes with the row's title in M7, D-043". It is now B-003. Fix: point at B-003.

- **[NON_BLOCKING]** `docs/windows-port/SUPPORT_MATRIX.md:4-6` — **The matrix promises more than the Agents list shows.**
  - It says that for "the client, or that part of it" the Agents list says "Not supported on Windows".
  - The list has rows only for the clients the Desktop's `SourceDetector` has. The 🔶 Claude and Codex desktop apps, DeepSeek Harness's app, Qoder CN and QoderWork never appear as unsupported; only Grok Bot does.
  - Fix: either word the sentence for what is listed and leave the desktop apps to `docs/windows.md` (M9), or add a note to the affected rows.

- **[NON_BLOCKING]** `windows/AgentHUD.Shell/CardRules.cs:27` with `windows/AgentHUD/IslandWindow.xaml:212-241` — **A question or plan card can show a diff the Desktop never shows.**
  - `Diff` ignores the card kind, and the diff border sits outside the `IsPlain` panel.
  - So a question card, or a plan card answered here, that carries `removed`/`added` would show the lines. The Desktop's `PermissionOpenRow` checks `isQuestion` and `answersPlan` first.
  - `Detail` already respects the kind.
  - Fix: return `[]` from `Diff` for `CardKind.Question` and `CardKind.Plan`, and add a case to `CardRulesTests`.

- **[NON_BLOCKING]** `Sources/AgentHUDCore/Platform/Windows/Shell/ShellSources.swift:41-81` — **The copied `resolve`/`detect` rules can drift unnoticed.**
  - They are a verbatim copy of `SourceDetector`, which is acceptable: the copy is Swift in the engine, and moving the code would touch Desktop files.
  - `testTheEventsWordsAreTheDesktopsCopy` checks only its `L10n.text` calls, not its rules, so an upstream change to `SourceDetector.resolve` would drift silently.
  - Fix: add a source check that compares the whitespace-squeezed bodies of `resolve` and `detect` with the Desktop's. The one intended difference is `UserHome.directory` for `homeDirectoryForCurrentUser`.

- **[NON_BLOCKING]** `Sources/AgentHUDCore/Platform/Windows/Shell/EngineServer.swift:124-127` — **Two new non-demo paths have no test.**
  - Nothing checks that the first start writes `liveStatusPreferences`.
  - Nothing exercises the non-demo `sources` answer (`ShellSources.detect` under the isolated home). The end-to-end test covers only the demo list.
  - Fix: in `testARealRequestGoesThroughTheProtocolAndHooksChangeOnlyWithTheirSwitch`, which already has an isolated profile:
    - send `sources`, and assert every row is `detected == false` except the ones the test's fixtures create;
    - read the settings file, and assert the defaults were written.

- **[NON_BLOCKING]** `windows/AgentHUD/StatisticsWindow.cs:52` with `windows/AgentHUD/App.xaml.cs:62` — **The statistics window ignores the appearance setting unless Settings has been opened.**
  - It takes light or dark from `Application.ThemeMode`. That starts as Dark and is set only by `SettingsWindow.Theme`.
  - So a user on light appearance (or "system" in light mode) who opens only the statistics window gets it dark.
  - Fix: apply the appearance at the application level on each state and on `UserPreferenceChanged`, not only from the settings window.

- **[NON_BLOCKING]** `windows/AgentHUD/LoginItem.cs:21-23` — **The "installed copy" gate is a path test.**
  - It refuses only paths containing `\bin\Debug\` or `\bin\Release\`. A build output anywhere else registers itself, and so does a `dotnet publish -o <dir>`.
  - Fix in M8: gate on a positive marker of the packaged layout, for example a file the build script writes next to the executable.

- **[NON_BLOCKING]** `Tests/AgentHUDCoreTests/WindowsSupport/ShellProtocolTests.swift:126-129` — the new test was inserted between the 1.3 statistics doc comment and its function, so `testTheSourcesAreTheSharedFixture` now carries both comments. Fix: move the 1.3 lines back above `testTheStatisticsAreTheSharedFixture`.

## Round 1's items

**BLOCKING:**
1. **An edit's card hid its lines — fixed.**
   - `CardRules` shows the diff first, then the detail, as `PermissionOpenRow` does.
   - It marks lines − and + with blank lines kept (`omittingEmptySubsequences: false` reproduced), in the Desktop's colours.
   - It is tested against `demo-edit` in the shared fixture, and the snapshot draws `card-edit`.
   - The remaining kind gap is the CardRules entry above (non-blocking).
2. **A waiting request opened the panel unasked — fixed.**
   - `IslandParts` opens the panel only when hover has opened it (`open && !resting`), as `ScreenHUD.showsAlertDetails` does.
   - At rest the request holds the compact line (mark, project or vendor, the Desktop's short status, the count), as `PermissionAlertCompactView` does.
   - A click on that line answers nothing.
   - Covered by five view-model tests, `ui-check.ps1` (it hovers before clicking) and the `island-request` picture.
   - Typing still holds the island open, and the full-screen rule still never hides a request.
3. **Unowned M7 work — mostly fixed.**
   - **Done:**
     - Protocol 1.5 `sources` with Core's `PlatformSupport` verdict, and the Agents section's "Not supported on Windows".
     - `SUPPORT_MATRIX:5` corrected.
     - The live-status defaults applied at start: the same call and order as `DesktopApplication.start`, the demo using `DemoData.sources`.
     - D-043 corrected.
   - **Recorded in BLOCKERS:**
     - B-002, the MCP agent-tools channel. Deferring it is acceptable: the tools arrange panel layouts and styles the Windows shell does not draw, and the feature is experimental and off by default on macOS.
     - B-003, the session title and row token count. Deferring it is acceptable: it is a small display gap, and its suggested fix (Core functions plus a protocol field) is sound.
   - **Still open:** the other partial items have no owner, which is this round's BLOCKING entry.

**NON_BLOCKING:**
- **Fixed:**
  - the C# `unverified` assertion (and the PROGRESS record corrected);
  - D-044's text;
  - Core defaults removed from C# (placement, hover, wait; no drag before the display is placed);
  - 1.4 C# tests (placements, `MovePlacement`: other screens kept, notch becomes logos, offset clamped) and invalid `displays` fixtures;
  - the `LostMouseCapture` handler (drag state cleared before release, so the release is not taken for a lost capture);
  - `--feed` without `--snapshot` refused;
  - the stale workflow comment and PORTING_PLAN row;
  - the colours: `DesktopColours`, with source checks against `AgentPalette`, `StatusPalette` and `IslandAlert`;
  - routing on `isQuestion` alone;
  - `DynamicDaylightTimeDisabled`;
  - live system changes: `UserPreferenceChanged` in Settings, and `DpiChanged` with a guard so a rebuild happens only when a display measures differently, which ends the scale loop.
- **Partly fixed:**
  - **Full screen:** the caption rule fixes maximised windows that have a title bar. A caption-less maximised app over an auto-hide taskbar still counts as full screen; that is acceptable for an optional feature.
  - **Launch at login:** gated (see the LoginItem entry above). An explicit "on" now clears Task Manager's "disabled".
- **Deferred with a record:** the hooks-off confirmation's wording. It is recorded for M9's `docs/windows.md` (PROGRESS item 11), which is acceptable.

**Beyond round 1:**
- The CI time-zone crash is fixed: `WindowsTimeZone.adoptable` maps the identifiers Foundation does not list that never change offset (`Etc/UTC` and its aliases) to their fixed offset. It is tested (`testZonesFoundationDoesNotListAreTheirOffset`, `testTheUTCZoneCanBeTheDefault`), and D-050 records the measurement.
- `EngineServeEndToEndTests.send` now fails only the one test when the engine has gone, rather than trapping the whole run.

## G7

- **Settings window sources:** it asks for its sources only when it opens. `detect` checks whether files exist and reads no credentials.
- **`LoginItem`:** writes only HKCU `Run` and `StartupApproved` values under its own name.
- **Test inputs:** the C# tests read only repository sources and fixtures.
- **Other G7 items:** no new process starts, shell strings, listeners or stored credentials.

VERDICT: CHANGES_REQUESTED
