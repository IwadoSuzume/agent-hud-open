# ADR-001: Overall architecture — the Swift core on Windows, a WPF shell, stdio between them

- Status: accepted (M0, 2026-10-16)

## Context

Agent HUD Open is ~64k lines of Swift: ~34k in `AgentHUDSupport` + `AgentHUDCore` (providers, ledger, stores, alert
rules, panel layout, MCP, hooks) and ~30k in `AgentHUDDesktop` (SwiftUI/AppKit). TASK.md §2 proposes keeping the Swift
core and writing a native Windows shell, and asks M0 to prove or refute it with a spike before anything else.

## Evidence (spike on branch `spike-m0`, Swift 6.4.1 for Windows, Windows 11 10.0.26200, x86_64)

1. **AgentHUDSupport compiles unchanged** apart from the CryptoKit import (ADR-004). Build: 11 s.
2. **AgentHUDCore compiles** after:
   - guarding 23 imports (`Darwin`, `os`, `Network`, `Security`, `CoreServices`, `CryptoKit`) with `#if canImport`,
     and adding `FoundationNetworking` (2 files) and `Observation` (1 file, harmless on macOS);
   - replacing 8 files wholesale on Windows through `exclude:` in the Windows branch of `Package.swift`
     (`System/UnixSocket`, `UnixSocketListener`, `ChildProcess`, `FileChangeMonitor`, `InstanceLock`,
     `Providers/Codex/CodexDesktopIPC`) with implementations of the same API in `Sources/AgentHUDCore/Platform/Windows`;
   - small `#if os(Windows)` branches in 15 shared files (each around one statement or one function);
   - two Windows-only system modules: `SQLite3` over `winsqlite3` (ADR-003) and `CWinHTTP` over `winhttp`.
   The compiler errors met, in the order they surfaced, are listed in PORTING_PLAN.md §2 with how each was handled.
   No error required changing business logic.
3. **The Core test target compiles and links** on Windows with 10 test files excluded (sockets, `/bin/sh` children,
   flock): each is listed in SKIPPED_TESTS.md with a Windows replacement planned. The remaining 247 files compile
   unchanged except guarded imports and two test helpers.
4. Foundation on Windows behaves differently in ways that matter and were found during the spike:
   `FileManager.urls(for: .applicationSupportDirectory)` returns `%LOCALAPPDATA%`, `.cachesDirectory` returns `%TEMP%`,
   both trap when an environment override points at a missing folder; `homeDirectoryForCurrentUser` ignores
   `USERPROFILE`; `URL.path` uses forward slashes (`C:/Users/…`); `stat(2)` and `open(2)` of the C runtime take ANSI
   paths (wrong for non-ASCII user names); `URLSession.bytes` and Security-based server trust do not exist.
5. Toolchain limitation: linking a test bundle from a path with non-ASCII characters (`E:\桌面项目\…`) fails inside
   the clang driver's response-file handling; the same tree builds through an ASCII junction. CI paths are ASCII; the
   build script handles local trees (DECISIONS.md D-007).

## Options

| | A. Swift core + native shell (proposed) | B. All Swift (swift-winrt / WinUI) | C. Rewrite core (Rust/Tauri or C#) |
| --- | --- | --- | --- |
| Reuse of tested logic | ~34k lines, 247 test files run on Windows | same core reuse | none: ~34k lines and 250 test files to rewrite |
| UI work | new WPF shell | new WinUI shell through immature bindings (swift-winrt is experimental, no SwiftPM-only build, no XAML tooling) | new shell |
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
- **Transport between them: the engine's standard input and output**, newline-delimited JSON messages of a versioned
  protocol (PROTOCOL.md). The shell starts the engine as its child with `CREATE_NO_WINDOW`; the engine exits when its
  input ends. This replaces the brief's named pipe `\\.\pipe\agenthud-<SID>-ui`: anonymous pipes inherited by one
  child have no name another process can open, so there is nothing to squat or to protect with a DACL, and the
  engine's lifetime follows the shell's. Hook processes and `--mcp` still reach the running engine through named
  pipes (`NamedPipes.swift`), as they reach the app through unix sockets on macOS.
- Single instance: the engine takes `InstanceLock` (`%LOCALAPPDATA%\app.agenthud\instance.lock`); the shell starts at
  most one engine per user session and quits, naming the running copy, when the engine reports the lock held.

## Consequences

- macOS keeps building exactly what it built: the macOS branch of `Package.swift` is the original manifest, and every
  shared-file change is either an import guard or code under `#if os(Windows)`. The macOS CI run is the gate (G1).
- Features whose Windows mechanism is undocumented (Codex Desktop IPC, the Codex daemon's control socket, terminal
  session jumping) are compiled out on Windows behind the same APIs and reported as unsupported in SUPPORT_MATRIX.md.
- The engine's pipeline runs on the main actor as on macOS; the engine's `main` drives the main dispatch queue.
