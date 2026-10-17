#if os(Windows)
import Foundation
import XCTest
@testable import AgentHUDCore

/// Which programs the Windows build looks for and may start (Platform/Windows/WindowsExecutables.swift,
/// WindowsCodex.swift; DECISIONS.md D-011, D-019).
final class WindowsExecutablesTests: XCTestCase {
    private let system = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["SystemRoot"] ?? #"C:\Windows"#) + #"\System32"#)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud 程序 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A copy of a real Windows program at `relative` under `folder`.
    private func program(_ relative: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: system.appendingPathComponent("whoami.exe"), to: url)
        return url
    }

    func testPathEntriesAreAbsoluteFoldersSeparatedBySemicolons() {
        let found = Executables.onPath("codex", path: #"C:\Tools;;relative\bin;"D:\Quoted Folder";\\server\share\bin;/usr/bin"#)
        XCTAssertEqual(found.map { $0.lastPathComponent }, ["codex.exe", "codex.exe", "codex.exe"])
        XCTAssertEqual(found.map { $0.deletingLastPathComponent().lastPathComponent }, ["Tools", "Quoted Folder", "bin"])
        XCTAssertEqual(Executables.onPath("tool.EXE", path: #"C:\Tools"#).map(\.lastPathComponent), ["tool.EXE"])
    }

    func testPathIsReadWhateverTheCaseOfItsName() {
        XCTAssertEqual(Executables.path(in: ["Path": #"C:\One"#, "HOME": "x"]), #"C:\One"#)
        XCTAssertEqual(Executables.path(in: ["PATH": #"C:\Two"#]), #"C:\Two"#)
        XCTAssertEqual(Executables.path(in: [:]), "")
    }

    func testOnlyExistingProgramImagesAtAbsolutePathsAreStarted() throws {
        let folder = try directory()
        let real = try program("bin/tool.exe", in: folder)
        let batch = folder.appendingPathComponent("bin/shim.cmd")
        try Data("@echo off\r\n".utf8).write(to: batch)
        let fake = folder.appendingPathComponent("bin/fake.exe")
        try Data("#!/usr/bin/env node\n".utf8).write(to: fake)
        let renamedBatch = folder.appendingPathComponent("bin/shim.bat. .")
        try? Data("@echo off\r\n".utf8).write(to: renamedBatch)

        XCTAssertEqual(Executables.first([batch, fake, folder.appendingPathComponent("bin/missing.exe"), real])?.lastPathComponent, "tool.exe")
        XCTAssertNil(Executables.first([batch, fake, renamedBatch, folder.appendingPathComponent("bin")]))
        // POSIX candidates the shared locators list resolve against the current drive's root: never started.
        XCTAssertNil(Executables.first([URL(fileURLWithPath: "/usr/bin/env"), URL(fileURLWithPath: "/opt/homebrew/bin/node")]))
    }

    /// D-019's rule itself, with programs that do exist: a path without a drive or share names a folder at the current
    /// drive's root, which any user may create, so it is refused even where a real program sits behind it.
    func testADrivelessPathIsRefusedEvenWhereAProgramExists() throws {
        for path in ["/opt/homebrew/bin/node", "/Applications", "/usr/local/bin/claude"] {
            XCTAssertFalse(WindowsFolders.isAbsolute(URL(fileURLWithPath: path).path), path)
        }
        // A real program, and the current directory on its drive, so that its driveless spelling reaches the same file
        // whichever drive the tests started on (the checkout is on D: in CI).
        let folder = try directory()
        let tool = try program("bin/tool.exe", in: folder)
        XCTAssertNotNil(WindowsExecutables.program(tool), "the drive-qualified spelling is a program")
        let started = FileManager.default.currentDirectoryPath
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(folder.path))
        defer { _ = FileManager.default.changeCurrentDirectoryPath(started) }
        // The same program spelled from the current drive's root, as `/opt/homebrew/bin/node` is on macOS.
        let rootRelative = String(tool.path.drop { $0 != "/" && $0 != "\\" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootRelative), "the driveless spelling reaches the same file: \(rootRelative)")
        XCTAssertNil(WindowsExecutables.program(URL(fileURLWithPath: rootRelative)), rootRelative)
        XCTAssertNil(Executables.first([URL(fileURLWithPath: rootRelative), URL(fileURLWithPath: String(rootRelative.dropLast(4)))]))
        XCTAssertTrue(Executables.onPath("whoami", path: #"\Windows\System32;Windows\System32"#).isEmpty,
                      "PATH entries without a drive are skipped")
    }

    func testACandidateWithoutAnExtensionIsLookedForAsAnExe() throws {
        let folder = try directory()
        _ = try program("bin/claude.exe", in: folder)
        XCTAssertEqual(Executables.first([folder.appendingPathComponent("bin/claude")])?.lastPathComponent, "claude.exe")
    }

    func testCodexIsFoundWhereNpmInstallsItsEngine() throws {
        let appData = try directory()
        XCTAssertNil(Executables.first(WindowsCodex.engines(appData: appData)))
        let fallback = try program("npm/node_modules/@openai/codex/vendor/x86_64-pc-windows-msvc/bin/codex.exe", in: appData)
        XCTAssertEqual(Executables.first(WindowsCodex.engines(appData: appData))?.path, fallback.path)
        let nested = try program("npm/node_modules/@openai/codex/node_modules/@openai/codex-win32-x64/vendor/x86_64-pc-windows-msvc/bin/codex.exe",
                                 in: appData)
        XCTAssertEqual(Executables.first(WindowsCodex.engines(appData: appData))?.path, nested.path)
        // npm's batch shim beside them is never a candidate.
        let shim = appData.appendingPathComponent("npm/codex.cmd")
        try Data("@echo off\r\n".utf8).write(to: shim)
        XCTAssertNil(Executables.first(Executables.onPath("codex", path: appData.appendingPathComponent("npm").path)))
    }
}
#endif
