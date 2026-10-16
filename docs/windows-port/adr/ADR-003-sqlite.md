# ADR-003: SQLite on Windows — the system `winsqlite3` exposed as module `SQLite3`

- Status: accepted (M0, 2026-10-16)

## Context

Core opens SQLite in seven files (`Ledger/SQLiteConnection.swift`, `Providers/Kit/ReadOnlySQLite.swift`, and the
Antigravity, Hermes, OpenClaw and ZCode readers) through `import SQLite3`, the macOS SDK's module. The calls used
(collected with `grep -rhoE 'sqlite3_[a-z0-9_]+'`) are the core C API only: `open_v2`, `prepare_v2/v3`
(`SQLITE_PREPARE_PERSISTENT`), `step`, `column_*`, `bind_*`, `exec`, `busy_timeout`, `progress_handler`, `limit`,
`close_v2`, `errmsg`, `free`. SQL features used: WAL journal mode, `PRAGMA user_version`, `json_each` and
`json_extract` (the ledger's `IN (SELECT value FROM json_each(?))` and Cursor's `composerHeaders` read), `strftime`
with `'unixepoch'` and a fixed `'+8 hours'` offset (no `localtime`), and `?immutable=1` URIs (`SQLITE_OPEN_URI`).

Options:

1. **System `winsqlite3.dll`** (in `System32` on every Windows 10/11 SKU), with `winsqlite/winsqlite3.h` and
   `winsqlite3.lib` from the Windows SDK.
2. **SQLite amalgamation** vendored as a local C target (public domain), registered in THIRD_PARTY_NOTICES and the
   boundary check.
3. A Swift SQLite package — rejected: external package dependency.

## Evidence

On this machine (Windows 11 10.0.26200), `winsqlite3.dll` reports (queried with P/Invoke from PowerShell):

```
sqlite3_libversion() = 3.51.1
THREADSAFE=1, MUTEX_W32, OMIT_LOCALTIME, ENABLE_FTS5, ENABLE_RTREE, MAX_VARIABLE_NUMBER=32766 …
```

JSON functions are built into SQLite from 3.38.0 on (no `ENABLE_JSON1` needed), so `json_each`/`json_extract` work.
`OMIT_LOCALTIME` does not matter: no query uses the `localtime` modifier. The headers and import library are in
`Windows Kits\10\Include\<ver>\um\winsqlite\` and `Lib\<ver>\um\x64\winsqlite3.lib`.

Risk: the DLL's version follows the OS build. Windows 10 22H2 ships an older `winsqlite3` whose version is not
documented by Microsoft; if it predates 3.38 the JSON functions are missing.

## Decision

Option 1. `Package.swift` declares, **on Windows only**, a `systemLibrary` target named `SQLite3` (directory
`Sources/SQLite3Windows`, a `module.modulemap` with `link "winsqlite3"` and a shim header that includes
`<winsqlite/winsqlite3.h>`). Because the module carries the same name as the macOS SDK module, no Swift file changes:
`import SQLite3` resolves to the SDK on macOS and to `winsqlite3` on Windows.

On Windows, both the ledger (`SQLiteConnection`) and the read-only reader of clients' databases (`ReadOnlySQLite`,
whose Cursor query uses `json_extract`) check `sqlite3_libversion_number() >= 3038000` before use; below that the
ledger is unavailable with a notice (the application then runs without history, as it does when the ledger cannot
be opened on macOS) and a client database read fails as a failed read of that source, never of another. The Windows
CI job logs `sqlite3_libversion()` of its image, and the version on Windows 10 22H2 is recorded in SUPPORT_MATRIX.md
when one is available to test on. If the check fires on supported systems in practice, option 2 is the fallback and
needs a new ADR.

`winsqlite3` also differs from the macOS SQLite on one point that matters (spike, PORTING_PLAN.md §8.1): a read-only
connection to a WAL database whose `-wal`/`-shm` files are gone creates them, where macOS refuses. `ReadOnlySQLite`
therefore opens such a database as immutable from the start on Windows, so that reading never writes into a client's
folder (M3).

Evidence the choice works: in the spike `UsageLedgerTests`, `HermesProviderTests`, `ZCodeProviderTests` and
`OpenAgentProviderTests` passed against `winsqlite3`; `LedgerFileStoreTests`, `OpenClawProviderTests` and
`TencentBuddyProviderTests` passed but for one case each, under investigation (PORTING_PLAN.md §8).

## Consequences

- No new source or binary is added to the repository; nothing changes on macOS (the target does not exist there).
- The Windows build depends on the Windows SDK's `winsqlite` headers, which every SDK since 10.0.10586 carries.
- SQLite behaviour on Windows is that of the OS copy; tests run against it on the CI image.
