#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// The Windows `ChildProcess` (Platform/Windows/ChildProcess+Windows.swift), held to the contract ChildProcessTests
/// holds the macOS one to, with Windows' own programs as children.
final class ChildProcessWindowsTests: XCTestCase {
    private let system = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["SystemRoot"] ?? #"C:\Windows"#) + #"\System32"#)
    private var cmd: URL { system.appendingPathComponent("cmd.exe") }
    private var powershell: URL { system.appendingPathComponent(#"WindowsPowerShell\v1.0\powershell.exe"#) }
    private var ping: URL { system.appendingPathComponent("PING.EXE") }

    /// Stops the processes of this user whose command line names `marker`.
    private func stopProcesses(mentioning marker: String) {
        for line in WindowsProcesses.listing().split(separator: "\n") where line.contains(marker) {
            guard let pid = DWORD(line.split(separator: " ").first ?? ""), pid != GetCurrentProcessId(),
                  let process = OpenProcess(DWORD(PROCESS_TERMINATE), false, pid) else { continue }
            TerminateProcess(process, 1)
            CloseHandle(process)
        }
    }

    func testAGrandchildHoldingThePipesDoesNotDelayTheExitOrTheDeadline() async throws {
        let marker = "127.0.0.\(Int.random(in: 2...250))"
        defer { stopProcesses(mentioning: marker) }
        var started = Date()
        // `start /b` leaves the grandchild on the same console, holding the inherited output pipe.
        let exited = try await ChildProcess.run(cmd, ["/c", "start /b ping -n 30 \(marker) & echo started"],
                                                timeout: 10, stdoutLimit: 64 * 1024)
        XCTAssertEqual(exited.status, 0)
        XCTAssertTrue(String(decoding: exited.stdout, as: UTF8.self).contains("started"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "returns at the child's exit, not at the pipes' end")

        started = Date()
        let running = try await ChildProcess.run(ping, ["-n", "30", marker], timeout: 1, stdoutLimit: 64 * 1024)
        XCTAssertNil(running.status, "the deadline passed first")
        XCTAssertFalse(running.stdout.isEmpty, "output written before the deadline is kept")
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testStopEndsAChildThatIgnoresItsInputClosing() async throws {
        let child = try ChildProcess(ping, ["-n", "30", "127.0.0.1"], input: true, stdoutLimit: 64 * 1024)
        child.stop()
        try await child.waitForExit(before: Date().addingTimeInterval(1))
        XCTAssertNil(child.output.status, "closing its input does not end ping, and the grace period runs")
        try await child.waitForExit(before: Date().addingTimeInterval(ChildProcess.grace + 2))
        XCTAssertEqual(child.output.status, 1, "terminated after the grace period")
    }

    func testLargeOutputIsDrainedUpToItsCaps() async throws {
        let script = "[Console]::Error.Write('e' * 2000000); [Console]::Out.Write('o' * 2000000)"
        let output = try await ChildProcess.run(powershell, ["-NoProfile", "-NonInteractive", "-Command", script],
                                                timeout: 60, stdoutLimit: 1024 * 1024)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stderr.count, ChildProcess.stderrLimit)
        XCTAssertEqual(output.stdout.count, 1024 * 1024)
        XCTAssertTrue(output.truncated)
    }

    func testLinesStopAtTheAnswerAndEndWithTheExit() async throws {
        let server = try ChildProcess(cmd, ["/v:on", "/c", "set /p request=&echo noise&echo reply !request!&ping -n 30 127.0.0.1 >nul"],
                                      input: true, stdoutLimit: 64 * 1024)
        defer { server.stop() }
        try server.write(Data("ping\r\n".utf8))
        let started = Date()
        var answer: String?
        while let line = try await server.line(before: Date().addingTimeInterval(5)) {
            if line.hasPrefix("reply") { answer = line; break }
        }
        XCTAssertEqual(answer, "reply ping", "a CR LF line end is a line end")
        XCTAssertNil(server.output.status)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)

        let short = try ChildProcess(cmd, ["/c", "echo one&<nul set /p =two&exit /b 0"], stdoutLimit: 1024)
        var lines: [String] = []
        while let line = try await short.line(before: Date().addingTimeInterval(5)) { lines.append(line) }
        XCTAssertEqual(lines, ["one"], "an unterminated last line is not a line")
        XCTAssertEqual(short.output.status, 0)
    }

    func testALineWaiterReturnsOnceStdoutPassesItsCap() async throws {
        let script = "[Console]::Out.Write('a' * 4096); [Console]::Out.Flush(); Start-Sleep 30"
        let child = try ChildProcess(powershell, ["-NoProfile", "-NonInteractive", "-Command", script], stdoutLimit: 1024)
        defer { child.stop() }
        let line = try await child.line(before: Date().addingTimeInterval(30))
        XCTAssertNil(line, "no whole line is left once bytes were lost")
        XCTAssertTrue(child.output.truncated)
        XCTAssertNil(child.output.status, "the child still runs")
    }

    func testCancellationStopsTheChild() async throws {
        let child = try ChildProcess(ping, ["-n", "30", "127.0.0.1"], stdoutLimit: 64 * 1024)
        let waiting = Task { try await child.waitForExit(before: Date().addingTimeInterval(30)) }
        try await Task.sleep(for: .milliseconds(200))
        waiting.cancel()
        do {
            try await waiting.value
            XCTFail("a cancelled wait throws")
        } catch is CancellationError {}
        try await child.waitForExit(before: Date().addingTimeInterval(ChildProcess.grace + 3))
        XCTAssertNotNil(child.output.status, "cancelling stops the child")
    }

    func testTheEnvironmentAndFolderAreTheChildsOwn() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud child \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var environment = ProcessInfo.processInfo.environment
        environment["AGENTHUD_CHILD_TEST"] = "value with spaces"
        let child = try ChildProcess(cmd, ["/c", "echo %AGENTHUD_CHILD_TEST%&cd"], environment: environment, directory: folder,
                                     stdoutLimit: 64 * 1024)
        try await child.waitForExit(before: Date().addingTimeInterval(10))
        let lines = String(decoding: child.output.stdout, as: UTF8.self).components(separatedBy: "\r\n")
        XCTAssertEqual(lines.first, "value with spaces")
        XCTAssertEqual(lines.dropFirst().first?.lowercased(), folder.path.replacingOccurrences(of: "/", with: "\\").lowercased())
    }

    func testAnExecutableUnderAPathWithSpacesAndChineseRuns() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud 路径 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("命令 copy.exe")
        try FileManager.default.copyItem(at: cmd, to: copy)
        let output = try await ChildProcess.run(copy, ["/c", "echo ok"], timeout: 10, stdoutLimit: 1024)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), "ok")
    }

    func testABatchFileIsRefused() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["tool.cmd", "TOOL.BAT"] {
            let script = folder.appendingPathComponent(name)
            try "@echo should not run\r\n".write(to: script, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try ChildProcess(script, [], stdoutLimit: 1024), name)
        }
    }

    func testBatchNamesAndNonProgramsAreRefused() throws {
        for name in ["x.bat", "X.CMD", "x.bat.", "x.cmd  ", "x.Bat. . "] {
            XCTAssertTrue(ChildProcess.isBatchFile(name), name)
        }
        for name in ["x.exe", "bat", "x.batch", "cmd.exe"] {
            XCTAssertFalse(ChildProcess.isBatchFile(name), name)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("tool.exe")
        try "@echo a script named like a program\r\n".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ChildProcess(script, [], stdoutLimit: 1024), "a file that is not a PE image is not run")
        XCTAssertTrue(ChildProcess.isProgramImage(cmd.path.replacingOccurrences(of: "/", with: "\\")))
    }

    func testAQuoteFollowedByACombiningMarkIsStillEscaped() {
        let argument = "a\"\u{0301} b"
        XCTAssertEqual(argument.count, 4, "the quote and its mark are one character")
        let line = ChildProcess.commandLine(executable: #"C:\tool.exe"#, arguments: [argument, "next"])
        XCTAssertEqual(WindowsCommandLine.split(line), [#"C:\tool.exe"#, argument, "next"], line)
    }

    func testArgumentsReachTheChildExactlyAsGiven() {
        let tricky = ["", "plain", "with space", "tab\there", #"quote " inside"#, #"trailing\"#, #"two\\"#, #"\\server\share\"#,
                      #"back\\" "quote"#, "中文 参数", "a=b", "--flag=\"x y\"", "%PATH%", "&|<>^"]
        let line = ChildProcess.commandLine(executable: #"C:\Program Files\Tool\tool.exe"#, arguments: tricky)
        XCTAssertEqual(WindowsCommandLine.split(line), [#"C:\Program Files\Tool\tool.exe"#] + tricky,
                       "the C runtime splits the command line back into the same arguments: \(line)")
    }

    func testEnvironmentBlocksAreSortedWithoutRegardToCase() {
        let block = ChildProcess.environmentBlock(["b": "2", "A": "1", "C": "3", "": "x", "bad=key": "y"])
        let entries = String(decoding: block, as: UTF16.self).split(separator: "\0").map(String.init)
            .filter { entry in !ChildProcess.systemVariables.contains { entry.uppercased().hasPrefix($0.uppercased() + "=") } }
        XCTAssertEqual(entries, ["A=1", "b=2", "C=3"])
        XCTAssertEqual(block.suffix(2), [0, 0], "the block ends with two NULs")
    }

    /// D-035: a Windows program cannot start in an empty environment, so the system's folders are always passed on;
    /// a value the caller gives wins, in whatever case it names the variable.
    func testAGivenEnvironmentKeepsTheSystemFolders() throws {
        func entries(_ environment: [String: String]) -> [String] {
            String(decoding: ChildProcess.environmentBlock(environment), as: UTF16.self).split(separator: "\0").map(String.init)
        }
        let root = try XCTUnwrap(Win32.environment("SystemRoot"))
        XCTAssertTrue(entries([:]).contains("SystemRoot=" + root), "\(entries([:]))")
        XCTAssertFalse(entries([:]).contains { $0.uppercased().hasPrefix("PATH=") || $0.uppercased().hasPrefix("USERPROFILE=") },
                       "nothing else is added")
        XCTAssertEqual(entries(["SYSTEMROOT": #"D:\Other"#]).filter { $0.uppercased().hasPrefix("SYSTEMROOT=") }, [#"SYSTEMROOT=D:\Other"#])
    }

    /// Node, the runtime the DeepSeek reader starts with an environment of its own, runs in one that names nothing else.
    func testNodeStartsInAnOtherwiseEmptyEnvironment() async throws {
        guard let node = Executables.first(Executables.onPath("node", path: Executables.systemPath)) else {
            throw XCTSkip("Node.js is not on PATH")
        }
        let output = try await ChildProcess.run(node, ["-e", "console.log(require('node:crypto').randomBytes(4).length)"],
                                                environment: [:], timeout: 30, stdoutLimit: 1024)
        XCTAssertEqual(output.status, 0, String(decoding: output.stderr, as: UTF8.self))
        XCTAssertEqual(String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), "4")
    }
}
#endif
