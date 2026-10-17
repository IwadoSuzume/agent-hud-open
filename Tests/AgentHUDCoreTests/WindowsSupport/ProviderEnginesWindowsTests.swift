#if os(Windows)
import Foundation
import XCTest
@testable import AgentHUDCore

/// The Windows counterparts of the provider and MCP tests whose subject is macOS's: the shell the command runner is
/// tried on, the Python script that stands in for Codex's app server, the `sleep` copied to stand for a running `agy`,
/// and the macOS install places (docs/windows-port/SKIPPED_TESTS.md). Each engine is the test program
/// `AgentHUDFakeEngine` (D-034).
final class ProviderEnginesWindowsTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud 引擎 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func same(_ one: String, _ other: String) -> Bool {
        func normal(_ path: String) -> String {
            var path = path.replacingOccurrences(of: "\\", with: "/").lowercased()
            while path.hasSuffix("/") { path.removeLast() }
            return path
        }
        return normal(one) == normal(other)
    }

    /// MCPClientTests.testACommandRunsFromTheHomeFolderAndIsStoppedWhenItTakesTooLong, on programs: standard error
    /// first, the home folder as the working directory, this process's PATH unchanged (D-019), and a command that
    /// takes too long or cannot start.
    func testACommandRunsFromTheHomeFolderAndIsStoppedWhenItTakesTooLong() async throws {
        let folder = try directory()
        let failing = try TestEngine.write([.out("said"), .err("error: no such scope"), .exit(3)], to: folder.appendingPathComponent("failing.exe"))
        let failed = await MCPClientCommand.run(failing, [])
        XCTAssertEqual(failed.status, 3)
        XCTAssertEqual(failed.output, "error: no such scope\nsaid\n", "standard error first")
        XCTAssertEqual(failed.failureLine, "error: no such scope")

        let record = folder.appendingPathComponent("record.json")
        let recorder = try TestEngine.write([.record(record.path)], to: folder.appendingPathComponent("recorder.exe"))
        let place = await MCPClientCommand.run(recorder, ["mcp", "list"])
        XCTAssertTrue(place.succeeded, place.output)
        let facts = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
        XCTAssertEqual(facts["arguments"] as? [String], ["mcp", "list"])
        XCTAssertTrue(same(facts["directory"] as? String ?? "", UserHome.directory.path), "from the home folder: \(facts)")
        XCTAssertEqual(facts["path"] as? String, Executables.systemPath, "PATH is passed on as it is, never with macOS folders")

        let sleeper = try TestEngine.write([.sleep(30)], to: folder.appendingPathComponent("sleeper.exe"))
        let started = Date()
        let slow = await MCPClientCommand.run(sleeper, [], timeout: 0.3)
        XCTAssertNil(slow.status)
        XCTAssertEqual(slow.output, "")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)

        let missing = await MCPClientCommand.run(folder.appendingPathComponent("missing/claude.exe"), ["mcp"])
        XCTAssertNil(missing.status)
        XCTAssertFalse(missing.output.isEmpty, "why it could not start")
        let script = folder.appendingPathComponent("claude.cmd")
        try Data("@echo off\r\n".utf8).write(to: script)
        let batch = await MCPClientCommand.run(script, ["mcp"])
        XCTAssertNil(batch.status, "a batch file is never started")
    }

    /// MCPClientTests.testAClientIsFoundWhereItsCommandIsInstalled, at the Windows install places: the native
    /// installer's `.local\bin\claude.exe` before PATH, never npm's batch shims, never the desktop app's engine.
    func testAClientIsFoundWhereItsCommandIsInstalled() throws {
        let home = try directory()
        let applications = home.appendingPathComponent("Applications", isDirectory: true)
        func found(_ client: MCPClient, path: String = "") -> String? {
            client.executable(home: home, applications: applications, path: path, registered: [])?.path
        }
        XCTAssertNil(found(.claudeCode))
        XCTAssertNil(found(.codex))
        try TestEngine.write([], to: home.appendingPathComponent("Library/Application Support/Claude/claude-code/2.1.300/build/claude.app/Contents/MacOS/claude"))
        XCTAssertNil(found(.claudeCode), "the desktop app's engine is not offered")
        let shims = home.appendingPathComponent("npm", isDirectory: true)
        try FileManager.default.createDirectory(at: shims, withIntermediateDirectories: true)
        for name in ["claude.cmd", "codex.cmd", "claude", "codex"] {
            try Data("@echo off\r\n".utf8).write(to: shims.appendingPathComponent(name))
        }
        XCTAssertNil(found(.claudeCode, path: shims.path), "npm's shims are not programs")
        XCTAssertNil(found(.codex, path: shims.path))
        let tools = try TestEngine.write([], to: home.appendingPathComponent("tools/claude.exe"))
        let codex = try TestEngine.write([], to: home.appendingPathComponent("tools/codex.exe"))
        let path = [shims.path, home.appendingPathComponent("tools").path].joined(separator: ";")
        XCTAssertTrue(same(found(.claudeCode, path: path) ?? "", tools.path), "on PATH")
        XCTAssertTrue(same(found(.codex, path: path) ?? "", codex.path), "on PATH")
        let installed = try TestEngine.write([], to: home.appendingPathComponent(".local/bin/claude.exe"))
        XCTAssertTrue(same(found(.claudeCode, path: path) ?? "", installed.path), "the installer's place first")
    }

    /// CodexProviderTests.testClientPerformsHandshakeWithoutStartingSession, with the engine answering the same lines.
    func testCodexClientPerformsHandshakeWithoutStartingSession() async throws {
        let dir = try directory()
        let log = dir.appendingPathComponent("methods")
        let exe = try TestEngine.write([.serve(log: log.path, replies: [
            "initialize": [#"{"id":1,"result":{"userAgent":"test"}}"#],
            "account/rateLimits/read": [#"{"method":"account/rateLimits/updated","params":{}}"#, #"{"id":999,"result":{}}"#,
                                        #"{"id":2,"result":\#(CodexProviderTests.limitsWithResets)}"#],
            "account/read": [#"{"id":3,"result":{"account":{"type":"chatgpt","email":"Dev@Example.com","planType":"prolite"},"requiresOpenaiAuth":true}}"#],
        ])], to: dir.appendingPathComponent("codex.exe"))
        let result = try await CodexAppServerClient(executable: exe, dataDirectory: dir, timeout: 5).fetch()
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(result.rateLimitResetCredits?.availableCount, 3)
        XCTAssertEqual(result.account?.email, "Dev@Example.com")
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), "initialize\ninitialized\naccount/rateLimits/read\naccount/read\n")
    }

    /// AntigravityCLITests.testOnlyARunningAgyProgramIsAsked: the program is the running process's own, named
    /// `agy.exe` on Windows; a process of another name is not agy.
    func testOnlyARunningAgyProgramIsAsked() throws {
        let dir = try directory()
        let agy = try TestEngine.write([.sleep(30)], to: dir.appendingPathComponent("AGY.exe"))
        let process = Process()
        process.executableURL = agy
        try process.run()
        defer { process.terminate() }

        func candidate(_ pid: Int32) -> AntigravityService.Candidate {
            .init(pid: Int(pid), token: "", extensionPort: nil, extensionToken: nil, priority: 1)
        }
        let own = ProcessInfo.processInfo.processIdentifier
        XCTAssertNil(AntigravityCLI.executable(of: [candidate(own)]))
        let found = try XCTUnwrap(AntigravityCLI.executable(of: [candidate(own), candidate(process.processIdentifier)]))
        XCTAssertTrue(same(found.path, agy.path), found.path)
    }
}
#endif
