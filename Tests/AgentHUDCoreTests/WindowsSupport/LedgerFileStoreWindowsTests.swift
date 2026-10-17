#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// LedgerFileStoreTests' unreadable-log case on Windows, where clearing a file's POSIX permissions only sets its
/// read-only attribute: here the log is made unreadable by a handle that shares nothing, as a client that holds its log
/// exclusively would (SKIPPED_TESTS.md).
final class LedgerFileStoreWindowsTests: XCTestCase, @unchecked Sendable {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    private enum Requests: TailLog {
        static let source = "fixture"
        static let summaryKey = "keys"
        static let version = 1
        static func summary(for url: URL) -> [String] { [] }
        static func ingest(_ lines: Data, at offset: Int, into keys: inout [String]) -> [UsageLedger.Event] {
            lines.split(separator: 0x0A).map { line in
                let parts = String(decoding: line, as: UTF8.self).split(separator: " ").map(String.init)
                keys.append(parts[0])
                return UsageLedger.Event(key: parts[0], timestamp: LedgerFileStoreWindowsTests.base, agentId: "fixture-model:m",
                                         tokensIn: Int(parts[1])!, tokensOut: 0)
            }
        }
    }

    private func tokens(_ ledger: UsageLedger) async throws -> Int {
        try await ledger.buckets(since: .distantPast, source: Requests.source).reduce(0) { $0 + $1.tokensIn }
    }

    func testMissingLogLeavesTheLedgerWhileAListedUnreadableLogStays() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let ledger = UsageLedger.inMemory()
        let kept = root.appendingPathComponent("kept.log"), gone = root.appendingPathComponent("gone.log")
        try "a 10\n".write(to: kept, atomically: true, encoding: .utf8)
        try "b 5\n".write(to: gone, atomically: true, encoding: .utf8)
        let store = TailLogStore<Requests>(roots: [root], ledger: ledger, watchesChanges: false) { _ in true }
        _ = await store.index(since: .distantPast, timeBudget: 5)
        var total = try await tokens(ledger)
        XCTAssertEqual(total, 15)
        try "a 10\nc 1\n".write(to: kept, atomically: true, encoding: .utf8)
        let lock = Win32.withWide(kept.path.replacingOccurrences(of: "/", with: "\\")) {
            CreateFileW($0, DWORD(GENERIC_READ), 0, nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let lock, lock != Win32.invalidHandle else { return XCTFail("the log is held exclusively") }
        try FileManager.default.removeItem(at: gone)
        let pass = await store.index(since: .distantPast, timeBudget: 5)
        CloseHandle(lock)
        XCTAssertEqual(pass.failures.count, 1)
        total = try await tokens(ledger)
        XCTAssertEqual(total, 10, "the deleted log leaves; the unreadable one keeps what it recorded")
        let files = try await ledger.fileStates(source: Requests.source)
        XCTAssertEqual(files.keys.map { URL(fileURLWithPath: $0).lastPathComponent }, ["kept.log"])
    }
}
#endif
