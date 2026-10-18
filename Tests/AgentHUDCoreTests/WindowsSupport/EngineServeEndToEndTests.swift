#if os(Windows)
import AgentHUDSupport
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// `agenthud-engine --serve` as the shell runs it (PROTOCOL.md): a child with pipes for its standard input and output,
/// in the temporary profile gate G3 runs in (D-021). Every line on its output must be a protocol message.
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

        init(_ engine: URL, _ arguments: [String]) throws {
            process.executableURL = engine
            process.arguments = ["--serve"] + arguments
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

    func testTheDemoServesStateTakesAnswersAndSettingsAndQuits() throws {
        let served = try Served(try engine(), ["--demo", "--language", "en"])
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

    func testAnEngineThatFindsAnotherCopyRunningSaysWhichAndExits() throws {
        // The lock the engine looks for, in the temporary profile both processes share.
        let claim = InstanceLock.claim(at: InstanceLock.sharedURL, executable: URL(fileURLWithPath: #"C:\Program Files\Agent HUD\agenthud-engine.exe"#))
        guard case .acquired = claim else { return XCTFail("the test holds the lock") }
        try withExtendedLifetime(claim) {
            let served = try Served(try engine(), [])
            defer { if served.process.isRunning { served.process.terminate() } }
            served.send(#"{"v":1,"type":"hello","minor":0,"shell":{"version":"test"}}"#)
            let held = try XCTUnwrap(served.next(type("lock-held")))
            XCTAssertEqual(held["holder"].stringValue, #"C:\Program Files\Agent HUD\agenthud-engine.exe"#)
            XCTAssertEqual(served.exitStatus(), 3)
        }
    }

    func testTheEngineEndsWhenItsInputEnds() throws {
        let served = try Served(try engine(), ["--demo"])
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
