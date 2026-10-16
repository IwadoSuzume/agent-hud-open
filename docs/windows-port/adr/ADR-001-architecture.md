# ADR-001: Overall architecture — the Swift core on Windows, a WPF shell, stdio between them

- Status: accepted (M0, 2026-10-16; revised after the M0 review)

## Context

Agent HUD Open is ~64k lines of Swift: ~34k in `AgentHUDSupport` + `AgentHUDCore` (providers, ledger, stores, alert
rules, panel layout, MCP, hooks) and ~30k in `AgentHUDDesktop` (SwiftUI/AppKit). TASK.md §2 proposes keeping the Swift
core and writing a native Windows shell, and asks M0 to prove or refute it with a spike before anything else.

## Evidence (spike on branch `spike-m0`, commit `809e047`, Swift 6.4.1 for Windows, Windows 11 10.0.26200, x86_64)

1. **AgentHUDSupport compiles** with one change, the guarded CryptoKit import (ADR-004). Build: 11 s.
2. **AgentHUDCore compiles** after:
   - 27 guarded imports (26 in Core: `Darwin`, `os`, `os.log`, `Network`, `Security`, `CoreServices`, `CryptoKit`;
     1 in Support; 20 remain once D-006 leaves the replaced files unedited), plus `FoundationNetworking` in 2 files
     and `Observation` in 1 (harmless on macOS);
   - **6 files** replaced wholesale on Windows through `exclude:` in the Windows branch of `Package.swift`
     (`System/UnixSocket`, `System/UnixSocketListener`, `System/ChildProcess`, `System/FileChangeMonitor`,
     `System/InstanceLock`, `Providers/Codex/CodexDesktopIPC`), each by a Windows file of the same API in
     `Sources/AgentHUDCore/Platform/Windows`;
   - `#if os(Windows)` branches in **16 shared files** (18 counting the two whose only change is an import), each
     around one statement or one function;
   - two Windows-only system modules: `SQLite3` over `winsqlite3` (ADR-003) and `CWinHTTP` over `winhttp`.
   Every item is listed with its handling and milestone in PORTING_PLAN.md §1–§4. No error required changing business
   logic.
3. **The Core test target compiles and links** on Windows with 10 of its 165 test files excluded (raw sockets,
   `/bin/sh` children, `flock`, macOS bundle paths): PORTING_PLAN.md §6 lists each with its Windows counterpart, and
   SKIPPED_TESTS.md (due in M3, with the Core tests) will register every exclusion and runtime skip. The remaining 155
   files compile with guarded imports and one test-only compatibility file.
4. **The tests run**: AgentHUDSupportTests 5/5 pass; AgentHUDCoreTests executed 1282 tests — 1235 pass, 38 fail,
   9 skip themselves at run time (opt-in probes and tests needing tools absent here) — in 108 s. PORTING_PLAN.md §8
   classifies every failure; none is in the collection pipeline, the ledger, the alert rules or the panel layout.
5. Foundation on Windows behaves differently in ways that matter, found during the spike:
   `FileManager.urls(for: .applicationSupportDirectory)` returns `%LOCALAPPDATA%`, `.cachesDirectory` returns `%TEMP%`,
   both trap when an environment override points at a missing folder; `homeDirectoryForCurrentUser` ignores
   `USERPROFILE`; `UserDefaults` writes `<suite>.plist` straight into `%LOCALAPPDATA%`; `URL.path` uses forward slashes
   (`C:/Users/…`) while POSIX-style absolute paths (`/opt/homebrew/bin/node`) stay drive-relative; the C runtime's
   `stat(2)`/`open(2)` take ANSI paths (wrong for non-ASCII user names); `URLSession.bytes` and Security-based server
   trust do not exist; `winsqlite3` creates `-wal`/`-shm` files where the macOS SQLite refuses to.
6. Toolchain limitation: linking a test bundle from a path with non-ASCII characters (`E:\桌面项目\…`) fails inside
   the clang driver's response-file handling, and the error text is lost; the same tree links through an ASCII junction
   (DECISIONS.md D-007).

## Options

| | A. Swift core + native shell (proposed) | B. All Swift (swift-winrt / WinUI) | C. Rewrite core (Rust/Tauri or C#) |
| --- | --- | --- | --- |
| Reuse of tested logic | ~34k lines; 155 of 165 Core test files run on Windows | same core reuse | none: ~34k lines and 165 test files to rewrite |
| UI work | new WPF shell | new WinUI shell through immature bindings (swift-winrt is experimental, needs its own generator and NuGet packages, no XAML tooling) | new shell |
| Risk of divergence from macOS | low: same code | low | high: every rule exists twice |
| Upstream rebase | shared files keep small `#if` diffs | same | n/a (fork) |

## Decision

**Option A**, refined:

- `agenthud-engine.exe` — a Swift executable (target `AgentHUDEngine`, Windows only) linking Support and Core. It runs
  the collection pipeline (`UsageStore`), the approval channel (`PermissionRequests`), the MCP channel, the hook and
  adapter commands (`HookEntry.handle`), `--mcp`, `--probe` and the demo. It is a console-subsystem program so that
  clients' hooks can run it and read its standard output.
- `AgentHUD.exe` — the WPF shell (ADR-002) in `windows/`. It owns the windows, the tray icon and user input, and
  displays what the engine computed. No rule of Core is re-implemented in C#.
- **Transport between them: anonymous pipes inherited by the engine as its child**, newline-delimited JSON messages of
  a versioned protocol (PROTOCOL.md). The shell starts the engine with `CREATE_NO_WINDOW`; the engine exits when its
  input ends. This replaces the brief's named pipe `\\.\pipe\agenthud-<SID>-ui`: anonymous pipes inherited by one
  child have no name another process can open, so there is nothing to squat or to protect with a DACL, and the
  engine's lifetime follows the shell's (D-005). Hook processes and `--mcp` still reach the running engine through
  named pipes (`NamedPipes.swift`, D-010), as they reach the app through unix sockets on macOS.
- Single instance: the engine takes `InstanceLock` (`%LOCALAPPDATA%\app.agenthud\instance.lock`); the shell starts at
  most one engine per user session and quits, naming the running copy, when the engine reports the lock held.

## Consequences

- macOS keeps building the same products: the macOS branch of `Package.swift` is the original manifest (plus test
  resources where a test of the port needs a fixture), every shared-file change is either an import guard or code
  under `#if os(Windows)`, and the only new code macOS compiles is `PortableDigest.swift` and its tests (ADR-004),
  which the app does not call. The macOS CI run is the gate (G1).
- The protocol channel must carry nothing but protocol: the engine moves its protocol output off file descriptor 1 at
  start (it keeps the inherited handle for the protocol and points the C runtime's and Foundation's standard output at
  standard error), so a stray `print` from shared code cannot inject a message; the shell rejects any line that is not
  a valid message of the current protocol version (D-022, M6).
- Features whose Windows mechanism is undocumented (Codex Desktop IPC, the Codex daemon's control socket, terminal
  session jumping) are compiled out on Windows behind the same APIs and reported as unsupported in SUPPORT_MATRIX.md.
- Nothing at compile time keeps a Windows twin's API in step with its macOS file; the Windows CI build catches drift
  when upstream changes a replaced file (D-006).
- The engine's pipeline runs on the main actor as on macOS; the engine's `main` drives the main dispatch queue.
