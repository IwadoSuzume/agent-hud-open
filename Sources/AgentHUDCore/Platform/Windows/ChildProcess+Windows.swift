#if os(Windows)
import Foundation
import WinSDK

/// A child process that cannot stall its caller, on Windows: the same contract as the macOS `ChildProcess`. Both pipes
/// are drained while it runs, each up to a byte cap, and reading ends when it exits rather than at the pipes' end,
/// because a grandchild can inherit them and hold them open indefinitely.
///
/// The child is started with `CreateProcessW` from the executable's path and its arguments, each quoted by the rules
/// the C runtime parses a command line with; no shell is involved, and a batch file (`.bat`, `.cmd`), which Windows can
/// only run through `cmd.exe`, is refused. It inherits only its three standard handles, runs without a console window,
/// and is put in a job so that stopping it also stops what it started.
public final class ChildProcess: @unchecked Sendable {
    public struct Output: Sendable {
        /// The exit code, or nil while the child is running.
        public var status: Int32?
        /// Reading lines consumes stdout.
        public var stdout = Data(), stderr = Data()
        /// Stdout outgrew its cap and the rest was discarded.
        public var truncated = false
    }

    enum LaunchFailure: Error, CustomStringConvertible {
        case batchFile(String)
        case notAProgram(String)
        case system(Win32.Failure)
        public var description: String {
            switch self {
            case .batchFile(let name): "\(name) is a batch file, which runs only through cmd.exe; it is not started"
            case .notAProgram(let name): "\(name) is not a Windows program; it is not started"
            case .system(let failure): failure.description
            }
        }
    }

    /// Between asking the child to end — closing its input — and terminating it.
    public static let grace: TimeInterval = 2
    public static let stderrLimit = 64 * 1024

    private enum Condition { case line, exit }

    private let stdoutLimit: Int
    private let queue = DispatchQueue(label: "app.agenthud.child-process")
    private let process: HANDLE
    private let job: HANDLE?
    private var readers: [Reader] = []
    // Confined to `queue` after init.
    private var input: HANDLE?
    private var collected = Output()
    private var lineStart = 0
    private var waiter: (id: Int, condition: Condition, continuation: CheckedContinuation<Void, Never>)?
    private var waits = 0, cancelledWait = 0, stopping = false

    public var output: Output { queue.sync { collected } }

    /// Launches the child. With `input` its stdin is a pipe for `write`, otherwise the null device.
    public init(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil, directory: URL? = nil,
                input: Bool = false, stdoutLimit: Int) throws {
        self.stdoutLimit = stdoutLimit
        let path = executable.path.replacingOccurrences(of: "/", with: "\\")
        // CreateProcessW runs a batch file through cmd.exe by its extension, and Windows ignores trailing dots and spaces
        // in a name: both checks hold, the name's and the content's (DECISIONS.md D-011).
        guard !Self.isBatchFile(executable.lastPathComponent) else { throw LaunchFailure.batchFile(executable.lastPathComponent) }
        guard Self.isProgramImage(path) else { throw LaunchFailure.notAProgram(executable.lastPathComponent) }
        let out = try Self.pipe(), err = try Self.pipe()
        let stdin = input ? try Self.pipe(childReads: true) : nil
        let null = stdin == nil ? Self.nullDevice() : nil
        defer {
            // The child holds its own copies now; this process keeps only its ends.
            CloseHandle(out.child)
            CloseHandle(err.child)
            if let stdin { CloseHandle(stdin.child) }
            if let null { CloseHandle(null) }
        }
        let childInput = stdin?.child ?? null
        var inherited: [HANDLE?] = [childInput, out.child, err.child].filter { $0 != nil }

        var size: SIZE_T = 0
        _ = InitializeProcThreadAttributeList(nil, 1, 0, &size)
        let attributes = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { attributes.deallocate() }
        let list: LPPROC_THREAD_ATTRIBUTE_LIST? = OpaquePointer(attributes)
        guard InitializeProcThreadAttributeList(list, 1, 0, &size) else {
            Self.closeEnds(out, err, stdin)
            throw LaunchFailure.system(Win32.Failure("InitializeProcThreadAttributeList"))
        }
        defer { DeleteProcThreadAttributeList(list) }
        let listed = inherited.withUnsafeMutableBytes { bytes in
            UpdateProcThreadAttribute(list, 0, Self.handleListAttribute, bytes.baseAddress, SIZE_T(bytes.count), nil, nil)
        }
        guard listed else {
            Self.closeEnds(out, err, stdin)
            throw LaunchFailure.system(Win32.Failure("UpdateProcThreadAttribute"))
        }

        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        startup.StartupInfo.dwFlags = DWORD(STARTF_USESTDHANDLES)
        startup.StartupInfo.hStdInput = childInput
        startup.StartupInfo.hStdOutput = out.child
        startup.StartupInfo.hStdError = err.child
        startup.lpAttributeList = list

        var commandLine = Array(Self.commandLine(executable: path, arguments: arguments).utf16) + [0]
        let block = environment.map(Self.environmentBlock)
        var information = PROCESS_INFORMATION()
        let flags = DWORD(EXTENDED_STARTUPINFO_PRESENT) | DWORD(CREATE_NO_WINDOW) | DWORD(CREATE_UNICODE_ENVIRONMENT)
            | DWORD(CREATE_SUSPENDED)
        let created = Win32.withWide(path) { application in
            Self.withOptionalWide(directory?.path.replacingOccurrences(of: "/", with: "\\")) { folder in
                Self.withOptionalBlock(block) { environmentBlock in
                    withUnsafeMutablePointer(to: &startup) { info in
                        info.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1) { startupInfo in
                            CreateProcessW(application, &commandLine, nil, nil, true, flags, environmentBlock, folder,
                                           startupInfo, &information)
                        }
                    }
                }
            }
        }
        guard created, let processHandle = information.hProcess else {
            let failure = Win32.Failure("CreateProcessW")
            Self.closeEnds(out, err, stdin)
            throw LaunchFailure.system(failure)
        }
        process = processHandle
        // A job of its own, so that stopping the child stops what it started; without one the child still runs.
        job = CreateJobObjectW(nil, nil)
        if let job, !AssignProcessToJobObject(job, processHandle) { CloseHandle(job) }
        ResumeThread(information.hThread)
        CloseHandle(information.hThread)
        self.input = stdin?.ours

        readers = [Reader(handle: out.ours, isStdout: true, owner: self), Reader(handle: err.ours, isStdout: false, owner: self)]
        readers.forEach { $0.start() }
        let exitWatch = Thread { [self] in
            WaitForSingleObject(process, INFINITE)
            // What the child left is in the pipes' buffers; a grandchild still writing is not waited for.
            for reader in readers { reader.drainAndStop() }
            queue.async { self.exited() }
        }
        exitWatch.name = "app.agenthud.child-exit"
        exitWatch.start()
    }

    deinit {
        CloseHandle(process)
        if let job { CloseHandle(job) }
    }

    /// Runs a child without stdin until it exits; at the deadline it is stopped and the output has no status.
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                           timeout: TimeInterval, stdoutLimit: Int) async throws -> Output {
        try Task.checkCancellation()
        let child = try ChildProcess(executable, arguments, environment: environment, stdoutLimit: stdoutLimit)
        defer { child.stop() }
        try await child.waitForExit(before: Date().addingTimeInterval(timeout))
        return child.output
    }

    /// Writes to stdin. Requests are small, so a child that does not read cannot block the drain.
    public func write(_ data: Data) throws {
        try queue.sync {
            guard let input, NamedPipes.write(input, data, milliseconds: 10_000) else {
                throw ChildProcess.LaunchFailure.system(Win32.Failure("WriteFile", code: DWORD(ERROR_BROKEN_PIPE)))
            }
        }
    }

    /// The next complete stdout line; nil at the deadline, or once the child has exited, or stdout outgrew its cap, and no
    /// complete line is left.
    public func line(before deadline: Date) async throws -> String? {
        try await wait(until: deadline, for: .line)
        return queue.sync {
            guard let newline = collected.stdout[lineStart...].firstIndex(of: 0x0A) else { return nil }
            var end = newline
            // A Windows program ends its lines with CR LF; the line is the same text either way.
            if end > lineStart, collected.stdout[end - 1] == 0x0D { end -= 1 }
            let line = String(decoding: collected.stdout[lineStart..<end], as: UTF8.self)
            lineStart = newline + 1
            // Returned lines are dropped once they fill half the buffer, so a long exchange does not run into the cap.
            if lineStart * 2 >= collected.stdout.count { collected.stdout = Data(collected.stdout[lineStart...]); lineStart = 0 }
            return line
        }
    }

    /// Waits until the child exits or the deadline passes; `output.status` tells which.
    public func waitForExit(before deadline: Date) async throws {
        try await wait(until: deadline, for: .exit)
    }

    /// Closes stdin, the child's sign to end, then terminates the child and what it started if it outlives the grace
    /// period. Returns immediately.
    public func stop() {
        queue.async { [self] in
            if let input { CloseHandle(input) }
            input = nil
            guard collected.status == nil, !stopping else { return }
            stopping = true
            queue.asyncAfter(deadline: .now() + Self.grace) { [weak self] in
                guard let self, collected.status == nil else { return }
                if let job { TerminateJobObject(job, 1) } else { TerminateProcess(process, 1) }
            }
        }
    }

    /// Cancellation stops the child and throws.
    private func wait(until deadline: Date, for condition: Condition) async throws {
        let id = queue.sync { waits += 1; return waits }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    waiter = (id, condition, continuation)
                    let delay = min(max(deadline.timeIntervalSinceNow, 0), 86_400)
                    queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.wake(expired: id) }
                    wake()
                }
            }
        } onCancel: {
            queue.async { [self] in
                cancelledWait = id
                wake()
            }
            stop()
        }
        try Task.checkCancellation()
    }

    /// Resumes the waiter when its condition holds, its deadline passed (`expired`) or it was cancelled.
    private func wake(expired id: Int? = nil) {
        guard let current = waiter else { return }
        let ready = collected.status != nil
            || current.condition == .line && (collected.truncated || collected.stdout[lineStart...].contains(0x0A))
        guard ready || current.id == id || current.id == cancelledWait else { return }
        waiter = nil
        current.continuation.resume()
    }

    /// Keeps a chunk a reader read, up to the stream's cap. On `queue`.
    fileprivate func append(_ bytes: UnsafeRawBufferPointer, isStdout: Bool) {
        let held = isStdout ? collected.stdout.count : collected.stderr.count
        let kept = min(bytes.count, max(0, (isStdout ? stdoutLimit : Self.stderrLimit) - held))
        if kept > 0, let base = bytes.baseAddress {
            if isStdout { collected.stdout.append(base.assumingMemoryBound(to: UInt8.self), count: kept) }
            else { collected.stderr.append(base.assumingMemoryBound(to: UInt8.self), count: kept) }
        }
        if isStdout, kept < bytes.count { collected.truncated = true }
        wake()
    }

    fileprivate var queueForReaders: DispatchQueue { queue }

    private func exited() {
        var code: DWORD = 0
        collected.status = GetExitCodeProcess(process, &code) ? Int32(bitPattern: code) : -1
        if let input { CloseHandle(input) }
        input = nil
        wake()
    }

    // MARK: Pipes

    private struct PipeEnds {
        /// This process's end: overlapped, not inheritable.
        let ours: HANDLE
        /// The child's end: inheritable, synchronous, as a child's standard handle must be.
        let child: HANDLE
    }

    private static let counter = Counter()

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }

    /// A pipe of its own, under a name nobody else knows, only this user can open, made for one child.
    private static func pipe(childReads: Bool = false) throws -> PipeEnds {
        let name = #"\\.\pipe\agenthud-child-"# + "\(GetCurrentProcessId())-\(counter.next())-" + UUID().uuidString
        let security = try Win32.OwnerOnlySecurity()
        let access = DWORD(childReads ? PIPE_ACCESS_OUTBOUND : PIPE_ACCESS_INBOUND) | DWORD(FILE_FLAG_OVERLAPPED)
            | DWORD(FILE_FLAG_FIRST_PIPE_INSTANCE)
        let ours = security.withAttributes { attributes in
            Win32.withWide(name) {
                CreateNamedPipeW($0, access, DWORD(PIPE_TYPE_BYTE) | DWORD(PIPE_WAIT) | DWORD(PIPE_REJECT_REMOTE_CLIENTS),
                                 1, 64 * 1024, 64 * 1024, 0, attributes)
            }
        }
        guard let ours, ours != Win32.invalidHandle else { throw LaunchFailure.system(Win32.Failure("CreateNamedPipeW")) }
        var inheritable = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
                                              lpSecurityDescriptor: nil, bInheritHandle: true)
        let child = Win32.withWide(name) {
            CreateFileW($0, childReads ? DWORD(GENERIC_READ) : DWORD(GENERIC_WRITE), 0, &inheritable, DWORD(OPEN_EXISTING),
                        DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let child, child != Win32.invalidHandle else {
            let failure = Win32.Failure("CreateFileW")
            CloseHandle(ours)
            throw LaunchFailure.system(failure)
        }
        return PipeEnds(ours: ours, child: child)
    }

    private static func nullDevice() -> HANDLE? {
        var inheritable = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
                                              lpSecurityDescriptor: nil, bInheritHandle: true)
        let handle = Win32.withWide("NUL") {
            CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE), &inheritable,
                        DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        return handle == Win32.invalidHandle ? nil : handle
    }

    private static func closeEnds(_ ends: PipeEnds?...) {
        for end in ends { if let end { CloseHandle(end.ours) } }
    }

    /// `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`, a macro the importer does not bring over.
    private static let handleListAttribute = DWORD_PTR(0x0002_0002)

    // MARK: Command line

    /// The command line the C runtime parses back into `executable` and `arguments` exactly: each argument quoted when
    /// it holds a space, a tab or a quote, its quotes and the backslashes before them escaped.
    static func commandLine(executable: String, arguments: [String]) -> String {
        (["\"" + executable + "\""] + arguments.map(quote)).joined(separator: " ")
    }

    static func quote(_ argument: String) -> String {
        // Scalars, not characters: a quote followed by a combining mark is one character but still a quote to the parser.
        let special: Set<Unicode.Scalar> = [" ", "\t", "\n", "\u{0B}", "\""]
        if !argument.isEmpty, !argument.unicodeScalars.contains(where: special.contains) { return argument }
        let backslash: Unicode.Scalar = "\\", quote: Unicode.Scalar = "\""
        var result = String.UnicodeScalarView()
        result.append(quote)
        var backslashes = 0
        for scalar in argument.unicodeScalars {
            if scalar == backslash {
                backslashes += 1
            } else if scalar == quote {
                result.append(contentsOf: repeatElement(backslash, count: backslashes * 2 + 1))
                result.append(quote)
                backslashes = 0
            } else {
                result.append(contentsOf: repeatElement(backslash, count: backslashes))
                result.append(scalar)
                backslashes = 0
            }
        }
        result.append(contentsOf: repeatElement(backslash, count: backslashes * 2))
        result.append(quote)
        return String(result)
    }

    /// Whether Windows would treat a file of this name as a batch file: `.bat` or `.cmd` in any case, once the
    /// trailing dots and spaces Windows drops from names are gone.
    static func isBatchFile(_ name: String) -> Bool {
        var trimmed = Substring(name)
        while let last = trimmed.last, last == "." || last == " " { trimmed = trimmed.dropLast() }
        let lower = trimmed.lowercased()
        return lower.hasSuffix(".bat") || lower.hasSuffix(".cmd")
    }

    /// Whether the file at `path` starts as a Windows program does (`MZ`).
    static func isProgramImage(_ path: String) -> Bool {
        let handle = Win32.withWide(path) {
            CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE) | DWORD(FILE_SHARE_DELETE), nil,
                        DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != Win32.invalidHandle else { return false }
        defer { CloseHandle(handle) }
        var header: [UInt8] = [0, 0]
        var count: DWORD = 0
        guard ReadFile(handle, &header, 2, &count, nil), count == 2 else { return false }
        return header == [0x4D, 0x5A]
    }

    /// What a Windows program needs in its environment to start at all.
    static let systemVariables = ["SystemRoot", "windir", "SystemDrive"]

    /// `NAME=value` strings, sorted by name without regard to case as Windows expects, each ended by a NUL, and a NUL
    /// after the last.
    static func environmentBlock(_ environment: [String: String]) -> [UInt16] {
        var environment = environment
        // An environment given to a child is complete on macOS, where a program starts in an empty one. A Windows
        // program does not: Node, for one, aborts at start without SystemRoot (its random-number source looks it up).
        // So the variables naming the system's own folders come from this process when the child's leave them out
        // (DECISIONS.md D-035); they name no user's data.
        for name in systemVariables where !environment.keys.contains(where: { $0.uppercased() == name.uppercased() }) {
            if let value = Win32.environment(name) { environment[name] = value }
        }
        let entries = environment.filter { !$0.key.isEmpty && !$0.key.contains("=") }
            .sorted { $0.key.uppercased() < $1.key.uppercased() }
        var block: [UInt16] = []
        for (key, value) in entries { block += Array((key + "=" + value).utf16) + [0] }
        if block.isEmpty { block.append(0) }
        return block + [0]
    }

    private static func withOptionalWide<Result>(_ string: String?, _ body: (UnsafePointer<WCHAR>?) -> Result) -> Result {
        guard let string else { return body(nil) }
        return Win32.withWide(string) { body($0) }
    }

    private static func withOptionalBlock<Result>(_ block: [UInt16]?, _ body: (UnsafeMutableRawPointer?) -> Result) -> Result {
        guard var block else { return body(nil) }
        return block.withUnsafeMutableBytes { body($0.baseAddress) }
    }

    // MARK: Readers

    /// Drains one of the child's output pipes on a thread of its own.
    private final class Reader: @unchecked Sendable {
        let handle: HANDLE
        let isStdout: Bool
        weak var owner: ChildProcess?
        private let stopEvent = CreateEventW(nil, true, false, nil)!
        private let finished = CreateEventW(nil, true, false, nil)!

        init(handle: HANDLE, isStdout: Bool, owner: ChildProcess) {
            self.handle = handle
            self.isStdout = isStdout
            self.owner = owner
        }

        deinit {
            CloseHandle(stopEvent)
            CloseHandle(finished)
        }

        func start() {
            let thread = Thread { [self] in run() }
            thread.name = "app.agenthud.child-output"
            thread.start()
        }

        /// After the child exited: lets the reader take what is already in the pipe, then stops it, whether or not a
        /// grandchild still holds the pipe's other end. Never called on the owner's queue, which the reader appends on.
        func drainAndStop() {
            var available: DWORD = 0
            var rounds = 0
            while rounds < 50, WaitForSingleObject(finished, 0) != WAIT_OBJECT_0,
                  PeekNamedPipe(handle, nil, 0, nil, &available, nil), available > 0 {
                Sleep(2)
                rounds += 1
            }
            SetEvent(stopEvent)
            WaitForSingleObject(finished, 2000)
        }

        private func run() {
            defer {
                CloseHandle(handle)
                SetEvent(finished)
            }
            guard let overlapped = Overlapped() else { return }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                overlapped.reset()
                var count: DWORD = 0
                let started = buffer.withUnsafeMutableBytes { ReadFile(handle, $0.baseAddress, DWORD($0.count), nil, overlapped.pointer) }
                if !started {
                    guard GetLastError() == DWORD(ERROR_IO_PENDING) else { return }
                    guard NamedPipes.wait(overlapped, handle: handle, milliseconds: INFINITE, cancel: stopEvent) else { return }
                }
                let done = GetOverlappedResult(handle, overlapped.pointer, &count, false)
                guard done, count > 0, let owner else { return }
                let chunk = Data(buffer[..<Int(count)])
                owner.queueForReaders.sync {
                    chunk.withUnsafeBytes { owner.append($0, isStdout: isStdout) }
                }
            }
        }
    }
}
#endif
