#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// SessionProjectTests on Windows: Git from `PATH` instead of `/usr/bin/git`, a junction instead of a symbolic link (which
/// needs Developer Mode or elevation), and Windows' root spellings instead of `/` (SKIPPED_TESTS.md).
final class SessionProjectWindowsTests: XCTestCase {
    private func session(_ path: String?) -> LiveSession {
        LiveSession(id: "session", agentId: "codex", task: "task", terminal: nil, startedAt: Date(),
                    endedAt: nil, pctOfWindow: nil, tokensIn: 0, tokensOut: 0, workingDirectory: path)
    }

    /// Git as `PATH` finds it; the tests that need it are skipped without one, as on a machine without Git.
    private static let git: URL? = {
        let path = ProcessInfo.processInfo.environment.first { $0.key.uppercased() == "PATH" }?.value ?? ""
        return path.split(separator: ";").lazy.map { URL(fileURLWithPath: String($0)).appendingPathComponent("git.exe") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }()

    @discardableResult
    private func git(_ arguments: [String]) throws -> String {
        let git = try XCTUnwrap(Self.git)
        let process = Process(), output = Pipe()
        process.executableURL = git
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(process.terminationStatus, 0, text)
        return text
    }

    private func repository() throws -> (directory: URL, main: URL, worktree: URL) {
        try XCTSkipIf(Self.git == nil, "Git is not on PATH")
        let created = FileManager.default.temporaryDirectory.appendingPathComponent("HUD Project 项目 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: created) }
        // Repositories are named by their final paths, which spell every folder in full: a temporary folder reached
        // through an 8.3 name (`C:/Users/RUNNER~1/…` on CI) is resolved first, so the expected paths are spelled alike.
        let directory = URL(fileURLWithPath: try XCTUnwrap(WindowsPaths.finalPath(created.path)), isDirectory: true)
        let main = directory.appendingPathComponent("main", isDirectory: true)
        let worktree = directory.appendingPathComponent("tree with space", isDirectory: true)
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try git(["init", "-q", main.path])
        try git(["-C", main.path, "-c", "user.name=HUD Tests", "-c", "user.email=tests@example.invalid", "commit", "--allow-empty", "-qm", "Initial"])
        try git(["-C", main.path, "worktree", "add", "--detach", "-q", worktree.path])
        return (directory, main, worktree)
    }

    func testLinkedWorktreesAndTheirSubdirectoriesBelongToTheMainRepository() throws {
        let fixture = try repository()
        for path in [fixture.main, fixture.worktree, fixture.main.appendingPathComponent("Sources"),
                     fixture.worktree.appendingPathComponent("Sources/Feature")] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            XCTAssertEqual(SessionProject(session(path.path)).path?.lowercased(), fixture.main.path.lowercased(), path.path)
        }
    }

    func testAWorkingDirectoryRecordedInItsShortSpellingBelongsToTheMainRepository() throws {
        let fixture = try repository()
        let long = fixture.worktree.path.replacingOccurrences(of: "/", with: "\\")
        let length = Win32.withWide(long) { GetShortPathNameW($0, nil, 0) }
        var buffer = [WCHAR](repeating: 0, count: Int(length) + 1)
        let written = Win32.withWide(long) { GetShortPathNameW($0, &buffer, DWORD(buffer.count)) }
        try XCTSkipIf(written == 0 || Int(written) >= buffer.count, "no short spelling for the fixture")
        let short = String(decodingCString: buffer, as: UTF16.self)
        try XCTSkipIf(short.lowercased() == long.lowercased(), "the volume keeps no 8.3 names")
        XCTAssertEqual(SessionProject(session(short)).path?.lowercased(), fixture.main.path.lowercased(), short)
    }

    func testAJunctionToAWorktreeUsesTheSameRepository() throws {
        let fixture = try repository()
        let alias = fixture.directory.appendingPathComponent("linked-alias")
        let made = Process()
        made.executableURL = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["SystemRoot"] ?? #"C:\Windows"#) + #"\System32\cmd.exe"#)
        made.arguments = ["/c", "mklink", "/J", alias.path.replacingOccurrences(of: "/", with: "\\"),
                          fixture.worktree.path.replacingOccurrences(of: "/", with: "\\")]
        made.standardOutput = FileHandle.nullDevice
        try made.run()
        made.waitUntilExit()
        addTeardownBlock { _ = Win32.withWide(alias.path.replacingOccurrences(of: "/", with: "\\")) { RemoveDirectoryW($0) } }
        XCTAssertEqual(SessionProject(session(alias.path)).path?.lowercased(), fixture.main.path.lowercased())
    }

    func testFoldersThatDifferOnlyInCaseShareTheirRepository() throws {
        let fixture = try repository()
        let sources = fixture.main.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let upper = SessionProject(session(sources.path.uppercased())), lower = SessionProject(session(sources.path.lowercased()))
        XCTAssertEqual(upper, lower)
        XCTAssertEqual(upper.path, WindowsPaths.finalPath(fixture.main.path), "named by the repository's real path")
    }

    func testClientHomesThatDifferOnlyInCaseAreOneHome() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("Codex Home")
        XCTAssertEqual(ClientHome.key(URL(fileURLWithPath: home.path.uppercased()), defaultDirectory: home), "")
        XCTAssertEqual(ClientHome.key(URL(fileURLWithPath: home.path.uppercased()), defaultDirectory: URL(fileURLWithPath: "C:/x")),
                       ClientHome.key(URL(fileURLWithPath: home.path.lowercased()), defaultDirectory: URL(fileURLWithPath: "C:/x")))
        XCTAssertEqual(PathCase.folded("C:/Users/A"), "c:/users/a")
    }

    func testRootPathsTerminateAndKeepTheRecordedDirectory() {
        for path in [#"C:\"#, "C:/", "C:/./", "C:/../", #"\\localhost\c$\"#] {
            XCTAssertEqual(SessionProject(session(path)), .directory(path), "root spellings keep their original fallback path")
        }
    }
}
#endif
