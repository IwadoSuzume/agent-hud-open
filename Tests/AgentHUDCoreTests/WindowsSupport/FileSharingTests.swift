#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// Reading a client's file must never stop the client from writing, renaming or deleting it: every way Core opens a
/// client's file on Windows shares reading, writing and deletion.
final class FileSharingTests: XCTestCase {
    private func file() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud share \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("会话.jsonl")
        try Data("{\"a\":1}\n".utf8).write(to: url)
        return url
    }

    /// Whether a writer can open `url` for appending, as a client does, while the reader holds it.
    private func writerCanOpen(_ url: URL) -> Bool {
        let handle = Win32.withWide(url.path.replacingOccurrences(of: "/", with: "\\")) {
            CreateFileW($0, DWORD(FILE_APPEND_DATA), DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE) | DWORD(FILE_SHARE_DELETE),
                        nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != Win32.invalidHandle else { return false }
        CloseHandle(handle)
        return true
    }

    func testAFoundationFileHandleLetsTheWriterIn() throws {
        let url = try file()
        let reader = try XCTUnwrap(FileHandle(forReadingAtPath: url.path))
        defer { try? reader.close() }
        _ = try reader.read(upToCount: 4)
        XCTAssertTrue(writerCanOpen(url), "FileHandle(forReadingAtPath:) shares writing")
    }

    func testTheZstandardAndSignatureReadsLetTheWriterIn() throws {
        let url = try file()
        let descriptor = WindowsFiles.openForReading(url.path)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { _close(descriptor) }
        XCTAssertTrue(writerCanOpen(url), "the C runtime descriptor shares writing")
        XCTAssertNotNil(WindowsFiles.signature(url.path))
    }

    func testAReadOnlyDatabaseLetsTheWriterIn() throws {
        let url = try file().deletingLastPathComponent().appendingPathComponent("state.db")
        let connection = try SQLiteConnection(url: url)
        try connection.execute("CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1);")
        let reader = try ReadOnlySQLite(url)
        try reader.rows("SELECT x FROM t") { _ in }
        XCTAssertTrue(writerCanOpen(url))
        withExtendedLifetime(connection) {}
    }
}
#endif
