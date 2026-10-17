# Skipped and excluded tests

Every test that does not run on Windows, with the reason and its Windows counterpart (TASK.md §6 G3). A skip that is
not listed here counts as a failure. Three mechanisms, each listed below:

1. **Excluded files** — test files that do not build on Windows, in `windowsSkippedTests` in `Package.swift`.
2. **Skip list** — tests that build but whose fixture or subject is macOS-specific, in
   `scripts/windows/skipped-tests.txt`, passed to `swift test --skip` by `scripts/windows/test.ps1`.
3. **Runtime skips** — tests that skip themselves (`XCTSkip`) on every platform when an opt-in variable or a tool is
   missing.

State at M3 (2026-10-17, Windows 11 26200, Swift 6.4.1): 1301 pass, 9 runtime skips, 34 listed skips, 10 excluded
files, 0 failures.

## AgentHUDSupportTests

None. `portableDigestsEqualCryptoKit` compiles only where CryptoKit exists: it is the macOS cross-check by design,
and the NIST and golden tests are its Windows counterpart.

## 1. Excluded test files (AgentHUDCoreTests)

| File | Why it does not build on Windows | Windows counterpart | Until |
| --- | --- | --- | --- |
| `System/UnixSocketListenerTests.swift` | AF_UNIX socket files, `stat`, `S_IFSOCK` | `WindowsSupport/NamedPipesTests` (9 tests) | permanent |
| `System/ChildProcessTests.swift` | `/bin/sh` children, signals | `WindowsSupport/ChildProcessWindowsTests` (13) | permanent |
| `System/InstanceLockTests.swift` | macOS bundle paths, `flock` | `WindowsSupport/InstanceLockWindowsTests` (5) | permanent |
| `MCP/MCPAppChannelTests.swift` | raw AF_UNIX squatter sockets | to port to pipes | M5 |
| `Hooks/Permission/PermissionHookTests.swift` | raw AF_UNIX client, `flock` (most cases are pure logic) | split: logic on Windows, socket cases on pipes | M5 |
| `Providers/Codex/CodexDaemonOriginTransportTests.swift` | unix-socket daemon stand-in | none: the feature is not supported on Windows (SUPPORT_MATRIX) | permanent |
| `Providers/Codex/CodexDesktopTestServer.swift` | unix-socket Desktop stand-in (helper of the next two) | none, as above | permanent |
| `Providers/Codex/CodexDesktopPermissionsTests.swift` | uses the server above | none, as above | permanent |
| `Providers/Codex/CodexDesktopStreamTests.swift` | uses the server above | none, as above | permanent |

## 2. Skip list (`scripts/windows/skipped-tests.txt`)

| Test | Why | Windows counterpart | Until |
| --- | --- | --- | --- |
| `LedgerFileStoreTests/testMissingLogLeavesTheLedgerWhileAListedUnreadableLogStays` | makes a log unreadable with POSIX permissions, which on Windows only set the read-only attribute | `LedgerFileStoreWindowsTests` (the log held exclusively) | permanent |
| `LogFilesTests/testANewDirectoryIsListedWithoutItsSiblingsOrOtherRoots`, `…/testARootCreatedAfterTheFirstListingTakesEventsByItsRealPath` | rely on the temporary folder sitting behind a symbolic link (`/var` → `/private/var`) | `LogFilesWindowsTests` (behind a junction) | permanent |
| `SessionProjectTests/testLinkedWorktreesAndTheirSubdirectoriesBelongToTheMainRepository`, `…/testNestedRepositoriesAndUnrelatedDirectoriesStaySeparate`, `…/testRelativeGitPointerAndDirectoryAliasUseTheSameRepository` | run `/usr/bin/git` and make a symbolic link (Developer Mode or elevation on Windows) | `SessionProjectWindowsTests` (Git from `PATH`, a junction, Windows root spellings, case) | permanent |
| `AntigravityCLITests/testOnlyARunningAgyProgramIsAsked` | copies `/bin/sleep` to stand for a running `agy` | `ProviderEnginesWindowsTests.testOnlyARunningAgyProgramIsAsked` (the fake engine as `agy.exe`) | permanent |
| `CodexProviderTests/testClientPerformsHandshakeWithoutStartingSession` | the app server is a Python script | `ProviderEnginesWindowsTests.testCodexClientPerformsHandshakeWithoutStartingSession` (the same replies from the fake engine) | permanent |
| `CodexProviderTests/testLocatorFindsTheAppUnderItsBundleIDWhateverItIsCalled`, `…/testLocatorPrefersTheDesktopEngineWhereCurrentBuildsKeepIt`, `…/testLocatorWorksWithoutDesktopOrWithoutCLI` | macOS install places (`.app` bundles, `.bun/bin`) | `WindowsExecutablesTests.testCodexIsFoundWhereNpmInstallsItsEngine`; the desktop app is not supported on Windows (SUPPORT_MATRIX) | permanent |
| `MCPClientTests/testAClientIsFoundWhereItsCommandIsInstalled`, `…/testACommandRunsFromTheHomeFolderAndIsStoppedWhenItTakesTooLong` | macOS install places; `/bin/sh` and `/bin/sleep` as the commands | `ProviderEnginesWindowsTests` (same names) | permanent |
| `DeepSeekDesktopTests` ×3 (`testTheBalanceHelperReadsTheCredentialThroughTheDesktopApp`, `testTheDesktopAppIsFoundByNameAndRunAsNode`, `testWithoutACLIInstallTheDesktopAppSuppliesThePackageAndItsRuntime`) | the DeepSeek Harness desktop app, which no source places on Windows: the Windows build never looks for it (D-036) | `ProviderPathsWindowsTests.testClientsWithoutAWindowsSourceAreNeverRead` | permanent |
| `DeepSeekQuestionObserverTests/testCancellingIdleWebSocketClosesTheConnectionWithoutAHostFrame` | swift-corelibs' `URLSessionWebSocketTask` ends a stream on which the host sends nothing ("Empty reply from server"), measured against the Winsock host `IdleQuestionHost+Windows.swift` | the observer's WebSocket on WinHTTP | M5 |
| `ClientHooksTests/testASettingsFileKeptAsALinkIsWrittenWhereItLeadsAndKeepsItsPermissions` | POSIX permission bits | an ACL-keeping test (D-023) | M5 |
| `MCPToolsOffTests/testABundledHolderCountsByTheDataDirectoryItsBundleNames`, `…/testAnUnservedSocketIsOffWhileTheApplicationHoldsTheLockAndNotRunningOtherwise` | macOS bundle paths in the instance lock's holder | Windows holder record tests (D-009) | M5 |

## 3. Runtime skips (all platforms)

| Test | Skips itself when |
| --- | --- |
| `AdditionalProviderTests/testInstalledSourcesReadOnlyProbe` | `AGENT_HUD_PROBE_ADDITIONAL` is unset (opt-in probe of installed clients) |
| `AntigravityPermissionsTests/testInstalledAntigravityPermissionsReadOnlyProbe` | `AGENT_HUD_PROBE_ANTIGRAVITY` is unset |
| `GrokAccountLinkTests/testInstalledConfirmedAccountCacheProbe` | `AGENT_HUD_PROBE_GROK_CACHE` is unset |
| `SessionUsageProbeTests/testReportedSessionsUsageProbe` | `AGENT_HUD_PROBE_SESSION_USAGE` and its paths are unset |
| `DeepSeekProviderTests` ×3 (compressed logs) | Node.js with Zstandard support is not installed (on Windows: no `node.exe` on `PATH`; they run where it is, as on this machine since M4) |
| `OpenCodeSessionObserverTests/testNativePluginRecordsOnlyFinishedTurnsOfTopLevelSessions`, `PiSessionObserverTests/testNativeExtensionLifecycleRetriesHeartbeatAndPrivacy` | on Windows only: no `node.exe` on `PATH` (`TestNode`, D-034) |
