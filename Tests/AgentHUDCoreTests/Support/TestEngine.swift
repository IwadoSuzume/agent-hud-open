import Foundation
#if os(Windows)
import WinSDK
#endif

/// A stand-in for a client's engine that plays a few steps, written where a test needs one: on macOS a `/bin/sh`
/// script, on Windows a copy of the test program `AgentHUDFakeEngine` with the steps beside it, since the Windows build
/// starts only programs (docs/windows-port/DECISIONS.md D-034).
enum TestEngine {
    enum Step {
        /// Reads one line of standard input.
        case readLine
        /// Writes the text and a line break to standard output.
        case out(String)
        /// Writes the text and a line break to standard error.
        case err(String)
        /// Copies the file to standard output.
        case cat(String)
        /// Replaces the file's contents with the text; a relative path is in the working directory.
        case write(String, String)
        /// Adds the text to the end of the file; a relative path is in the working directory.
        case append(String, String)
        case sleep(Double)
        case exit(Int32)
        /// Exits with the status unless the arguments, joined by spaces, are these.
        case requireArguments([String], orExit: Int32)
        /// Exits with the status unless the environment variable has this value.
        case requireEnvironment(String, String, orExit: Int32)
        #if os(Windows)
        /// Adds a JSON line with the arguments, the working directory and `PATH` to the file.
        case record(String)
        /// Answers each JSON-RPC request line with the replies listed for its method, logging the methods to `log`,
        /// until standard input ends.
        case serve(log: String, replies: [String: [String]])
        #endif
    }

    /// What separates the folders of `PATH`.
    #if os(Windows)
    static let pathSeparator = ";"
    #else
    static let pathSeparator = ":"
    #endif

    /// The file name a program called `name` has on `PATH`: `name.exe` on Windows.
    static func programName(_ name: String) -> String {
        #if os(Windows)
        name + ".exe"
        #else
        name
        #endif
    }

    /// Writes an engine playing `steps` at `url` and returns `url`.
    @discardableResult
    static func write(_ steps: [Step], to url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(Windows)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: try program(), to: url)
        var base = url.path
        if base.lowercased().hasSuffix(".exe") { base.removeLast(4) }
        let data = try JSONSerialization.data(withJSONObject: steps.map(\.json))
        try data.write(to: URL(fileURLWithPath: base + ".fake.json"))
        #else
        try (["#!/bin/sh"] + steps.map(\.shell)).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        #endif
        return url
    }

    #if os(Windows)
    /// `AgentHUDFakeEngine.exe`, which SwiftPM builds beside the test program.
    static func program() throws -> URL {
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        let count = Int(GetModuleFileNameW(nil, &buffer, DWORD(buffer.count)))
        var folder = URL(fileURLWithPath: String(decoding: buffer[..<count], as: UTF16.self)).deletingLastPathComponent()
        for _ in 0..<3 {
            let candidate = folder.appendingPathComponent("AgentHUDFakeEngine.exe")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            folder.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "AgentHUDFakeEngine.exe is not built beside the tests"])
    }
    #endif
}

private extension TestEngine.Step {
    #if os(Windows)
    var json: [String: Any] {
        switch self {
        case .readLine: return ["readLine": true]
        case .out(let text): return ["out": text]
        case .err(let text): return ["err": text]
        case .cat(let path): return ["cat": path]
        case .write(let path, let text): return ["write": [path, text]]
        case .append(let path, let text): return ["append": [path, text]]
        case .sleep(let seconds): return ["sleep": seconds]
        case .exit(let status): return ["exit": Int(status)]
        case .requireArguments(let arguments, let status): return ["requireArguments": [arguments, Int(status)]]
        case .requireEnvironment(let name, let value, let status): return ["requireEnvironment": [name, value, Int(status)]]
        case .record(let path): return ["record": path]
        case .serve(let log, let replies): return ["serve": ["log": log, "replies": replies]]
        }
    }
    #else
    var shell: String {
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }
        switch self {
        case .readLine: return "read -r line"
        case .out(let text): return "printf '%s\\n' \(quoted(text))"
        case .err(let text): return "printf '%s\\n' \(quoted(text)) >&2"
        case .cat(let path): return "cat \(quoted(path))"
        case .write(let path, let text): return "printf '%s' \(quoted(text)) > \(quoted(path))"
        case .append(let path, let text): return "printf '%s' \(quoted(text)) >> \(quoted(path))"
        case .sleep(let seconds): return "sleep \(seconds)"
        case .exit(let status): return "exit \(status)"
        case .requireArguments(let arguments, let status): return "[ \"$*\" = \(quoted(arguments.joined(separator: " "))) ] || exit \(status)"
        case .requireEnvironment(let name, let value, let status): return "[ \"${\(name):-}\" = \(quoted(value)) ] || exit \(status)"
        }
    }
    #endif
}
