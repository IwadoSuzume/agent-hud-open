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
        // Descriptor 1 must leave the protocol pipe whatever happens: onto standard error, or, when there is none, onto
        // the null device; failing both, the engine does not serve (D-022 fails closed).
        if _dup2(2, 1) != 0 {
            let device = Win32.withWide("NUL") {
                CreateFileW($0, DWORD(GENERIC_WRITE), DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE), nil, DWORD(OPEN_EXISTING), 0, nil)
            }
            let null = device.flatMap { $0 == Win32.invalidHandle ? nil : _open_osfhandle(Int(bitPattern: $0), _O_WRONLY) } ?? -1
            guard null >= 0, _dup2(null, 1) == 0 else {
                CloseHandle(kept)
                return nil
            }
            _close(null)
        }
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
            EngineServer(options: options, send: { writer.write($0, kind: $1) }, finish: { status in
                // A live shell gets the last lines (`lock-held` before status 3); a stalled one holds the exit 2 s at most.
                writer.drain(seconds: 2)
                exit(status)
            })
        }
        let input = Win32.SendableHandle(handle: GetStdHandle(STD_INPUT_HANDLE))
        let reader = Thread {
            readLines(from: input.handle) { line in
                DispatchQueue.main.async { MainActor.assumeIsolated { server.receive(line) } }
            } tooLong: {
                DispatchQueue.main.async { MainActor.assumeIsolated { server.lineTooLong() } }
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

    /// Writes whole lines to the protocol handle on a thread of its own, so that the engine never waits for the shell
    /// (PROTOCOL.md): a slow, hung or gone reader holds this thread, never the main actor that takes the hooks' requests
    /// and lets unanswered ones go after the hold time (G7). Lines are queued by `enqueue`.
    final class ProtocolWriter: @unchecked Sendable {
        static let limit = 256
        typealias Queued = (line: Data, kind: String)
        private let handle: Win32.SendableHandle
        private let condition = NSCondition()
        private var queue: [Queued] = []
        private var writing = false
        private var broken = false

        init(handle: HANDLE) {
            self.handle = Win32.SendableHandle(handle: handle)
            let thread = Thread { [self] in run() }
            thread.name = "app.agenthud.engine-output"
            thread.start()
        }

        static let replaceable: Set<String> = ["state", "hello"]

        /// Queues `line`, a message of type `kind`.
        func write(_ line: Data, kind: String) {
            condition.lock()
            defer { condition.unlock() }
            guard !broken else { return }
            Self.enqueue(line, kind: kind, into: &queue)
            condition.signal()
        }

        /// The queue's rules (PROTOCOL.md). A `hello` not yet written is replaced where it stands, so that the shell
        /// still reads a `hello` before any `state`; a `state` not yet written gives way to the newer one at the end,
        /// after the lines queued before it (a new language's `hello` included). The shell keeps the last of each. Other
        /// lines wait in order, at most `limit` in all: when a stalled shell lets more pile up, an `error` is dropped
        /// first, then the oldest other line (an `event`), never the `hello` or the `state`.
        static func enqueue(_ line: Data, kind: String, into queue: inout [Queued]) {
            if kind == "hello", let index = queue.firstIndex(where: { $0.kind == "hello" }) {
                queue[index] = (line, kind)
                return
            }
            if kind == "state", let index = queue.firstIndex(where: { $0.kind == "state" }) { queue.remove(at: index) }
            queue.append((line, kind))
            if queue.count > limit,
               let index = queue.firstIndex(where: { $0.kind == "error" })
                ?? queue.firstIndex(where: { !replaceable.contains($0.kind) }) {
                queue.remove(at: index)
            }
        }

        /// Waits until every queued line is written, the reader is gone, or `seconds` pass.
        func drain(seconds: Double) {
            let deadline = Date().addingTimeInterval(seconds)
            condition.lock()
            defer { condition.unlock() }
            while !broken, !queue.isEmpty || writing {
                if !condition.wait(until: deadline) { return }
            }
        }

        private func run() {
            while true {
                condition.lock()
                while queue.isEmpty { condition.wait() }
                let next = queue.removeFirst()
                writing = true
                condition.unlock()
                let written = write(next.line)
                condition.lock()
                writing = false
                // The shell went away: nothing more can reach it, and the input's end stops the engine.
                if !written { broken = true; queue.removeAll() }
                condition.broadcast()
                condition.unlock()
                if !written { return }
            }
        }

        private func write(_ line: Data) -> Bool {
            let bytes = [UInt8](line)
            var offset = 0
            while offset < bytes.count {
                var written: DWORD = 0
                let ok = bytes.withUnsafeBytes {
                    WriteFile(handle.handle, $0.baseAddress! + offset, DWORD(bytes.count - offset), &written, nil)
                }
                guard ok, written > 0 else { return false }
                offset += Int(written)
            }
            return true
        }
    }
}
#endif
