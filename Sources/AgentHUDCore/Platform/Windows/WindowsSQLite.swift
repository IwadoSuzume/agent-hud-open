#if os(Windows)
import Foundation
import SQLite3

/// What the Windows build needs to know about the system's SQLite, `winsqlite3.dll` (ADR-003).
enum WindowsSQLite {
    /// The library's version, such as `3.51.1`.
    static var version: String { String(cString: sqlite3_libversion()) }

    /// Whether the library has the JSON functions the ledger and the Cursor reader use: SQLite 3.38 or later.
    static var isSupported: Bool { sqlite3_libversion_number() >= 3_038_000 }

    /// Whether the database at `path` is in WAL mode (its header's write and read versions are 2) and neither its
    /// `-wal` nor its `-shm` file is beside it, as when its writer removed them on close.
    static func isWALWithoutItsFiles(_ path: String) -> Bool {
        guard !["-wal", "-shm"].contains(where: { FileManager.default.fileExists(atPath: path + $0) }),
              let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 20), header.count == 20 else { return false }
        return header.starts(with: Array("SQLite format 3\0".utf8)) && header[18] == 2 && header[19] == 2
    }
}
#endif
