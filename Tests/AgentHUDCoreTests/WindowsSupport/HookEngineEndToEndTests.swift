#if os(Windows)
import AgentHUDSupport
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// TASK.md M5's end-to-end case on Windows: the engine's channel is open, a client runs the hook Agent HUD installed
/// for it exactly as its settings file says, the request reaches the engine, the HUD answers, and the hook process
/// prints the answer and ends with status 0. The profile is the temporary one gate G3 runs in (D-021), so the channel's
/// pipe and key are the test's own.
@MainActor
final class HookEngineEndToEndTests: XCTestCase {
    /// `agenthud-engine.exe`, which SwiftPM builds beside the test program.
    private func engine() throws -> URL {
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        let count = Int(GetModuleFileNameW(nil, &buffer, DWORD(buffer.count)))
        var folder = URL(fileURLWithPath: String(decoding: buffer[..<count], as: UTF16.self)).deletingLastPathComponent()
        for _ in 0..<3 {
            let candidate = folder.appendingPathComponent("agenthud-engine.exe")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            folder.deleteLastPathComponent()
        }
        // A failure, not a skip: the engine is a product of this package, which `swift build --build-tests` builds.
        throw MissingEngine()
    }

    private struct MissingEngine: Error, CustomStringConvertible {
        var description: String { "agenthud-engine.exe is not built beside the tests" }
    }

    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HUD 端到端 \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Runs `program` with `arguments` as a client runs its hook: the payload on standard input, closed after it.
    private func runHook(_ program: String, _ arguments: [String], payload: Data) throws -> (Process, Pipe) {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(payload)
        try input.fileHandleForWriting.close()
        return (process, output)
    }

    /// A running hook, handed to the threads that wait on it; the first to finish answers.
    private final class Running: @unchecked Sendable {
        let process: Process, output: Pipe
        private let lock = NSLock()
        private var continuation: CheckedContinuation<(Data, Int32)?, Never>?
        init(_ process: Process, _ output: Pipe) { self.process = process; self.output = output }

        func wait(seconds: Double) async -> (Data, Int32)? {
            await withCheckedContinuation { continuation in
                lock.lock(); self.continuation = continuation; lock.unlock()
                DispatchQueue.global().async {
                    let data = self.output.fileHandleForReading.readDataToEndOfFile()
                    self.process.waitUntilExit()
                    self.finish((data, self.process.terminationStatus))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                    if self.process.isRunning { self.process.terminate() }
                    self.finish(nil)
                }
            }
        }

        private func finish(_ value: (Data, Int32)?) {
            lock.lock(); let continuation = self.continuation; self.continuation = nil; lock.unlock()
            continuation?.resume(returning: value)
        }
    }

    /// The hook's output and exit status, read on another thread (the channel answers on the main actor), or nil once
    /// `seconds` pass, when the hook is stopped.
    private static func finish(_ process: Process, _ output: Pipe, seconds: Double = 15) async -> (Data, Int32)? {
        await Running(process, output).wait(seconds: seconds)
    }

    func testClaudeCodesHookReachesTheEngineAndCarriesTheAnswerBack() async throws {
        let engine = try engine(), home = try home()
        try PermissionHooks.configure(.claude, enabled: true, executable: engine, home: home)
        let settings = try ProviderJSON.read(Data(contentsOf: home.appendingPathComponent(".claude/settings.json")))
        let handler = try XCTUnwrap((settings["hooks"]["PermissionRequest"].arrayValue ?? []).flatMap { $0["hooks"].arrayValue ?? [] }.first)
        let program = try XCTUnwrap(handler["command"].stringValue), arguments = handler["args"].arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertEqual(arguments, ["--permission-hook", "claude"])

        let requests = PermissionRequests()
        requests.start()
        defer { requests.stop() }
        let payload = try JSONSerialization.data(withJSONObject: [
            "session_id": "end-to-end", "hook_event_name": "PermissionRequest", "cwd": home.path,
            "tool_name": "Bash", "tool_input": ["command": "dir", "description": "List the folder"]])
        let (process, output) = try runHook(program, arguments, payload: payload)
        defer { if process.isRunning { process.terminate() } }

        let deadline = Date().addingTimeInterval(15)
        while requests.pending.isEmpty, Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        let request = try XCTUnwrap(requests.pending.first, "the request reached the engine's channel")
        XCTAssertEqual(request.source, .claude)
        XCTAssertTrue(process.isRunning, "the hook waits for the answer")
        requests.resolve(request.id, .allow)

        let finished = await Self.finish(process, output)
        let (answer, status) = try XCTUnwrap(finished, "the hook ended once answered")
        XCTAssertEqual(status, 0)
        let response = try ProviderJSON.read(answer)
        XCTAssertEqual(response["hookSpecificOutput"]["hookEventName"].stringValue, "PermissionRequest")
        XCTAssertEqual(response["hookSpecificOutput"]["decision"]["behavior"].stringValue, "allow")
        XCTAssertTrue(requests.pending.isEmpty)
    }

    func testWithoutARunningEngineTheHookPrintsNothingAndLeavesTheClientsOwnPrompt() async throws {
        let engine = try engine()
        let payload = try JSONSerialization.data(withJSONObject: [
            "session_id": "nobody", "hook_event_name": "PermissionRequest", "cwd": "C:/", "tool_name": "Bash", "tool_input": ["command": "dir"]])
        let started = Date()
        let (process, output) = try runHook(engine.path, ["--permission-hook", "claude"], payload: payload)
        let finished = await Self.finish(process, output, seconds: 10)
        let (answer, status) = try XCTUnwrap(finished, "the hook ended")
        XCTAssertEqual(status, 0)
        XCTAssertTrue(answer.isEmpty, "nothing on standard output: the client asks in its own prompt")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "no channel is a quick no")
    }

    /// `--mcp` in the engine program: the server answers a client's agent line by line on standard input and output,
    /// says that Agent HUD is not running when no copy holds the lock (the temporary profile's), and ends with status 0
    /// once its input closes.
    func testTheEngineServesMCPOnItsStandardInputAndOutput() async throws {
        let engine = try engine()
        let lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_panel","arguments":{}}}"#,
        ]
        let (process, output) = try runHook(engine.path, ["--mcp"], payload: Data((lines.joined(separator: "\n") + "\n").utf8))
        defer { if process.isRunning { process.terminate() } }
        let finished = await Self.finish(process, output, seconds: 20)
        let (answer, status) = try XCTUnwrap(finished, "the server ended with its input")
        XCTAssertEqual(status, 0)
        XCTAssertFalse(answer.contains(13), "lines end with LF alone, as on macOS: standard output is in binary mode")
        let replies = try String(decoding: answer, as: UTF8.self).split(separator: "\n").map { try ProviderJSON.read(Data($0.utf8)) }
        XCTAssertEqual(replies.map { $0["id"] }, [.integer(1), .integer(2)], "\(replies)")
        XCTAssertNotNil(replies.first?["result"]["serverInfo"]["name"].stringValue)
        let text = replies.last?["result"]["content"].arrayValue?.first?["text"].stringValue
        XCTAssertEqual(text, "Agent HUD is not running. Open Agent HUD and try again.")
    }

    /// `HookWatchdog`: a client that never closes the hook's standard input is let go once the bounded part's five
    /// seconds pass, with status 0 and nothing printed, as `alarm(5)` does on macOS.
    func testAClientThatNeverClosesItsPipeIsLetGoByTheWatchdog() async throws {
        let engine = try engine()
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = engine
        process.arguments = ["--permission-hook", "claude"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let started = Date()
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        input.fileHandleForWriting.write(Data(#"{"session_id":"open","hook_event_name":"PermissionRequest""#.utf8))
        let finished = await Self.finish(process, output, seconds: 15)
        let elapsed = Date().timeIntervalSince(started)
        withExtendedLifetime(input) {}
        let (answer, status) = try XCTUnwrap(finished, "the watchdog ended the hook before the test had to")
        XCTAssertEqual(status, 0)
        XCTAssertTrue(answer.isEmpty)
        XCTAssertGreaterThanOrEqual(elapsed, 4.5, "not before its time")
        XCTAssertLessThan(elapsed, 12)
    }
}
#endif
