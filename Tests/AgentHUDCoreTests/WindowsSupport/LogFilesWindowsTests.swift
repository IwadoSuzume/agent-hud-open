#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// The cases of LogFilesTests that need their fixture behind a link, with the link a Windows junction: the macOS
/// temporary folder sits behind `/var` → `/private/var`, Windows' does not (SKIPPED_TESTS.md).
final class LogFilesWindowsTests: XCTestCase {
    private final class Visits { var paths: [String] = [] }

    /// A folder reached through a junction: the junction's path, and the real one the listing names files by.
    private func junctioned() throws -> (link: URL, real: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud-junction-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real"), link = base.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let cmd = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["SystemRoot"] ?? #"C:\Windows"#) + #"\System32\cmd.exe"#)
        let made = Process()
        made.executableURL = cmd
        made.arguments = ["/c", "mklink", "/J", link.path.replacingOccurrences(of: "/", with: "\\"),
                          real.path.replacingOccurrences(of: "/", with: "\\")]
        made.standardOutput = FileHandle.nullDevice
        try made.run()
        made.waitUntilExit()
        XCTAssertEqual(made.terminationStatus, 0, "the junction is made")
        addTeardownBlock {
            _ = Win32.withWide(link.path.replacingOccurrences(of: "/", with: "\\")) { RemoveDirectoryW($0) }
            try? FileManager.default.removeItem(at: base)
        }
        let resolved = URL(fileURLWithPath: try XCTUnwrap(WindowsPaths.finalPath(link.path)))
        return (link, resolved)
    }

    private func write(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "a 1\n".write(to: url, atomically: false, encoding: .utf8)
    }

    private func listing(_ roots: [URL], visits: Visits) -> LogFiles {
        LogFiles(roots: roots, watchesChanges: false, skips: { $0.lastPathComponent == "tool-results" }) {
            visits.paths.append($0.path)
            return $0.pathExtension == "jsonl"
        }
    }

    func testANewDirectoryIsListedWithoutItsSiblingsOrOtherRoots() throws {
        let (root, listed) = try junctioned()
        let other = try junctioned().link, visits = Visits()
        XCTAssertNotEqual(listed.path, root.path, "the fixture sits behind a junction")
        for session in 0..<20 { try write(root.appendingPathComponent("project/s\(session).jsonl")) }
        try write(other.appendingPathComponent("o.jsonl"))
        let files = listing([root, other], visits: visits)
        files.refresh(now: Date())
        XCTAssertEqual(files.files.count, 21)

        let added = root.appendingPathComponent("project/s3/subagents")
        try write(added.appendingPathComponent("agent-1.jsonl"))
        try write(added.appendingPathComponent("agent-2.jsonl"))
        visits.paths = []
        files.noteChanges([listed.appendingPathComponent("project/s3").path,
                           root.appendingPathComponent("project/s3/subagents").path, "C:/elsewhere/project"])
        XCTAssertEqual(files.refresh(now: Date()).unreadable, 0)

        let keyed = listed.appendingPathComponent("project/s3/subagents")
        XCTAssertNotNil(files.files[keyed.appendingPathComponent("agent-1.jsonl").path], "keyed as the full listing keys them")
        XCTAssertNotNil(files.files[keyed.appendingPathComponent("agent-2.jsonl").path])
        XCTAssertEqual(files.files.count, 23)
        XCTAssertEqual(visits.paths.count, 3, "the subfolder and its two files, each once: \(visits.paths)")
        XCTAssertTrue(visits.paths.allSatisfy { $0.hasPrefix(listed.appendingPathComponent("project/s3").path + "/") })
    }

    func testARootCreatedAfterTheFirstListingTakesEventsByItsRealPath() throws {
        let (base, _) = try junctioned()
        let visits = Visits()
        let root = base.appendingPathComponent("home/projects")
        let files = listing([root], visits: visits)
        files.refresh(now: Date())
        XCTAssertTrue(files.files.isEmpty)

        let log = root.appendingPathComponent("p/a.jsonl")
        try write(log)
        let named = URL(fileURLWithPath: try XCTUnwrap(WindowsPaths.finalPath(root.path)))
        XCTAssertNotEqual(named.path, root.path, "the fixture sits behind a junction")
        files.noteChanges([named.path, named.appendingPathComponent("p").path])
        files.refresh(now: Date())
        XCTAssertEqual(Set(files.files.keys), [named.appendingPathComponent("p/a.jsonl").path])
    }
}
#endif
