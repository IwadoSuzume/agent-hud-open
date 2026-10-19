# M7 review, round 1 (port-reviewer): `git diff 5ab51fc...c6222d2`

**Scope.** Before the diff I read TASK.md §4, §6 and §7, PROGRESS, DECISIONS D-043 to D-052, PROTOCOL.md 1.1 to 1.4, ADR-002, PORTING_PLAN, SUPPORT_MATRIX and `reports/M6-review-3.md`. I then read every file in the diff. I compared each "mirrors the Desktop" claim with the Desktop source it names. The review was read-only: nothing built or run, no files written.

The things I could check by reading hold:
- Root and bundled `THIRD_PARTY_NOTICES.txt` are byte-identical (`cmp`).
- No bin/obj output is tracked.
- C# test counts are 14 protocol + 26 shell = 40, which matches SKIPPED_TESTS.

## Entries

- **[BLOCKING]** `windows/AgentHUD/CardModel.cs:66-69` — **An edit request's card hides the change being approved.**
  - `Subject => Request.Detail ?? Diff` shows the detail first. Claude's Edit/Write requests carry a detail (the file path) and `removed`/`added` (the demo's `demo-edit` has both), so the card shows the path and never the lines.
  - The Desktop shows the diff first, then the detail (`PermissionAlertViews.swift:153-160`). docs/hud.md, Approvals, says Deny and Allow are "always beside what an allow lets run: … the file and the lines it would change". On Windows the user approves edits without seeing them.
  - `Diff` also drops blank lines, where the Desktop keeps them (`omittingEmptySubsequences: false`).
  - Fix:
    - Use `Diff ?? Detail`, mirror `PermissionDiff` (− and + per line, blank lines kept).
    - Move the card's routing (`Kind`, `Subject`) into `AgentHUD.Shell` and test it against `engine-state.demo.json`'s `demo-edit`.
    - Add a `card-edit` picture to the snapshot and smoke test.

- **[BLOCKING]** `windows/AgentHUD/IslandViewModel.cs:81-83` — **A waiting request opens the whole event panel with no hover.**
  - `ShowsPanel => !Resting && (IsOpen || HoldsRequest)` opens the panel, with live Deny / Allow / Always allow buttons, whenever a request waits on that display.
  - macOS shows a request's details only while the hover machine is open (`ScreenHUD.swift:84`, `showsAlertDetails = machine.isOpen && …`). docs/hud.md says "Hovering opens the queue", and this file's own header (lines 3-4) says the same. "A request holds the island" means the alert does not expire, not that it opens.
  - Risk: on Windows a large card appears unasked at the top centre, never takes focus, and one stray click meant for the window underneath can answer the request.
  - Fix:
    - At rest, show the request's compact line (mark, kind or project, count) and open the queue through `HoverMachine`, as for news. Keep the rule that a full-screen app never hides a request.
    - Update `ui-check.ps1` to hover before clicking a line, and add a view-model test.

- **[BLOCKING]** Unfinished work that the docs say M7 does, with no milestone left to own it (G8, TASK §3):
  - **Where the docs say M7:**
    - `docs/windows-port/SUPPORT_MATRIX.md:5`: unsupported clients are absent "and Settings says so (M7)". TASK §3 also requires them to be shown honestly in settings.
    - `DECISIONS.md` D-043 (line 50) gives M7 three more things:
      - the MCP agent-tools channel;
      - the first start's live-status defaults (`Settings.applyLiveStatusDefaults`, which `EngineServer.start`, around `EngineServer.swift:120-125`, never calls; every client's live status therefore defaults to on, unlike macOS);
      - the session title and row token count.
  - **What M7 did:** the settings window has only the General pane, and none of the above is implemented.
  - **Where the deferrals are recorded:** PROGRESS.md:112-114, "Left for later minor versions", lists some of these but leaves out the agent-tools channel, the live-status defaults and the "Settings says so" display. Only M8 (packaging) and M9 (wrap-up) remain, so nothing owns them.
  - **Fix, either:**
    - implement them: protocol 1.5 sends the agent list with Core's `PlatformSupport` status, the settings window shows "not supported on Windows", and the engine applies the live-status defaults with a Windows source list; or
    - record each in BLOCKERS.md (or PROGRESS with a named target) and correct SUPPORT_MATRIX:5 and D-043 so they no longer say M7.

- **[NON_BLOCKING]** `windows/AgentHUD.Protocol.Tests/ProtocolTests.cs:209-214` — **M6 round-3 item 10 is not done, but is recorded as done.**
  - `TheLaterStateCarriesCoresLabels` still has no `SessionPhase.Unverified` / "Status out of date" assertion.
  - Commit `a66759f` touched no file under `windows/`, yet its message and PROGRESS.md:84 say "the C# test of the later state checks its unverified session".
  - Fix: add the assertion and correct the record.

- **[NON_BLOCKING]** `docs/windows-port/DECISIONS.md:51` (D-044) — still says the test junction is made with `mklink /J`. Since step 1 it is made with `FSCTL_SET_REPARSE_POINT`. Fix: update the text.

- **[NON_BLOCKING]** **Core defaults copied into C#.** All are fallbacks used before the first state, or with an older engine:
  - `windows/AgentHUD/IslandWindow.xaml.cs:82`: the `Default` placement (logos, top, 0.5, 20, 2, 0.4).
  - `windows/AgentHUD.Protocol/Protocol.cs:172`: the `ParsePlacement` field fallbacks.
  - `windows/AgentHUD.Shell/ShellModel.cs:66-67`: hover 400/200 ms, which a test asserts as "Core's default".
  - `windows/AgentHUD/SettingsWindow.xaml.cs:76`: the wait of 10 minutes.
  - With `Default`, a drag sends `MovePlacement` from an empty `Encoded`, so the patch is a partial `ScreenPlacement`.
  - Fix: draw no dock and allow no drag until the engine has placed the display; take everything else from the state.

- **[NON_BLOCKING]** **1.4 has no C# tests.** Nothing tests `placements` parsing or `ShellMessage.MovePlacement` (other screens kept, notch becomes logos, offset clamped). There are no invalid fixtures for `displays` or `statistics`. Fix: add them.

- **[NON_BLOCKING]** `windows/AgentHUD/IslandWindow.xaml.cs:149-185` — **No `LostMouseCapture` handler.**
  - If capture is lost mid-drag (Alt+Tab, a UAC prompt), `dragging` stays true.
  - `Track()` then returns early, so hover is dead on that display, and the HUD stays at the drag target until the next press.
  - Fix: cancel the drag on lost capture.

- **[NON_BLOCKING]** `windows/AgentHUD/App.xaml.cs:28-42` with `windows/AgentHUD.Shell/FullScreen.cs` — **The full-screen rule is a rectangle test.**
  - Any maximised window under an auto-hide taskbar, or any borderless maximised app, counts as full-screen and hides the HUD.
  - Fix: consider `SHQueryUserNotificationState` (`QUNS_BUSY`, `QUNS_RUNNING_D3D_FULL_SCREEN`, `QUNS_PRESENTATION_MODE`), or exclude captioned windows.

- **[NON_BLOCKING]** `windows/AgentHUD/LoginItem.cs:16-25` — **Launch at login can register a development build.**
  - There is no equivalent of the Desktop's `LoginItem.isAvailable` (only a real `.app` bundle registers).
  - Core's default is `launchAtLogin = true`, so any non-demo run of a dev build under `bin\Release` writes an HKCU `Run` value pointing at that build folder.
  - Also, `Set(true)` after Task Manager disabled the entry leaves `StartupApproved` disabling it: the setting says on and nothing launches.
  - Fix: gate on the packaged layout (M8). On an explicit "on", clear our `StartupApproved` value, or show that Task Manager has it disabled.

- **[NON_BLOCKING]** `windows/AgentHUD/SettingsWindow.xaml.cs:126-148` and `windows/AgentHUD/IslandWindow.xaml.cs` — **Live system changes are not followed.**
  - The "system" appearance is read only when a state arrives. There is no `WM_SETTINGCHANGE` or `UserPreferenceChanged` listener, which the TASK §3 mapping asks for.
  - The island has no `WM_DPICHANGED` / `DpiChanged` handling. It is not established that `DisplaySettingsChanged` fires on a scale-only change, which would leave `Monitor.Scale` stale.
  - Fix: subscribe to both and rebuild or re-place.

- **[NON_BLOCKING]** **Colours not held to the Desktop's sources.**
  - The event accents (`IslandViewModel.cs:150`, `Converters.cs:14-16`) are the system blue, green and orange. The Desktop's alert accents are 0x82aaff, 0x6cd8ac and 0xe9a16d (`IslandAlert.swift`), although the comment says "as the Desktop's alert accents go".
  - `StatisticsWindow.cs:19-20` copies `AgentPalette` correctly, but nothing checks it against `AgentPalette.swift`.
  - Fix: correct the colours (or the comment), and add a source check like the strings'.

- **[NON_BLOCKING]** `windows/AgentHUD/CardModel.cs:46` — a request with `isQuestion` and an empty `questions` list routes to the plain card, offering Deny/Allow. The Desktop routes on `isQuestion` alone. Fix: route as the Desktop does.

- **[NON_BLOCKING]** `windows/AgentHUD/SettingsWindow.xaml.cs:117` — **The hooks-off confirmation does not say what stops working.**
  - Its message is `settings.clientHooksNote`, which describes what hooks do. docs/hud.md says the confirmation should name what stops working (answering on the HUD, completion reminders, the waiting state).
  - D-048 documents the difference.
  - Fix: have Core supply a Windows sentence, and carry D-048's differences into `docs/windows.md` (TASK §7.3, M9 to-do).

- **[NON_BLOCKING]** `windows/AgentHUD/App.xaml.cs:72` — `--feed` is accepted without `--snapshot`, where it is unused. Fix: refuse it, so the test hooks stay test-only.

- **[NON_BLOCKING]** **Stale docs:**
  - `.github/workflows/windows.yml:115` says "three pictures"; the smoke test now checks 13.
  - `PORTING_PLAN.md:130` names `windows/AgentHUD.Tests`; the project is `AgentHUD.Shell.Tests`.

- **[NON_BLOCKING]** `Sources/AgentHUDCore/Platform/Windows/WindowsTimeZone.swift` — `DynamicDaylightTimeDisabled` is ignored. A user who unchecked "Adjust for daylight saving time automatically" still gets IANA daylight time, and `testTheZoneHasWindowsCurrentOffset` would fail on such a machine.
  - Fix: use the fixed offset in that case.

## M6 round-3 items

1. Test engines' `PATH` reduced to System32, `%SystemRoot%` and the folders holding `swiftCore.dll` — **fixed**.
2. The "would reach the real profile" assertion replaced by a check that the keys are a subset of the allowlist — **fixed**.
3. The demo, stalled, lock-held and input-end engines all get `isolatedEnvironment`; the lock test claims the lock under the child's `LOCALAPPDATA` — **fixed**.
4. A queued `hello` is replaced where it stands; PROTOCOL.md says "the oldest other line (an `event`)" — **fixed**.
5. `ProtocolWriterTests` covers the `enqueue` rules and the `projectTitle` memo — **fixed**. It tests the pure function, not over a pipe with a stalled reader; that is acceptable.
6. `RemoveDirectoryW` is asserted, and the folder is kept while the link exists — **fixed**.
7. `mklink` through cmd replaced by `FSCTL_SET_REPARSE_POINT` (the reparse buffer layout checked) — **fixed**; D-044's text is stale (entry above).
8. `guard baseWritten > 0` — **fixed**.
9. `imagePath` forward-slash assertion — **fixed**.
10. C# `unverified` check — **NOT fixed**, but recorded as done (entry above).

The tester's note: `test.ps1` now fails a filtered batch that runs no test — **fixed**.

## No business logic in C# and the engine's words (checked, fine apart from the entries)

- **Ported as the Desktop has them:**
  - `HoverMachine`: transition for transition, its 9 tests case for case.
  - `QuestionDraft` / `PlanDraft`: line for line, the 3 draft tests case for case.
  - `EventQueue`: `IslandAlertQueue`'s rules for news.
  - `RequestPlacement`: follows docs/hud.md, Approvals.
  - `MovePlacement`'s notch-becomes-logos rule: the Desktop's `NotchGeometry.dragPlacement`. Its offset is the centre's share of the edge, as Core's own doc for `offset` says.
- `FullScreen` is a shell-only rule (optional in TASK).
- **The engine's words match the Desktop:**
  - `ShellEventCopy` matches `QuotaAlertCopy`, `ResetCreditAlertCopy` and the reply card, word for word, including `AlertPolicy.exhaustedRemaining` and `warning == isWarning`.
  - `ShellStatistics` matches `UsagePeriodsCard`.
  - `ShellStrings` wait choices match GeneralPane.
  - Protocol 1.1 marks and labels (`L10n.modelLabel`, `VendorMark.key`, `queueMarks`) and 1.4 placements (`Settings.placement(on:hasNotch:)`) come from Core.
- **The source checks are meaningful:** `testTheEventsWordsAreTheDesktopsCopy` extracts every literal `L10n.text("…")` call from the three engine files (at least 21) and requires each verbatim (whitespace squeezed) in the Desktop's sources. The `ShellStrings` pairs are checked the same way.
- **Shared files:** `DemoData.swift` gains one `#if os(Windows)` in `default:`, and the macOS demo is unchanged. Everything else is in new `#if os(Windows)` files, the Windows workflow or Windows scripts. `Package.swift`, `ci.yml` and the boundary script are untouched, so macOS behaviour is unchanged.

## G7 (fine apart from the entries)

- **Typing:** `WS_EX_NOACTIVATE` + `MA_NOACTIVATE`. A field drops the style and activates only once clicked, and hands the keyboard back on send or Escape.
- **Engine process:** the shell starts the engine from an argument list with no console and reads its stderr to the end on its own thread. It finds no network listener and builds no shell string.
- **`LoginItem`:** HKCU `Run` only, path quoted, never in the demo or a snapshot.
- **Test hooks:** `--snapshot` forces the demo. `smoke-shell.ps1` and `ui-check.ps1` use temporary profiles and `--demo`.
- **Other:**
  - Mouse capture is taken on press.
  - Display keys are monitor interface paths.
  - No new packages.

## Tests

- **Meaningful:**
  - The 1.0/1.1 compatibility test removes the 1.1 fields and reads the state.
  - `ProtocolWriterTests`.
  - `WindowsTimeZoneTests`: real ICU mapping, and offset against `GetTimeZoneInformation`.
  - `smoke-shell.ps1`: 13 pictures; blank or too-small pictures and status ≠ 0 fail.
  - `ui-check.ps1`: real focus, typing, drag and full-screen checks.
- **Gaps:** card routing (would have caught BLOCKING 1), 1.4 parsing and patch.
- **Flakiness:** `ui-check.ps1` is timing-based with fixed sleeps, and opt-in. The time-zone test would fail if daylight-saving adjustment is turned off on the machine.

## TASK.md M7 list

| Item | Status | Notes |
| --- | --- | --- |
| Tray | Done | Settings, Statistics, Quit |
| Island | Done | Per display, non-activating |
| Dock | Partial | Edges and drag; no Simple panel, logo size, spacing, showsLogos, per-screen look, or move to another display (D-051) |
| Panel | Partial | No balances, account grouping, notices, 24-hour tokens, session title or row total (D-043) |
| Approval cards | Done but defective | BLOCKING 1 and 2 |
| Reminders | Done | Replies are not listed beside a waiting request; no session return or token-usage action (D-047) |
| Settings | Partial | General pane only; no unsupported-client display (BLOCKING 3) |
| Statistics | Partial | Recent usage card only (D-049) |
| `--demo` | Done | |
| Per-Monitor-V2 | Done | Manifest |
| Multi-monitor | Done | |
| Hot-plug | Done | `DisplaySettingsChanged` |
| Full-screen | Done | Optional in TASK |

The partial items that need protocol additions are acceptable for M7 once each is recorded with an owner (BLOCKING 3). The TASK §3 settings display and D-043's M7 commitments are not acceptable as they stand.

VERDICT: CHANGES_REQUESTED
