// A stand-in for a client's engine in the Windows tests (docs/windows-port/DECISIONS.md D-034). The Windows build
// starts only programs, never scripts or batch files (D-011, D-019), so the tests copy this program to wherever a
// client's executable is looked for and write beside it, in `<name>.fake.json`, the steps the copy plays: the shell
// scripts the macOS tests use, as data. Tests/AgentHUDCoreTests/Support/TestEngine.swift writes both.
import Foundation
import WinSDK

/// The path of this copy of the program.
func ownPath() -> String {
    var buffer = [WCHAR](repeating: 0, count: 32_768)
    let count = Int(GetModuleFileNameW(nil, &buffer, DWORD(buffer.count)))
    return String(decoding: buffer[..<count], as: UTF16.self)
}

func write(_ text: String, to handle: FileHandle) {
    handle.write(Data(text.utf8))
}

/// One line of standard input without its line break, nil at its end.
func readLine(from input: FileHandle) -> String? {
    var bytes = Data()
    while true {
        let byte = input.readData(ofLength: 1)
        if byte.isEmpty { return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self) }
        if byte.first == 0x0A { break }
        bytes.append(byte)
    }
    if bytes.last == 0x0D { bytes.removeLast() }
    return String(decoding: bytes, as: UTF8.self)
}

func file(_ path: String) -> URL {
    URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
}

func append(_ text: String, to path: String) {
    let url = file(path)
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        try? handle.close()
    } else {
        try? Data(text.utf8).write(to: url)
    }
}

var script = ownPath()
if script.lowercased().hasSuffix(".exe") { script.removeLast(4) }
guard let data = try? Data(contentsOf: URL(fileURLWithPath: script + ".fake.json")),
      let steps = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
    write("fake engine: no steps beside \(ownPath())\n", to: .standardError)
    exit(90)
}
let arguments = Array(CommandLine.arguments.dropFirst())
let environment = ProcessInfo.processInfo.environment

for step in steps {
    guard let (name, value) = step.first else { continue }
    switch name {
    case "readLine":
        _ = readLine(from: .standardInput)
    case "out":
        write((value as? String ?? "") + "\n", to: .standardOutput)
    case "err":
        write((value as? String ?? "") + "\n", to: .standardError)
    case "cat":
        if let path = value as? String, let contents = try? Data(contentsOf: file(path)) { FileHandle.standardOutput.write(contents) }
    case "write":
        if let pair = value as? [String], pair.count == 2 { try? Data(pair[1].utf8).write(to: file(pair[0])) }
    case "append":
        if let pair = value as? [String], pair.count == 2 { append(pair[1], to: pair[0]) }
    case "sleep":
        Sleep(DWORD(((value as? Double) ?? 0) * 1000))
    case "exit":
        exit(Int32((value as? Int) ?? 0))
    case "requireArguments":
        // [expected arguments, exit status otherwise]
        if let pair = value as? [Any], let expected = pair.first as? [String], arguments != expected {
            exit(Int32((pair.last as? Int) ?? 3))
        }
    case "requireEnvironment":
        // [name, value, exit status otherwise]
        if let triple = value as? [Any], triple.count == 3, let key = triple[0] as? String,
           environment.first(where: { $0.key.uppercased() == key.uppercased() })?.value != triple[1] as? String {
            exit(Int32((triple[2] as? Int) ?? 7))
        }
    case "record":
        // One JSON line in the named file: the arguments, the working directory and `PATH`.
        guard let path = value as? String else { break }
        let facts: [String: Any] = ["arguments": arguments, "directory": FileManager.default.currentDirectoryPath,
                                    "path": environment.first { $0.key.uppercased() == "PATH" }?.value ?? ""]
        if let line = try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]) {
            append(String(decoding: line, as: UTF8.self) + "\n", to: path)
        }
    case "serve":
        // {"log": file the methods are appended to, "replies": {method: [lines]}}: a JSON-RPC peer over stdio until its
        // input ends.
        let spec = value as? [String: Any] ?? [:]
        let replies = spec["replies"] as? [String: [String]] ?? [:]
        while let line = readLine(from: .standardInput) {
            guard let request = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let method = request["method"] as? String else { continue }
            if let log = spec["log"] as? String { append(method + "\n", to: log) }
            for reply in replies[method] ?? [] { write(reply + "\n", to: .standardOutput) }
        }
    default:
        write("fake engine: unknown step \(name)\n", to: .standardError)
        exit(91)
    }
}
exit(0)
