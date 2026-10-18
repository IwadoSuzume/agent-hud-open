#if os(Windows)
import Foundation
import WinSDK

/// `agenthud-engine --serve [--demo] [--language zh|en]`: the engine as the Windows shell's child, speaking the shell
/// protocol over the standard input and output it inherited (PROTOCOL.md, D-022, D-041).
public enum EngineServe {
    public static let argument = "--serve"

    public static func isRequested(by arguments: [String]) -> Bool { arguments.dropFirst().first == argument }

    /// The options after `--serve`; nil for an argument it does not take.
    public static func options(from arguments: [String], executable: URL?) -> EngineServer.Options? {
        var options = EngineServer.Options()
        options.executable = executable
        var rest = arguments.dropFirst(2)[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--demo": options.demo = true
            case "--language":
                switch rest.popFirst() {
                case "zh"?: options.language = .zhHans
                case "en"?: options.language = .en
                default: return nil
                }
            default: return nil
            }
        }
        return options
    }

    /// Keeps the inherited standard output for the protocol alone and points the process's standard output — the C
    /// runtime's descriptor 1 and the handle Foundation and Windows hand out — at standard error, so that a stray
    /// `print` in shared code cannot put a line on the protocol (D-022). Nil when there is no output to keep.
    public static func takeProtocolOutput() -> HANDLE? {
        guard let inherited = GetStdHandle(STD_OUTPUT_HANDLE), inherited != Win32.invalidHandle else { return nil }
        var kept: HANDLE?
        let process = GetCurrentProcess()
        guard DuplicateHandle(process, inherited, process, &kept, 0, false, DWORD(DUPLICATE_SAME_ACCESS)), let kept else {
            return nil
        }
        let error = GetStdHandle(STD_ERROR_HANDLE)
        SetStdHandle(STD_OUTPUT_HANDLE, error)
        _ = _dup2(2, 1)
        return kept
    }

    /// Serves until the shell's input ends or it says `quit`; never returns.
    public static func run(arguments: [String], executable: URL?) -> Never {
        guard let options = options(from: arguments, executable: executable) else {
            complain("--serve takes --demo and --language zh|en only")
            exit(2)
        }
        guard let output = takeProtocolOutput() else {
            complain("no standard output to serve on")
            exit(2)
        }
        let writer = ProtocolWriter(handle: output)
        let server = MainActor.assumeIsolated {
            EngineServer(options: options, send: { writer.write($0) }, finish: { status in
                writer.close()
                exit(status)
            })
        }
        let input = Win32.SendableHandle(handle: GetStdHandle(STD_INPUT_HANDLE))
        let reader = Thread {
            readLines(from: input.handle) { line in
                DispatchQueue.main.async { MainActor.assumeIsolated { server.receive(line) } }
            } tooLong: {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { server.receive(Data("{\"v\":0}".utf8)) } // answered with error
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { server.inputEnded() } }
        }
        reader.name = "app.agenthud.engine-input"
        reader.start()
        dispatchMain()
    }

    /// One line on standard error through the C runtime, which, unlike Foundation's `FileHandle`, does not end the
    /// process when that is the null device or a closed pipe (measured: `ERROR_WRITE_FAULT`, status 29).
    public static func complain(_ text: String) {
        fputs("agenthud-engine: \(text)\n", stderr)
        fflush(stderr)
    }

    /// Reads `handle` to its end, handing each `\n`-ended line to `line`; a line over the limit is dropped up to its end
    /// and reported to `tooLong`.
    static func readLines(from handle: HANDLE?, line: (Data) -> Void, tooLong: () -> Void) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var pending = Data()
        var discarding = false
        while true {
            var count: DWORD = 0
            let read = buffer.withUnsafeMutableBytes { ReadFile(handle, $0.baseAddress, DWORD($0.count), &count, nil) }
            guard read, count > 0 else { return }
            var start = 0
            for index in 0..<Int(count) where buffer[index] == 0x0A {
                if discarding { discarding = false } else {
                    pending.append(contentsOf: buffer[start..<index])
                    line(pending)
                }
                pending = Data()
                start = index + 1
            }
            if !discarding { pending.append(contentsOf: buffer[start..<Int(count)]) }
            if pending.count > ShellProtocol.lineLimit {
                pending = Data()
                discarding = true
                tooLong()
            }
        }
    }

    /// Writes whole lines to the protocol handle, one at a time, from any thread.
    final class ProtocolWriter: @unchecked Sendable {
        private let handle: Win32.SendableHandle
        private let lock = NSLock()
        private var broken = false

        init(handle: HANDLE) { self.handle = Win32.SendableHandle(handle: handle) }

        func write(_ line: Data) {
            lock.lock()
            defer { lock.unlock() }
            guard !broken else { return }
            var offset = 0
            let bytes = [UInt8](line)
            while offset < bytes.count {
                var written: DWORD = 0
                let ok = bytes.withUnsafeBytes {
                    WriteFile(handle.handle, $0.baseAddress! + offset, DWORD(bytes.count - offset), &written, nil)
                }
                // The shell went away: nothing more can reach it, and the input's end will stop the engine.
                guard ok, written > 0 else { broken = true; return }
                offset += Int(written)
            }
        }

        func close() {
            lock.lock()
            defer { lock.unlock() }
            FlushFileBuffers(handle.handle)
        }
    }
}
#endif
