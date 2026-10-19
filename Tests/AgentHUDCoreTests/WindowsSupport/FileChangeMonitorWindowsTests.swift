#if os(Windows)
import Foundation
import XCTest
@testable import AgentHUDCore

/// The Windows file watch (Platform/Windows/FileChangeMonitor+Windows.swift): what changed is named by its full path
/// as Foundation writes paths, a first check and a dropped batch ask for a full scan, and directories that appear later
/// are watched after `update()`.
final class FileChangeMonitorWindowsTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud watch 监视 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Waits until `condition` holds, for up to five seconds.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    func testChangedFilesAreNamedByTheirFullPath() async throws {
        let root = try directory()
        let woken = Woken()
        let monitor = FileChangeMonitor(directories: [root]) { woken.mark() }
        XCTAssertTrue(monitor.isWatching)
        XCTAssertNil(monitor.consumePaths(), "the first check asks for a full scan")
        let nested = root.appendingPathComponent("projects/a b")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("会话.jsonl")
        try Data("{}\n".utf8).write(to: file)
        var seen: Set<String> = []
        let found = try await eventually {
            if let paths = monitor.consumePaths() { seen.formUnion(paths) }
            return seen.contains(file.standardizedFileURL.path)
        }
        XCTAssertTrue(found, "events name \(file.path); saw \(seen)")
        XCTAssertTrue(woken.count > 0, "each batch wakes the reader")
        XCTAssertFalse(seen.contains { $0.contains("\\") }, "paths are written with forward slashes")
    }

    func testNothingChangedReadsAsNoChangeOnceSeen() async throws {
        let root = try directory()
        let monitor = FileChangeMonitor(directories: [root])
        XCTAssertTrue(monitor.consumeChanges(), "the first check counts as a change")
        XCTAssertFalse(monitor.consumeChanges(), "nothing happened since")
        try Data("x".utf8).write(to: root.appendingPathComponent("a.txt"))
        let changed = try await eventually { monitor.consumeChanges() }
        XCTAssertTrue(changed)
    }

    func testADirectoryCreatedLaterIsWatchedAfterAnUpdate() async throws {
        let root = try directory()
        let later = root.appendingPathComponent("later")
        let monitor = FileChangeMonitor(directories: [later])
        XCTAssertFalse(monitor.isWatching, "nothing to watch yet: sources are read on a schedule")
        XCTAssertNil(monitor.consumePaths())
        try FileManager.default.createDirectory(at: later, withIntermediateDirectories: true)
        monitor.update()
        XCTAssertTrue(monitor.isWatching)
        XCTAssertNil(monitor.consumePaths(), "a newly watched directory asks for a full scan")
        let file = later.appendingPathComponent("x.jsonl")
        try Data("1".utf8).write(to: file)
        var seen: Set<String> = []
        let found = try await eventually {
            if let paths = monitor.consumePaths() { seen.formUnion(paths) }
            return seen.contains(file.standardizedFileURL.path)
        }
        XCTAssertTrue(found)
    }

    func testAWatchedDirectoryThatGoesAwayAsksForAFullScan() async throws {
        let root = try directory()
        let watched = root.appendingPathComponent("watched")
        try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        let monitor = FileChangeMonitor(directories: [watched])
        _ = monitor.consumePaths()
        try FileManager.default.removeItem(at: watched)
        // At once, whether or not the watch heard of it: an empty directory's removal names nothing inside it.
        XCTAssertNil(monitor.consumePaths(), "what changed under a removed directory is unknown")
        XCTAssertTrue(monitor.consumeChanges(), "and counts as a change")
        monitor.update()
        XCTAssertFalse(monitor.isWatching)
    }

    func testNestedDirectoriesAreWatchedOnceWhateverTheirCase() throws {
        let root = try directory()
        let inner = root.appendingPathComponent("Inner")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let upper = URL(fileURLWithPath: root.path.uppercased())
        let monitor = FileChangeMonitor(directories: [inner, upper])
        XCTAssertTrue(monitor.isWatching)
    }
}

private final class Woken: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func mark() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
#endif
