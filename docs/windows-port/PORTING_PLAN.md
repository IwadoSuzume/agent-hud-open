# Porting plan

File-level checklist of every macOS dependency in the code the Windows build compiles, how it is handled, and in which
milestone. Built from the M0 spike (`spike-m0` branch): every compiler error Core and its tests raised on Swift 6.4.1
for Windows, plus the runtime differences found while doing it. Status: ✅ done in the spike (to be committed in the
milestone named), 🔶 stub (compiles, feature reported unsupported), 🔷 later milestone.

Conventions (DECISIONS.md D-006): a macOS file replaced on Windows stays untouched and is listed in
`windowsReplaced` in `Package.swift`; its Windows twin with the same API is `Platform/Windows/<Name>+Windows.swift`.
Other shared files get `#if os(Windows)` around single statements or functions only.

## 1. Build system

| Item | Handling | Milestone |
| --- | --- | --- |
| `Package.swift` declares `platforms: [.macOS(.v14)]` and Desktop/App targets | `#if os(Windows)` manifest branch: Support, Core, their tests, Windows-only system modules; the `#else` branch is the original manifest byte for byte | M1 ✅ |
| `import SQLite3` (7 files) | system library `SQLite3` over `winsqlite3` (`Sources/SQLite3Windows`), ADR-003 | M3 ✅ |
| WinHTTP not in Swift's `WinSDK` module | system library `CWinHTTP` (`Sources/CWinHTTP`) | M3 ✅ |
| `NtQueryInformationProcess` | `linkerSettings: [.linkedLibrary("ntdll")]` on Core (Windows branch) | M3 ✅ |
| Non-ASCII repository path breaks the test DLL link | build through an ASCII junction (D-007); `scripts/build-windows.ps1` does it itself | M1 (CI is ASCII), M8 ✅ local |
| Toolchain warnings (`WinSDK` `wchar_t` modularization, `strerror` deprecated) | recorded as the warning baseline in PROGRESS.md; not ours to fix | M1 |

## 2. AgentHUDSupport

| File | macOS dependency | Handling | Milestone |
| --- | --- | --- | --- |
| `RecordCoding.swift` | `CryptoKit.SHA256` | `#if canImport(CryptoKit)` import; `CryptoKitShim.swift` + `PortableDigest.swift` (ADR-004); NIST vectors, CryptoKit cross-check on macOS, golden fixture on both | M2 ✅ |
| `JSONValue.swift` | `memchr` etc. (CRT) | available in ucrt | — |

## 3. AgentHUDCore — imports

| Files | Import | Handling | Milestone |
| --- | --- | --- | --- |
| 13 files | `Darwin` | `#if canImport(Darwin)`; CRT names come through Foundation on Windows | M3 ✅ |
| `DemoStage`, `FileChangeMonitor`, `UnixSocketListener` | `os` | guarded; `OSAllocatedUnfairLock` shim (`PosixCompat.swift`); Windows twins of the other two | M3 ✅ |
| `PermissionRequests`, `MCPAppChannel`, `UnixSocketListener` | `Network` | guarded; `NWConnection` is `PipeConnection` on Windows (`NamedPipes.swift`) | M3 ✅ |
| `CopilotClient`, `ProviderHTTP` | `Security` | guarded; Credential Manager / WinHTTP | M3 ✅ / M4 |
| `VendorCatalog`, `FileChangeMonitor` | `CoreServices` | guarded; `applications(_:)` returns `[]` on Windows | M3 ✅ |
| `CodexDaemonOriginTransport`, `GrokBotSessions`, `OpenAgentCredentials` | `CryptoKit` | guarded; shim | M2 ✅ |
| `DeepSeekQuestionObserver`, `ProviderHTTP` | (URLSession) | `#if canImport(FoundationNetworking)` | M3 ✅ |
| `PermissionRequests` | (`@Observable` without `import Observation`) | `import Observation` (harmless on macOS) | M3 ✅ |

## 4. AgentHUDCore — System and platform services

| macOS file / call | Windows implementation (`Platform/Windows/`) | Notes | Milestone |
| --- | --- | --- | --- |
| `System/AppSupport.swift` `~/Library/Application Support/Agent HUD Open` | `WindowsFolders.roamingAppData` → `%APPDATA%\Agent HUD Open` | `#if` in `directory` | M3 ✅ |
| `System/InstanceLock.swift` (`flock`, `~/Library/Caches/app.agenthud/instance.lock`) | `InstanceLock+Windows.swift`: share-mode lock, `%LOCALAPPDATA%\app.agenthud\instance.lock`, path+pid record | D-009; Windows tests | M3 ✅ code / tests 🔷 |
| `System/UnixSocket.swift`, `UnixSocketListener.swift` (`AF_UNIX`, `NWListener`) | `NamedPipes.swift`: `UnixSocket`, `UnixSocketListener`, `PipeConnection` (= `NWConnection`) | D-010; Windows tests | M3 ✅ code / tests 🔷 |
| `System/ChildProcess.swift` (`Process`, `fcntl`, `kill`) | `ChildProcess+Windows.swift`: `CreateProcessW`, handle list, job, `CREATE_NO_WINDOW` | D-011; Windows tests | M3 ✅ code / tests 🔷 |
| `System/FileChangeMonitor.swift` (FSEvents) | `FileChangeMonitor+Windows.swift`: `ReadDirectoryChangesW`, overflow = dropped | Windows tests | M3 ✅ code / tests 🔷 |
| `System/ProcessLines.swift` `strcasestr` | `PosixCompat.swift` `strcasestr` | | M3 ✅ |
| `os.Logger` | `PlatformLog.swift` (`OutputDebugStringW`, opt-in stderr) | only paths/states/codes | M3 ✅ |
| `realpath`, `memmem`, `proc_pidpath`, `MAXPATHLEN`, `pid_t`, `uid_t`, `getuid` | `PosixCompat.swift` | `getuid` fails closed (D-013); `realpath` = `GetFinalPathNameByHandleW` | M3 ✅ |
| `open(2)`/`read(2)` of a file (`ZstandardReader`) | `WindowsFiles.openForReading` (`_wsopen_s`, binary, no-inherit, UTF-16 path) | ANSI-path bug avoided | M3 ✅ |
| `stat(2)` signature (`ReadOnlySQLite`) | `WindowsFiles.signature` (volume, file index, size, write time) | | M3 ✅ |
| `NSString.abbreviatingWithTildeInPath` (`SessionProject`) | `FoundationGaps.swift` | | M3 ✅ |
| `DispatchSource.makeFileSystemObjectSource` (`PermissionTranscript`) | 250 ms timer source on Windows | D-016 | M3 ✅ |
| `signal`/`alarm` in `PermissionHookClient` | `HookWatchdog.swift` | | M5 ✅ code / tests 🔷 |
| `MCPStdio` `read`/`write`/`poll`/`SIGPIPE` | `_read`/`_write` branches | | M5 ✅ |
| `MCPAppClient` socket timeouts and `poll` | `MCPAppClient+Windows.swift` (pipe with deadline) | | M5 ✅ code / tests 🔷 |
| `HookProcessOrigins.ancestors` (`proc_pidinfo`, `KERN_PROCARGS2`) | `HookProcessOrigins+Windows.swift` (Toolhelp parent chain, `CommandLineToArgvW`) | environment never read | M5 ✅ code / tests 🔷 |
| `ProviderCommand` `/bin/ps`, `/usr/sbin/lsof` | `WindowsProcesses.swift` (D-012) | | M4 ✅ code / tests 🔷 |
| `ProviderHTTP.requestData` (`URLSession.bytes`, `serverTrust`) | `ProviderHTTP+Windows.swift` (WinHTTP, D-014) | | M4 ✅ code / tests 🔷 |
| Keychain `gh:github.com` (`CopilotCredentials.genericPassword`) | `WindowsCredentials.swift`: `CredReadW("gh:github.com:")` (go-keyring target format) | gh's `hosts.yml` on Windows is `%AppData%\GitHub CLI\hosts.yml` → `#if` in `hostsFile` | M4 🔷 |
| `HookInbox`/`HookSettings` `.posixPermissions` | ignored by Foundation on Windows; files live in the user's profile, whose ACL is the user's | verify and document | M5 🔷 |
| `HookCommand.make` (POSIX single-quoting) | Windows quoting per client shell (cmd/PowerShell/Git Bash), `.exe`, backslashes | **key risk**, per-client research | M5 🔷 |
| `HookCommand.isTransient` (`/Volumes`, AppTranslocation) | Windows: `%TEMP%`, a zip's extraction folder in Temp, removable/network drives | | M5 🔷 |

## 5. AgentHUDCore — providers and features

Each provider: research the Windows client's data location from official documentation or the client's source;
without such a source the client is "not supported on Windows" (SUPPORT_MATRIX.md). Fixture tests in temporary
directories only.

| Area | macOS specifics | Plan | Milestone |
| --- | --- | --- | --- |
| Claude Code | `~/.claude`, `~/.config/claude`, engine at `~/.local/bin`, Homebrew, `…/Claude/claude-code/<v>/<b>/claude.app` | `%USERPROFILE%\.claude`; engine `claude.exe` (native installer `~\.local\bin\claude.exe`), npm shim → resolve to node + `cli.js` (no `.cmd`) | M4 |
| Claude Desktop sessions | `~/Library/Application Support/Claude` | `%APPDATA%\Claude` if documented | M4 |
| Codex CLI/Desktop | `CODEX_HOME`/`~/.codex`, `/Applications/Codex.app` | `%USERPROFILE%\.codex`; `codex.exe` from npm's native package; Desktop IPC 🔶 | M4 |
| Codex daemon origins, terminal origins, Grok session origins | unix socket, `proc_*`, iTerm2 | 🔶 unsupported (session jump) | — |
| DeepSeek Harness | `DSH_HOME`, `lsof` on profile files, Node | home path research; liveness via Restart Manager (🔶 until done) | M4 |
| Antigravity | `ps`+`lsof`, `.app` paths, `agy` | Windows command-line patterns (`language_server_windows_x64.exe`?), install path research | M4 |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` | `%APPDATA%\Cursor\User\globalStorage\state.vscdb` (VS Code layout) | M4 |
| Grok CLI / Grok Bot | `~/.grok`, `~/Library/Application Support/Grok Bot` | research | M4 |
| OpenCode, Kimi, GLM, Pi | XDG-style dot folders | same under `%USERPROFILE%` where the client documents it | M4 |
| GitHub Copilot CLI | `~/.copilot`, gh keychain | `%USERPROFILE%\.copilot`; Credential Manager | M4 |
| OpenClaw, Hermes, ZCode, CodeBuddy, WorkBuddy, Qwen, Qoder | dot folders, SQLite | research each | M4 |
| `VendorCatalog.applications` (Launch Services) | 🔶 `[]` | providers check Windows install paths themselves | M4 |
| `ProviderData` `/Applications/<vendor>.app` presence | Windows install locations | | M4 |

## 6. Tests

Files excluded from the Windows test target (`windowsSkippedTests` in `Package.swift`); each must be in
SKIPPED_TESTS.md with its reason and Windows counterpart.

| Test file | Why | Windows counterpart | Milestone |
| --- | --- | --- | --- |
| `System/UnixSocketListenerTests` | AF_UNIX files, `stat` | `WindowsSupport/NamedPipesTests` | M3 |
| `System/ChildProcessTests` | `/bin/sh`, signals | `WindowsSupport/ChildProcessWindowsTests` (cmd.exe/PowerShell children) | M3 |
| `System/InstanceLockTests` | macOS bundle paths, `flock` | `WindowsSupport/InstanceLockWindowsTests` | M3 |
| `MCP/MCPAppChannelTests` | raw AF_UNIX squatter sockets | port to pipes | M5 |
| `Hooks/Permission/PermissionHookTests` | raw AF_UNIX client, `flock` (most cases are pure logic) | split: logic runs on Windows, socket cases ported to pipes | M5 |
| `Hooks/Permission/DeepSeekQuestionObserverTests` | raw BSD TCP WebSocket test server | port the server to Winsock or to a Foundation-free loopback helper | M4 |
| `Providers/Codex/CodexDaemonOriginTransportTests`, `CodexDesktopTestServer`, `CodexDesktopPermissionsTests`, `CodexDesktopStreamTests` | unix-socket servers for features unsupported on Windows | none (feature 🔶) | — |

## 7. New code

| Item | Where | Milestone |
| --- | --- | --- |
| Engine executable (`AgentHUDEngine`, Windows only) | `Sources/AgentHUDEngine` | M6 |
| Versioned shell↔engine protocol + JSON Schema + shared fixtures | `docs/windows-port/PROTOCOL.md`, `windows/protocol/` | M6 |
| WPF shell, tests | `windows/AgentHUD`, `windows/AgentHUD.Tests` | M7 |
| Windows CI | `.github/workflows/windows.yml` | M1 |
| Build/package script | `scripts/build-windows.ps1` | M8 |
| Boundary check over `windows/` | `scripts/check-source-boundaries.py` | M1 (UTF-8 reading), M7 (windows/ rules) |

## 8. Spike results (2026-10-16, Swift 6.4.1, Windows 11 26200, x86_64)

- `swift build --target AgentHUDSupport`: passes. `swift build --target AgentHUDCore`: passes after §1–§4.
- `swift build --build-tests`: passes with the §6 exclusions (through the ASCII junction, D-007).
- `swift test`: AgentHUDSupportTests 5/5 pass (swift-testing). AgentHUDCoreTests **1282 run, 9 skipped, 1244 pass,
  38 test cases fail** (93 assertion failures), in 108 s. The failures, by cause:

| Cause | Tests | Plan | Milestone |
| --- | --- | --- | --- |
| Fake engines written as `#!/bin/sh` scripts cannot be started (`CreateProcessW` error 193/3) | ClaudeEngineTests ×4, ClaudeCodeProviderTests ×5, CodexProviderTests.testClientPerformsHandshake…, ProviderAccountTests, SubscriptionTests, UsageInsightsTests, AntigravityCLITests ×2, MCPClientTests.testACommandRuns…, OpenCode/Pi observer tests (run `node`) | a Windows test helper executable that plays a scripted engine; Node-based tests run only where `node.exe` is on `PATH` (skipped otherwise, as on a Mac without Node) | M4 |
| Locators look in macOS places (`/Applications`, `Library/Application Support`, `.bun/bin`) | ClaudeEngineTests ×2, CodexProviderTests ×3, DeepSeekDesktopTests, MCPClientTests.testAClientIsFound… | Windows locations per SUPPORT_MATRIX, Windows variants of the tests | M4 |
| macOS bundle paths in the instance-lock holder | MCPToolsOffTests ×2 | Windows holder record (D-009); Windows variants | M5 |
| Symbolic links (need Developer Mode or elevation on Windows) and the `/var`→`/private/var` alias the tests rely on | SessionProjectTests ×4, LogFilesTests ×2 | Windows variants using junctions, or skip with reason | M3 |
| POSIX permission bits | ClientHooksTests.testASettingsFileKeptAsALink… | Windows: permissions are the file's ACL; test that the ACL is kept | M5 |
| To investigate | AdditionalProviderTests.testAntigravityReadsWALDatabase… (a read-only open must create no file beside a database — privacy/no-write rule), LedgerFileStoreTests.testMissingLog…, TencentBuddyProviderTests (5 s difference in a time), OpenClawProviderTests (title) | root-cause each | M3/M4 |
