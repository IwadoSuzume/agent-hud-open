// The Windows SDK's copy of SQLite, winsqlite3.dll in System32, under the module name the macOS SDK uses, so that
// `import SQLite3` reads the same on both (docs/windows-port/adr/ADR-003-sqlite.md). Built on Windows only.
#include <winsqlite/winsqlite3.h>
