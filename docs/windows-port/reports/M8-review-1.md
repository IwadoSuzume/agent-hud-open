# M8 review, round 1

- **Milestone:** M8 (Packaging)
- **Round:** 1
- **Range:** `git diff 00847af...94bb659`. That is `f686f1b` (step 1, the portable package, D-055) and `94bb659` (step 2, two timing fixes, D-056).
- **Worktree:** `E:\agenthud-dev\wt7` (branch `m7-work`)
- **Reviewer:** port-reviewer (read-only)

## What was checked

**Read first.** TASK.md (§1, §4 M8, §6, §8), PROGRESS, DECISIONS (D-055, D-056), PORTING_PLAN and the full diff.

**Evidence used for the notices.**
- The developer's research copies in `E:\agenthud-dev\m8research`:
  - `utils/build.ps1` and `update-checkout-config.json` at the 6.4.1 scheme;
  - the licence texts fetched at their tags.
- The installed runtime `%LOCALAPPDATA%\Programs\Swift\Runtimes\6.4.1\usr\bin`, inspected read-only for embedded strings.

**Behaviour checked under Windows PowerShell 5.1** (read-only commands only):
- `2>$null` on a failing native command, with `$ErrorActionPreference = 'Stop'`;
- where `swift --version` writes its output;
- `.Target` of the existing D-007 junction.

**Not run by me:** the build or the package check. That is the tester's job.

### Results, with no finding

1. **macOS.**
   - `MCPTools.swift`: only the doc comment moved. Both string literals are byte-identical.
   - `ProcessLinesTests`: the macOS assertion `XCTAssertLessThan(each, 0.02)` is unchanged in the `#else` branch.
   - `FileChangeMonitor+Windows.swift` is Windows-only.
   - `ci.yml` is untouched.
2. **CI.** One build step and one `upload-artifact` step (`if-no-files-found: error`). Permissions stay `contents: read`. No release, no signing, no new secrets.
3. **Junction (D-007).**
   - The junction is made only when the repository path is not ASCII, and only at `%LOCALAPPDATA%\agenthud-dev\src`.
   - It is never deleted or retargeted. An existing junction that leads elsewhere, or a plain folder, makes the script throw.
   - Under 5.1, `.Target` of the real junction reads back as `E:\桌面项目\agent-hud-open`, so the comparison works.
4. **External commands.** All are invoked with `&` and argument lists; there are no shell strings. `$LASTEXITCODE` is checked after:
   - `build.ps1`;
   - `dotnet publish`;
   - `check-package.ps1` (which uses `exit 1`, and `build-windows.ps1` checks it).

   `swift --version` writes to stdout only (verified), so its `2>&1` is safe under 5.1.
5. **File list and entry names.**
   - The 28 expected files match the stage. Every entry is prefixed `Agent HUD Open/` with forward slashes.
   - The check fails on a missing or extra file, on a backslash, and on a missing library: status 0xC0000135, run with only System32 and Windows on PATH. The engine's `main.swift` really ends with `exit(2)`.
   - It fails on a changed notice in three ways: package against repository, root against `Sources/AgentHUDDesktop/Resources/THIRD_PARTY_NOTICES.txt` (§8), and RUNTIME_NOTICES against `windows/packaging`.
   - The root and bundled `THIRD_PARTY_NOTICES.txt` are byte-identical at HEAD (`cmp`).
6. **RUNTIME_NOTICES texts.** Texts A–G match the fetched files exactly.
   - libdispatch's LICENSE is byte-identical to corelibs-foundation's (text B).
   - string-processing's LICENSE is identical to swift's (text A).
   - swift-foundation-icu's is identical to swift-foundation's (text C).
   - `_FoundationICU.dll` embeds `icudt76`.
   - The 6.4.1 scheme pins curl `curl-8_9_1`, zlib `v1.3.1` and brotli `v1.2.0`. `Build-CURL` uses Schannel, zlib and brotli, with no nghttp2, ssh or OpenSSL.
   - `FoundationNetworking.dll` contains curl 8.9.1, zlib 1.3.1 and brotli strings. `Foundation.dll` contains none of them.
   - BlocksRuntime is built from libdispatch's `src/BlocksRuntime`.
7. **Visual C++ runtime and framework-dependent shell.** Reasoned and documented in D-055.
   - The shell names the Redistributable on 0xC0000135 (`Package.IsMissingLibrary`, tested).
   - No NuGet packages ship.
8. **LoginItem.** The gate is now positive: the marker must be in `AppContext.BaseDirectory` (tested). Turning launch at login on or off is gated the same way.
9. **README data folders.** `%APPDATA%\Agent HUD Open` (`AppSupport`, `SettingsFile`) and `%LOCALAPPDATA%\app.agenthud` (`InstanceLock+Windows`) match the code.
10. **D-056, test bound.** The `ProcessLinesTests` Windows bound is a minimal `#if os(Windows)` branch, documented in the test and in D-056. The existence check costs one `GetFileAttributesExW` per watched root per call. The existing-directory results are unchanged unless that call fails.

## Findings

[BLOCKING] Sources/AgentHUDCore/Platform/Windows/FileChangeMonitor+Windows.swift:180 — `consumeChanges()`/`consumePaths()` report "everything changed" on every call while a watched directory is missing, until `update()` runs. `aWatchedDirectoryIsGone` is checked anew each call and nothing latches it. The callers make this costly:
- `LogFiles.refresh` calls `update()` first, so it is unaffected.
- `UsageCollector.gatherSignals` (UsageCollector.swift:275) calls `consumePaths()` on every pass, but calls `update()` only in the fallback read, every `UsageRefresh.accountInterval` = 300 s (line 214–217).
- So after a client's watched folder is deleted, every collect pass for up to 5 minutes sets `needsFetch` and does a full read of every source. Passes come roughly every 5 s through `pollInterval` or the log checks. That is up to about 60 full listings.

Before this commit, Windows reported this once, through the ended watch's `record(nil)`. macOS also reports it once: its stream is created without `kFSEventStreamCreateFlagWatchRoot`, so `RootChanged` is never delivered. The removal arrives as one batch naming the path, and `isWatching` stays true. The comment's claim "as FSEvents reports a changed root on macOS" is therefore wrong, and so is D-056's.

— Report a removal once per `update()` cycle. For example, keep a `reportedGone` set that `update()` clears, or stop the vanished directory's watch and `changes.record(nil)` once. Then a later `consumePaths()` returns the other watches' paths (or `[]`), and `consumeChanges()` returns false when nothing else happened. Extend `testAWatchedDirectoryThatGoesAwayAsksForAFullScan` to assert the second call. Correct the comment at :195–197 and D-056 (DECISIONS.md:63) so they describe the real macOS behaviour.

[BLOCKING] windows/packaging/RUNTIME_NOTICES.txt:20 — The notices omit a component that ships. `FoundationEssentials.dll` statically contains swift-collections, built as `_FoundationCollections`: `build.ps1` passes `_SwiftCollections_SourceDIR` to the Foundation build, the 6.4.1 scheme pins `swift-collections` `1.1.6`, and the DLL holds `s22_FoundationCollections` symbols. No `_FoundationCollections.dll` ships. Neither the file nor D-055 (DECISIONS.md:62) names it, although both present curl, zlib and brotli as the statically linked set. Its licence is the same Apache 2.0 with the Runtime Library Exception, so this is a completeness and accuracy gap in a notices file, not a missing licence text. TASK §8 and G8 still ask for it. — Add `FoundationEssentials.dll also contains swift-collections 1.1.6 (https://github.com/apple/swift-collections, tag 1.1.6) — Apache License 2.0 with the Runtime Library Exception`. Use its own LICENSE.txt as a new text, or point to the identical text after comparing them. Update D-055's sentence to match.

[NON_BLOCKING] scripts/build-windows.ps1:230 — `& git -C $root rev-parse HEAD 2>$null` runs under `$ErrorActionPreference = 'Stop'`. In Windows PowerShell 5.1 a stderr line, even one sent to `$null`, becomes a terminating NativeCommandError (verified). So in a source tree without git metadata (a downloaded source zip), the script throws instead of falling back to `commit = 'unknown'`. pwsh 7.2+ is unaffected, which is why CI is fine. — Wrap the two git calls in a local `$ErrorActionPreference = 'Continue'` scope, as `build.ps1` does, or use `try`/`catch`, then keep the `$LASTEXITCODE` test. Line 191's `--show-bin-path 2>$null` has the same exposure if SwiftPM ever warns. It is harmless today but deserves the same treatment.

[NON_BLOCKING] scripts/windows/check-package.ps1:90 — `StandardError.ReadToEnd()` and then `StandardOutput.ReadToEnd()` block until the engine closes its pipes. A hung engine therefore never reaches `WaitForExit(30000)`, and the 30 s bound is ineffective. — Read both streams asynchronously (`ReadToEndAsync`), or call `WaitForExit(30000)` first and read afterwards.

[NON_BLOCKING] scripts/build-windows.ps1:195 — The runtime folder is the first PATH entry holding `swiftCore.dll`. The script checks the compiler's version but not this folder's. If another runtime comes earlier on PATH, the zip would carry libraries that RUNTIME_NOTICES.txt does not describe. — Require the folder to be the 6.4.1 runtime, for example by path `...\Runtimes\6.4.1\usr\bin` or by `swiftCore.dll`'s file version, and throw otherwise.

[NON_BLOCKING] windows/packaging/README.txt:16 — "The clients' hooks and MCP servers run agenthud-engine.exe … turn off Settings > Client hooks first" overstates what the switch covers.
- Client hooks removes only hook entries. MCP servers are added by the user with the client's own command (docs/command-line.md:112–115) and are not removed by the switch; step 1 of "Removing it" (line 20) has the same gap.
- Moving the folder leaves the `Run` value pointing at the old path. `FollowLaunchAtLogin` → `RegisterIfNeverRegistered` sees a value of ours and leaves it, so after a move or an upgrade into a new folder, the old copy, or nothing, starts at login.

— In the README, say that an MCP entry is removed with the client's `mcp remove` command, and that Launch at login should be turned off before a move or upgrade and on again afterwards. Better still, have `RegisterIfNeverRegistered` rewrite a value of ours whose command differs from `Command`.

[NON_BLOCKING] windows/packaging/RUNTIME_NOTICES.txt:1 — `AgentHUD.exe` is the .NET apphost: Microsoft's MIT-licensed native host from dotnet/runtime, with the app's name patched in. The package carries no notice for it. — Add a short entry for the .NET apphost (MIT, https://github.com/dotnet/runtime, LICENSE.TXT), or record in D-055 why none is needed.

[NON_BLOCKING] scripts/build-windows.ps1:134 — The claim "the same commit and toolchain give the same entries" holds for names, order and times. The bytes of `LICENSE.txt`, `THIRD_PARTY_NOTICES.txt`, `README.txt` and `RUNTIME_NOTICES.txt`, however, depend on the builder's `core.autocrlf`, because `.gitattributes` covers only `windows/protocol/**`. CRLF is the default on Windows and on the runner. — Either say "entries" means names and times only, or pin the eol of the four packaged text files in `.gitattributes`. If you pin them, keep the root and bundled `THIRD_PARTY_NOTICES.txt` identical (§8).

[NON_BLOCKING] docs/windows-port/PROGRESS.md:28 — G8 drift in PROGRESS:
- The M8 row describes step 1 only; step 2 (`94bb659`, D-056) is missing.
- Next-steps item 13 (lines 123–128) still reads "next: commit, push, CI…".
- The known issue at line 149, "For M8: launch at login's 'installed copy' gate … is a path test", is done by D-055 but still listed.

— Add step 2 to the M8 row. Update item 13. Remove line 149, or mark it resolved in M8 (D-055).

## Summary

The packaging work itself is sound:
- **Scripts:** argument-list invocations, exit codes checked, the junction confined to its own path.
- **Package check:** an exact file list and real failure modes (a missing library, a changed notice, root against bundled notices).
- **CI:** artifact only, permissions unchanged.
- **LoginItem:** a positive marker gate.
- **macOS:** no change.
- **Notice texts:** each matches its source at the cited tag.

Two items block:
1. **D-056's monitor change** makes the collector repeat full reads for up to 5 minutes after a watched folder disappears, and it misstates the macOS semantics it claims to match.
2. **RUNTIME_NOTICES.txt and D-055** omit swift-collections, which `FoundationEssentials.dll` embeds statically.

VERDICT: CHANGES_REQUESTED
