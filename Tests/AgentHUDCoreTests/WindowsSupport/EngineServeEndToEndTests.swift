#if os(Windows)
import AgentHUDSupport
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// `agenthud-engine --serve` as the shell runs it (PROTOCOL.md): a child with pipes for its standard input and output,
/// each in a home of its own (`isolatedEnvironment`), never the profile the tests run in. Every line on its output must be a
/// protocol message.
final class EngineServeEndToEndTests: XCTestCase, @unchecked Sendable {
    private func engine() throws -> URL {
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        let count = Int(GetModuleFileNameW(nil, &buffer, DWORD(buffer.count)))
        var folder = URL(fileURLWithPath: String(decoding: buffer[..<count], as: UTF16.self)).deletingLastPathComponent()
        for _ in 0..<3 {
            let candidate = folder.appendingPathComponent("agenthud-engine.exe")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            folder.deleteLastPathComponent()
        }
        throw MissingEngine()
    }

    private struct MissingEngine: Error, CustomStringConvertible {
        var description: String { "agenthud-engine.exe is not built beside the tests" }
    }

    /// A running engine and the lines it wrote so far.
    private final class Served: @unchecked Sendable {
        let process = Process()
        let input = Pipe(), output = Pipe()
        private let lock = NSLock()
        private var received: [Data] = []
        private var pending = Data()

        init(_ engine: URL, _ arguments: [String], environment: [String: String]? = nil) throws {
            process.executableURL = engine
            process.arguments = ["--serve"] + arguments
            if let environment { process.environment = environment }
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self, !data.isEmpty else { return }
                self.lock.withLock {
                    self.pending.append(data)
                    while let end = self.pending.firstIndex(of: 0x0A) {
                        self.received.append(self.pending[self.pending.startIndex..<end])
                        self.pending.removeSubrange(self.pending.startIndex...end)
                    }
                }
            }
            try process.run()
        }

        var lines: [Data] { lock.withLock { received } }
        var messages: [JSONValue] { lines.compactMap { try? JSONValue.parse($0) } }

        func send(_ line: String) { input.fileHandleForWriting.write(Data((line + "\n").utf8)) }

        /// The first message after the first `skip` that `matches`, waiting up to `seconds`.
        func next(after skip: Int = 0, seconds: Double = 30, _ matches: (JSONValue) -> Bool) -> JSONValue? {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if let found = messages.dropFirst(skip).first(where: matches) { return found }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return nil
        }

        func exitStatus(seconds: Double = 20) -> Int32? {
            let deadline = Date().addingTimeInterval(seconds)
            while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            guard !process.isRunning else { process.terminate(); return nil }
            return process.terminationStatus
        }
    }

    private func type(_ name: String) -> (JSONValue) -> Bool { { $0["type"].stringValue == name } }

    private static let systemVariables = ["SystemRoot", "windir", "SystemDrive", "ComSpec", "PATHEXT", "TEMP", "TMP", "OS",
                                          "NUMBER_OF_PROCESSORS", "PROCESSOR_ARCHITECTURE", "USERNAME", "USERDOMAIN",
                                          "ProgramFiles", "ProgramFiles(x86)", "ProgramData"]
    private static let profileVariables = ["USERPROFILE", "HOME", "APPDATA", "LOCALAPPDATA"]

    /// A home of the test's own, removed afterwards.
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("HUD 引擎 home \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    /// An environment for an engine and its hooks that can reach nothing of the machine's user: only the system's own
    /// variables are taken over, and the user's folders — home, roaming and local profile — are folders of `home`. Every
    /// client's home variable (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `XDG_CONFIG_HOME`, …) is left out, so a machine that
    /// sets one keeps its real client untouched (TASK.md §8, G7). `Path` is the system's folders and those holding the
    /// Swift runtime, so no installed client (`claude`, `codex`) can be found and started: only the opt-in probe may
    /// start one (architecture.md).
    private func isolatedEnvironment(home: URL) throws -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]
        for (name, value) in inherited where Self.systemVariables.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            environment[name] = value
        }
        let systemRoot = environment.first { $0.key.caseInsensitiveCompare("SystemRoot") == .orderedSame }?.value ?? #"C:\Windows"#
        let path = inherited.first { $0.key.caseInsensitiveCompare("Path") == .orderedSame }?.value ?? ""
        let runtime = path.split(separator: ";").map(String.init)
            .filter { FileManager.default.fileExists(atPath: ($0 as NSString).appendingPathComponent("swiftCore.dll")) }
        XCTAssertFalse(runtime.isEmpty, "the Swift runtime is on the tests' own Path")
        environment["Path"] = ([systemRoot + #"\System32"#, systemRoot] + runtime).joined(separator: ";")
        let native = home.path.replacingOccurrences(of: "/", with: "\\")
        for (name, folder) in zip(Self.profileVariables, ["", "", #"\Profile\Roaming"#, #"\Profile\Local"#]) {
            environment[name] = native + folder
            try FileManager.default.createDirectory(atPath: native + folder, withIntermediateDirectories: true)
        }
        // Nothing but the allowed names reaches the child.
        let allowed = Set((Self.systemVariables + Self.profileVariables + ["Path"]).map { $0.uppercased() })
        XCTAssertTrue(Set(environment.keys.map { $0.uppercased() }).isSubset(of: allowed), "\(environment.keys.sorted())")
        return environment
    }

    func testTheDemoServesStateTakesAnswersAndSettingsAndQuits() throws {
        let served = try Served(try engine(), ["--demo", "--language", "en"], environment: try isolatedEnvironment(home: try temporaryHome()))
        defer { if served.process.isRunning { served.process.terminate() } }
        served.send(#"{"v":1,"type":"hello","minor":0,"shell":{"version":"test"}}"#)
        let hello = try XCTUnwrap(served.next(type("hello")), "the engine answers hello")
        XCTAssertEqual(hello["minor"], .integer(0))
        XCTAssertEqual(hello["demo"], .bool(true))
        XCTAssertEqual(hello["language"].stringValue, "en")
        XCTAssertEqual(hello["strings"]["menu.quit"].stringValue, "Quit")
        let state = try XCTUnwrap(served.next { $0["type"].stringValue == "state" && !($0["approvals"].arrayValue ?? []).isEmpty },
                                  "a state with the demo's requests")
        XCTAssertFalse(state["panel"]["agents"].arrayValue?.isEmpty ?? true)
        let request = try XCTUnwrap(state["approvals"].arrayValue?.first?["id"].stringValue)

        served.send(#"{"v":1,"type":"answer","id":"\#(request)","decision":"allow"}"#)
        XCTAssertNotNil(served.next(after: served.lines.count - 1) {
            $0["type"].stringValue == "state" && !($0["approvals"].arrayValue ?? []).contains { $0["id"].stringValue == request }
        }, "the answered request leaves the state")

        served.send("not a message")
        XCTAssertNotNil(served.next(type("error")), "a line the engine cannot take is answered with error")
        let before = served.lines.count
        served.send(#"{"v":1,"type":"update-settings","patch":{"language":"zh-Hans"}}"#)
        let chinese = try XCTUnwrap(served.next(after: before, type("hello")), "a language change says hello again")
        XCTAssertEqual(chinese["language"].stringValue, "zh")
        XCTAssertEqual(chinese["strings"]["menu.quit"].stringValue, "退出")
        XCTAssertNotNil(served.next(after: before) { $0["type"].stringValue == "state" && $0["settings"]["language"].stringValue == "zh-Hans" })

        served.send(#"{"v":1,"type":"quit"}"#)
        XCTAssertEqual(served.exitStatus(), 0)
        // Nothing but protocol on the output (D-022).
        for line in served.lines {
            let value = try XCTUnwrap(try? JSONValue.parse(line), String(decoding: line, as: UTF8.self))
            XCTAssertEqual(value["v"], .integer(1))
        }
    }

    /// A real engine (not the demo) in a home of the test's own: it sets Claude Code's hook at start and only when the
    /// switch changes afterwards (a hook the user took out stays out through clock ticks and other settings), and a
    /// request a real hook process makes reaches the shell in `state`, is answered by the shell's `answer`, and the
    /// hook prints that answer and ends with status 0 (TASK.md G7: only the user's answer resolves it).
    func testARealRequestGoesThroughTheProtocolAndHooksChangeOnlyWithTheirSwitch() throws {
        let engine = try engine()
        let home = try temporaryHome()
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/projects"), withIntermediateDirectories: true)
        let settingsFile = home.appendingPathComponent(".claude/settings.json")
        let environment = try isolatedEnvironment(home: home)

        let served = try Served(engine, [], environment: environment)
        defer { if served.process.isRunning { served.process.terminate() } }
        served.send(#"{"v":1,"type":"hello","minor":0,"shell":{"version":"test"}}"#)
        XCTAssertNotNil(served.next(type("state")))
        func hooked() -> Bool { ((try? String(contentsOf: settingsFile, encoding: .utf8)) ?? "").contains("--permission-hook") }
        XCTAssertTrue(hooked(), "the hook is set at start")

        // The user takes the hook out by hand; a clock tick (10 s) and an unrelated setting leave it out.
        try Data(#"{"model":"opus"}"#.utf8).write(to: settingsFile)
        served.send(#"{"v":1,"type":"update-settings","patch":{"hoverDelayMs":500}}"#)
        XCTAssertNotNil(served.next { $0["type"].stringValue == "state" && $0["settings"]["hoverDelayMs"] == .integer(500) })
        Thread.sleep(forTimeInterval: 11)
        XCTAssertFalse(hooked(), "nothing but the switch puts a hook back")
        // The switch off and on again sets it once more.
        served.send(#"{"v":1,"type":"update-settings","patch":{"clientHooks":false}}"#)
        XCTAssertNotNil(served.next { $0["type"].stringValue == "state" && $0["settings"]["clientHooks"] == .bool(false) })
        served.send(#"{"v":1,"type":"update-settings","patch":{"clientHooks":true}}"#)
        XCTAssertNotNil(served.next { $0["type"].stringValue == "state" && $0["settings"]["clientHooks"] == .bool(true) })
        let deadline = Date().addingTimeInterval(10)
        while !hooked(), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertTrue(hooked(), "turning the switch on sets the hook")

        // A client asks through the hook it was given.
        let hook = Process(), input = Pipe(), output = Pipe()
        hook.executableURL = engine
        hook.arguments = ["--permission-hook", "claude"]
        hook.environment = environment
        hook.standardInput = input
        hook.standardOutput = output
        hook.standardError = FileHandle.nullDevice
        try hook.run()
        defer { if hook.isRunning { hook.terminate() } }
        let payload = try JSONSerialization.data(withJSONObject: [
            "session_id": "through-the-shell", "hook_event_name": "PermissionRequest", "cwd": home.path,
            "tool_name": "Bash", "tool_input": ["command": "dir", "description": "List the folder"]])
        input.fileHandleForWriting.write(payload)
        try input.fileHandleForWriting.close()
        let asked = try XCTUnwrap(served.next {
            $0["type"].stringValue == "state" && ($0["approvals"].arrayValue ?? []).contains { $0["sessionID"].stringValue == "through-the-shell" }
        }, "the request reaches the shell")
        let request = try XCTUnwrap(asked["approvals"].arrayValue?.first { $0["sessionID"].stringValue == "through-the-shell" })
        XCTAssertTrue(hook.isRunning, "the hook waits for the user")
        served.send(#"{"v":1,"type":"answer","id":"\#(try XCTUnwrap(request["id"].stringValue))","decision":"allow"}"#)
        // Bounded: a hook that never got its answer would otherwise wait the engine's 10-minute hold.
        let hookDeadline = Date().addingTimeInterval(20)
        while hook.isRunning, Date() < hookDeadline { Thread.sleep(forTimeInterval: 0.05) }
        if hook.isRunning { hook.terminate(); return XCTFail("the hook did not get its answer") }
        let answer = output.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(hook.terminationStatus, 0)
        XCTAssertEqual(try ProviderJSON.read(answer)["hookSpecificOutput"]["decision"]["behavior"].stringValue, "allow")

        served.send(#"{"v":1,"type":"quit"}"#)
        XCTAssertEqual(served.exitStatus(), 0)
    }

    /// A shell that stops reading cannot hold the engine: with its output never read, the engine still takes `quit`
    /// and ends, as its writer waits on a thread of its own (PROTOCOL.md).
    func testAShellThatNeverReadsCannotHoldTheEngine() throws {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = try engine()
        process.arguments = ["--serve", "--demo"]
        process.environment = try isolatedEnvironment(home: try temporaryHome())
        process.standardInput = input
        process.standardOutput = output // never read
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        input.fileHandleForWriting.write(Data(#"{"v":1,"type":"hello","minor":0,"shell":{"version":"test"}}"#.utf8 + [0x0A]))
        // Enough refreshes for many states, far more than a pipe's buffer holds.
        for _ in 0..<40 { input.fileHandleForWriting.write(Data(#"{"v":1,"type":"refresh"}"#.utf8 + [0x0A])) }
        Thread.sleep(forTimeInterval: 3)
        let started = Date()
        input.fileHandleForWriting.write(Data(#"{"v":1,"type":"quit"}"#.utf8 + [0x0A]))
        while process.isRunning, Date().timeIntervalSince(started) < 15 { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertFalse(process.isRunning, "the engine ended though nobody read it")
        XCTAssertLessThan(Date().timeIntervalSince(started), 8, "within the writer's 2 s drain, not the reader's pace")
        if !process.isRunning { XCTAssertEqual(process.terminationStatus, 0) }
    }

    func testAnEngineThatFindsAnotherCopyRunningSaysWhichAndExits() throws {
        // The lock the engine looks for: the shared lock's place under the child's own local profile.
        let home = try temporaryHome(), environment = try isolatedEnvironment(home: home)
        let local = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALAPPDATA"]), isDirectory: true)
        XCTAssertTrue(InstanceLock.sharedURL.path.hasSuffix("/app.agenthud/instance.lock"))
        let lock = local.appendingPathComponent("app.agenthud/instance.lock")
        try FileManager.default.createDirectory(at: lock.deletingLastPathComponent(), withIntermediateDirectories: true)
        let claim = InstanceLock.claim(at: lock, executable: URL(fileURLWithPath: #"C:\Program Files\Agent HUD\agenthud-engine.exe"#))
        guard case .acquired = claim else { return XCTFail("the test holds the lock") }
        try withExtendedLifetime(claim) {
            let served = try Served(try engine(), [], environment: environment)
            defer { if served.process.isRunning { served.process.terminate() } }
            served.send(#"{"v":1,"type":"hello","minor":0,"shell":{"version":"test"}}"#)
            let held = try XCTUnwrap(served.next(type("lock-held")))
            XCTAssertEqual(held["holder"].stringValue, #"C:\Program Files\Agent HUD\agenthud-engine.exe"#)
            XCTAssertEqual(served.exitStatus(), 3)
        }
    }

    func testTheEngineEndsWhenItsInputEnds() throws {
        let served = try Served(try engine(), ["--demo"], environment: try isolatedEnvironment(home: try temporaryHome()))
        defer { if served.process.isRunning { served.process.terminate() } }
        served.send(#"{"v":1,"type":"hello","minor":0,"shell":{"version":"test"}}"#)
        XCTAssertNotNil(served.next(type("state")))
        try served.input.fileHandleForWriting.close()
        XCTAssertEqual(served.exitStatus(), 0, "the shell went away: the engine goes too")
    }

    func testAnArgumentServeDoesNotTakeIsRefused() throws {
        let process = Process()
        process.executableURL = try engine()
        process.arguments = ["--serve", "--colour", "blue"]
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let said = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 2)
        XCTAssertTrue(String(decoding: said, as: UTF8.self).contains("--serve takes --demo"), String(decoding: said, as: UTF8.self))
        // With standard error on the null device, the refusal still ends with status 2.
        let quiet = Process()
        quiet.executableURL = try engine()
        quiet.arguments = ["--serve", "--colour", "blue"]
        quiet.standardOutput = FileHandle.nullDevice
        quiet.standardError = FileHandle.nullDevice
        try quiet.run()
        quiet.waitUntilExit()
        XCTAssertEqual(quiet.terminationStatus, 2)
    }
}
#endif
