# Porting plan

File-level checklist of every macOS dependency in the code the Windows build compiles, how it is handled, and in which
milestone. Built from the M0 spike (`spike-m0`, commit `809e047`): every compiler error Core and its tests raised on
Swift 6.4.1 for Windows, the runtime differences found while doing it, and the gaps the M0 review found by grep.

Status: **S** the code exists in the spike and is re-applied, with its tests, in the milestone named; **N** new work in
that milestone; **U** compiled out on Windows, the feature reported unsupported (SUPPORT_MATRIX.md).

Conventions (DECISIONS.md D-006): a macOS file replaced on Windows stays untouched — not even its imports are edited —
and is listed in `windowsReplaced` in `Package.swift`; its Windows twin with the same API is
`Platform/Windows/<Name>+Windows.swift`. Other shared files get `#if os(Windows)` around single statements or
functions only.

## 1. Build system

| Item | Handling | Milestone |
| --- | --- | --- |
| `Package.swift` declares `platforms: [.macOS(.v14)]` and Desktop/App targets | `#if os(Windows)` manifest branch with Support and its tests (M1), Core, its tests and the Windows-only system modules (M3), the engine (M6); the `#else` branch is the original manifest, plus Support's test fixtures (M2) | M1 N, M2, M3 S |
| `import SQLite3` (7 files) | system library `SQLite3` over `winsqlite3` (`Sources/SQLite3Windows`), ADR-003; version check (D-003) | M3 S + N |
| WinHTTP not in Swift's `WinSDK` module | system library `CWinHTTP` (`Sources/CWinHTTP`) | M3 S |
| `NtQueryInformationProcess` | `linkerSettings: [.linkedLibrary("ntdll")]` on Core (Windows branch) | M3 S |
| Non-ASCII repository path breaks the test DLL link | build through a per-user ASCII junction (D-007); CI paths are ASCII; `scripts/build-windows.ps1` makes the junction itself | M1, M8 N |
| Boundary check read files in the system code page and fed CR LF to `git check-ignore` on Windows | fixed in M0 (UTF-8, bytes) | M0 ✅ |
| Toolchain warnings (`WinSDK` `wchar_t` modularization; `strerror` deprecated in `MCPStdio`) | the warning baseline in PROGRESS.md | M1 |

## 2. AgentHUDSupport

| File | macOS dependency | Handling | Milestone |
| --- | --- | --- | --- |
| `RecordCoding.swift` | `CryptoKit.SHA256` | guarded import; `CryptoKitShim.swift` + `PortableDigest.swift` (ADR-004) | M2 S |
| (tests) | — | NIST vectors, CryptoKit cross-check on macOS, golden fixture on both (`RecordCodingGoldenTests`) | M2 N |
| `JSONValue.swift` | `memchr` etc. | available in the C runtime | — |

## 3. AgentHUDCore — imports

| Files | Import | Handling | Milestone |
| --- | --- | --- | --- |
| 13 files (8 not replaced) | `Darwin` | `#if canImport(Darwin)` in the files not replaced; CRT names come through Foundation on Windows | M3 S |
| `DemoStage` | `os` | guarded; `OSAllocatedUnfairLock` shim (`PosixCompat.swift`) | M3 S |
| `PermissionRequests`, `MCPAppChannel` | `Network` | guarded; `NWConnection` is `PipeConnection` on Windows (`NamedPipes.swift`) | M3/M5 S |
| `CopilotClient`, `ProviderHTTP` | `Security` | guarded; Credential Manager / WinHTTP | M4 S |
| `VendorCatalog` | `CoreServices` | guarded; `applications(_:)` returns `[]` on Windows | M3 S |
| `CodexDaemonOriginTransport`, `GrokBotSessions`, `OpenAgentCredentials` | `CryptoKit` | guarded; shim | M2 S |
| `DeepSeekQuestionObserver`, `ProviderHTTP` | (URLSession) | `#if canImport(FoundationNetworking)` | M3 S |
| `PermissionRequests` | (`@Observable` without `import Observation`) | `import Observation` (harmless on macOS) | M3 S |

## 4. AgentHUDCore — system and platform services

| macOS file / call | Windows implementation (`Platform/Windows/`) | Notes | Milestone |
| --- | --- | --- | --- |
| `System/AppSupport.swift` `~/Library/Application Support/Agent HUD Open` | `WindowsFolders.roamingAppData` → `%APPDATA%\Agent HUD Open` | `#if` in `directory`; env value only if absolute and existing (D-008) | M3 S + N |
| `System/InstanceLock.swift` (`flock`, `~/Library/Caches/…`) | `InstanceLock+Windows.swift` (D-009) | Windows tests | M3 S |
| `System/UnixSocket.swift`, `UnixSocketListener.swift` | `NamedPipes.swift`: `UnixSocket`, `UnixSocketListener`, `PipeConnection` (= `NWConnection`) | D-010 incl. the per-user name key (N); Windows tests | M3 S + N |
| `System/ChildProcess.swift` (`Process`, `fcntl`, `kill`) | `ChildProcess+Windows.swift` (D-011) | quoting over scalars, PE-image check (N); Windows tests | M3 S + N |
| `System/FileChangeMonitor.swift` (FSEvents) | `FileChangeMonitor+Windows.swift`: `ReadDirectoryChangesW`, overflow = dropped | Windows tests | M3 S |
| `System/ProcessLines.swift` `strcasestr` | `PosixCompat.swift` | | M3 S |
| `os.Logger` (in the replaced listener) | `PlatformLog.swift` (`OutputDebugStringW`, opt-in stderr) | paths, states and codes only | M3 S |
| `realpath`, `memmem`, `proc_pidpath`, `MAXPATHLEN`, `pid_t`, `uid_t`, `getuid` | `PosixCompat.swift` | `getuid` fails closed (D-013) | M3 S |
| `open(2)`/`read(2)` (`ZstandardReader`) | `WindowsFiles.openForReading` (`_wsopen_s`, binary, no-inherit, UTF-16 path) | | M3 S |
| `stat(2)` signature (`ReadOnlySQLite`) | `WindowsFiles.signature` (volume, file index, size, write time) | | M3 S |
| `ReadOnlySQLite` on a WAL database without `-wal`/`-shm` | open immutable from the start on Windows (§8.1) | no file written beside a client's database | M3 N |
| `NSString.abbreviatingWithTildeInPath` (`SessionProject`) | `FoundationGaps.swift` | | M3 S |
| `DispatchSource.makeFileSystemObjectSource` (`PermissionTranscript`) | 250 ms timer source on Windows (D-016) | | M5 S |
| **UserDefaults**: `Store/SettingsStore.swift:23,37`, `PanelLayout/PanelLayoutStore.swift:51,65`, `Store/UsageAssembly.swift:9`; ~40 test files use `UserDefaults(suiteName:)` | `SettingsFile` (UserDefaults subclass over `settings.json`, D-018); tests keep their suites in the temporary profile (D-021) | the engine passes `SettingsFile`; the stores are unchanged | M3 N (class + tests), M6 (engine) |
| **Home directory**: `FileManager.default.homeDirectoryForCurrentUser` / `NSHomeDirectory` in 43 Core files | `UserHome.directory` (D-020): `%USERPROFILE%` if absolute and existing, else the token's profile; macOS value unchanged | one-line change per file; boundary check rejects new direct uses in Core; Windows test that `USERPROFILE` is honoured | M3 N |
| **Executables and `PATH`**: `Providers/Kit/Executables.swift:8` (splits on `:`); POSIX candidates in `Claude/ClaudeEngineLocator.swift:19-20`, `Codex/CodexLocator.swift:47`, `DeepSeek/DeepSeekLocator.swift:23`, `DeepSeek/DeepSeekCredentialLocator.swift:29`; `/Applications` in `MCP/MCPClient.swift:82`, `Codex/CodexLocator.swift:18,26`, `Antigravity/AntigravityService.swift:36`, `DeepSeek/DeepSeekScriptRuntime.swift:13`, `Grok/GrokBotLocator.swift:11`, `Kit/ProviderData.swift:55`; colon-joined child `PATH` in `MCP/MCPClientCommand.swift:45`, `Claude/ClaudeEngineUsage.swift:91`, `Codex/CodexAppServerClient.swift:19`; `environment["PATH"]` reads (Windows calls it `Path`) | the rule of D-019: Windows `Executables` accepts only absolute drive/UNC PE images, splits `PATH` on `;` without relative entries, tries `.exe`; each POSIX candidate list and child `PATH` gets a Windows branch; `PATH` read case-insensitively | security: no program in a folder another user can create is ever run | M4 N (each locator with a Windows test) |
| `ProviderCommand` `/bin/ps`, `/usr/sbin/lsof` | `WindowsProcesses.swift` (D-012); anything else refused | | M4 S + N |
| `ProviderHTTP.requestData` (`URLSession.bytes`, `serverTrust`) | `ProviderHTTP+Windows.swift` (WinHTTP, D-014); option results checked, fail closed (N) | | M4 S + N |
| Keychain `gh:github.com` (`CopilotCredentials.genericPassword`) | `WindowsCredentials.swift`: `CredReadW("gh:github.com:")` | `hostsFile` on Windows: `%AppData%\GitHub CLI\hosts.yml` | M4 S + N |
| `signal`/`alarm` in `PermissionHookClient` | `HookWatchdog.swift` | | M5 S |
| `MCPStdio` `read`/`write`/`poll`/`SIGPIPE` | `_read`/`_write` branches | | M5 S |
| `MCPAppClient` socket timeouts and `poll` | `MCPAppClient+Windows.swift` (pipe with deadline) | | M5 S |
| `HookProcessOrigins.ancestors` (`proc_pidinfo`, `KERN_PROCARGS2`) | `HookProcessOrigins+Windows.swift` (Toolhelp parent chain, `CommandLineToArgvW`) | environments never read | M5 S |
| `Hooks/ClaudeSessionOrigins.swift:100,110`, `Hooks/CodexSessionOrigins.swift:56,92`: iTerm identity from the host's environment, `/bin/sh|bash|zsh` shell sets | U on Windows (no iTerm; session jump unsupported): the origin hooks record the session and time only | | M5 |
| `HookInbox`/`HookSettings` `.posixPermissions` | ignored on Windows; files live in the user's profile; a client's settings file keeps its ACL through `ReplaceFileW` (D-023) | test that the ACL is kept | M5 N |
| `HookCommand.make` (POSIX single-quoting) | per client: Claude Code's exec form (`command` + `args`, no shell, `.exe` required — Claude Code *Hooks* docs); others per their documented shell | **key risk** | M5 N |
| `HookCommand.isTransient` (`/Volumes`, AppTranslocation) | Windows: `%TEMP%`, a zip extracted in Temp, removable and network drives | | M5 N |
| Path comparison: `Store/UsageCollector.swift:348` (changed paths), `Providers/Kit/ClientHome.swift:11-12` (id hash of a path), `Providers/Kit/Logs/LogFiles.swift:202` (aliases), `Models/Sessions/SessionProject.swift:28,55` | case-insensitive on Windows only (D-023); ids keep their macOS spelling rules | Windows tests with differently-cased paths | M3/M4 N |

## 5. AgentHUDCore — providers and features

Each provider: research the Windows client's data location from official documentation or the client's source;
without such a source the client is "not supported on Windows" (SUPPORT_MATRIX.md). Fixture tests in temporary
directories only.

| Area | macOS specifics | Plan | Milestone |
| --- | --- | --- | --- |
| Claude Code | `~/.claude`, `~/.config/claude`, engine at `~/.local/bin`, Homebrew, `…/Claude/claude-code/<v>/<b>/claude.app` | `%USERPROFILE%\.claude`; engine `%USERPROFILE%\.local\bin\claude.exe`, WinGet, npm's native binary (Claude Code *Advanced setup*) | M4 |
| Claude Desktop sessions | `~/Library/Application Support/Claude` | `%APPDATA%\Claude` only if documented | M4 |
| Codex CLI/Desktop | `CODEX_HOME`/`~/.codex`, `/Applications/Codex.app` | `%USERPROFILE%\.codex`; `codex.exe` from npm's native package; Desktop IPC U | M4 |
| Codex daemon origins, terminal origins, Grok session origins | unix socket, `proc_*`, iTerm2 | U (session jump) | — |
| DeepSeek Harness | `DSH_HOME`, `lsof` on profile files, Node | home path research; liveness via Restart Manager (U until done) | M4 |
| Antigravity | `ps`+`lsof`, `.app` paths, `agy` | Windows command-line patterns and install paths, research | M4 |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` | `%APPDATA%\Cursor\User\globalStorage\state.vscdb` if documented | M4 |
| Grok CLI / Grok Bot | `~/.grok`, `~/Library/Application Support/Grok Bot` | research | M4 |
| OpenCode, Kimi, GLM, Pi | dot folders | same under `%USERPROFILE%` where the client documents it | M4 |
| GitHub Copilot CLI | `~/.copilot`, gh keychain | `%USERPROFILE%\.copilot` if documented; Credential Manager | M4 |
| OpenClaw, Hermes, ZCode, CodeBuddy, WorkBuddy, Qwen, Qoder | dot folders, SQLite | research each | M4 |
| `VendorCatalog.applications` (Launch Services) | U: `[]` | providers check Windows install paths themselves | M4 |
| `ProviderData` `/Applications/<vendor>.app` presence | Windows install locations | | M4 |

## 6. Tests

Files excluded from the Windows test target (`windowsSkippedTests` in `Package.swift`) and runtime skips; each goes in
SKIPPED_TESTS.md (M3) with its reason and Windows counterpart.

| Test file | Why | Windows counterpart | Milestone |
| --- | --- | --- | --- |
| `System/UnixSocketListenerTests` | AF_UNIX files, `stat` | `WindowsSupport/NamedPipesTests` | M3 |
| `System/ChildProcessTests` | `/bin/sh`, signals | `WindowsSupport/ChildProcessWindowsTests` | M3 |
| `System/InstanceLockTests` | macOS bundle paths, `flock` | `WindowsSupport/InstanceLockWindowsTests` | M3 |
| `MCP/MCPAppChannelTests` | raw AF_UNIX squatter sockets | port to pipes | M5 |
| `Hooks/Permission/PermissionHookTests` | raw AF_UNIX client, `flock` (most cases are pure logic) | split: logic runs on Windows, socket cases ported to pipes | M5 |
| `Hooks/Permission/DeepSeekQuestionObserverTests` | raw BSD TCP WebSocket test server | port the server to Winsock | M4 |
| `Providers/Codex/CodexDaemonOriginTransportTests`, `CodexDesktopTestServer`, `CodexDesktopPermissionsTests`, `CodexDesktopStreamTests` | unix-socket servers for features unsupported on Windows | none (feature U) | — |
| Runtime skips seen in the spike | opt-in probes (`…ReadOnlyProbe`, `SessionUsageProbeTests`), tests that need Node or a Zstandard tool absent on the machine (`DeepSeekDesktopTests` ×2, `DeepSeekProviderTests` ×3), `LogFilesTests.testAFileEventInASkippedOrHiddenFolderAddsNothing` | registered with their skip reasons | M3 |

## 7. New code

| Item | Where | Milestone |
| --- | --- | --- |
| Engine executable (`AgentHUDEngine`, Windows only) | `Sources/AgentHUDEngine` | M6 |
| Versioned shell↔engine protocol + JSON Schema + shared fixtures | `docs/windows-port/PROTOCOL.md`, `windows/protocol/` | M6 |
| WPF shell, tests | `windows/AgentHUD`, `windows/AgentHUD.Tests` | M7 |
| Windows CI | `.github/workflows/windows.yml` | M1 |
| Build/package script | `scripts/build-windows.ps1` | M8 |
| Boundary check over `windows/`, new direct home reads in Core | `scripts/check-source-boundaries.py` | M3 (home), M7 (`windows/`) |

## 8. Spike results (2026-10-16, Swift 6.4.1, Windows 11 26200, x86_64)

- `swift build --target AgentHUDSupport`: passes. `swift build --target AgentHUDCore`: passes after §1–§4 (spike part).
- `swift build --build-tests`: passes with the §6 exclusions (through an ASCII junction, D-007).
- `swift test`: AgentHUDSupportTests 5/5 pass (swift-testing). AgentHUDCoreTests: **1282 executed — 1235 pass,
  38 fail (93 assertion failures), 9 skipped at run time** — in 108 s. The failures, by cause:

| Cause | Tests | Plan | Milestone |
| --- | --- | --- | --- |
| Fake engines written as `#!/bin/sh` scripts cannot be started (`CreateProcessW` error 193/3) | ClaudeEngineTests ×4, ClaudeCodeProviderTests ×5, CodexProviderTests.testClientPerformsHandshake…, ProviderAccountTests, SubscriptionTests, UsageInsightsTests, AntigravityCLITests ×2, MCPClientTests.testACommandRuns…, OpenCode/Pi observer tests (run `node`) | a Windows test helper executable that plays a scripted engine; Node-based tests run only where `node.exe` is on `PATH` (skipped otherwise, as on a Mac without Node) | M4 |
| Locators look in macOS places (`/Applications`, `Library/Application Support`, `.bun/bin`) | ClaudeEngineTests ×2, CodexProviderTests ×3, DeepSeekDesktopTests, MCPClientTests.testAClientIsFound… | Windows locations per SUPPORT_MATRIX and D-019, Windows variants of the tests | M4 |
| macOS bundle paths in the instance-lock holder | MCPToolsOffTests ×2 | Windows holder record (D-009); Windows variants | M5 |
| Symbolic links (need Developer Mode or elevation on Windows) and the `/var`→`/private/var` alias the tests rely on | SessionProjectTests ×4, LogFilesTests ×2 | Windows variants using junctions, or skip with reason | M3 |
| POSIX permission bits | ClientHooksTests.testASettingsFileKeptAsALink… | Windows: the ACL is kept (D-023) | M5 |
| To investigate | LedgerFileStoreTests.testMissingLog…, TencentBuddyProviderTests (5 s difference in a time), OpenClawProviderTests (title) | root-cause each | M3/M4 |
| WAL database without its files | AdditionalProviderTests.testAntigravityReadsWALDatabase… | §8.1 | M3 |

### 8.1 Root causes found after the spike

- `AdditionalProviderTests.testAntigravityReadsWALDatabaseWhoseWriterRemovedItsFiles`: the macOS system SQLite
  refuses a read-only open of a WAL database whose `-wal`/`-shm` are gone (`SQLITE_CANTOPEN`), and the reader then
  reads it as immutable; Windows' `winsqlite3` instead **creates** `-wal` and `-shm` beside the client's database.
  That writes into a client's folder, which the rules forbid. Fix (M3, `ReadOnlySQLite`): on Windows, a database whose
  header says WAL (bytes 18–19 = 2) with neither file beside it is opened as immutable from the start.
- The spike's test run left six `AgentHUDTests.*.plist` files in `%LOCALAPPDATA%` and fifty temporary folders
  (removed); from M2 on, tests run in a temporary profile (D-021).
