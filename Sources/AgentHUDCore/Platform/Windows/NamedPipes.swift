#if os(Windows)
import AgentHUDSupport
import Foundation
import WinSDK

/// The named pipes that stand in for the unix-domain sockets of the macOS build.
///
/// A socket path keeps its meaning — the place a hook process and the application meet — and is turned into a pipe
/// name: `\\.\pipe\agenthud-<user SID>-<24 hex>`, the hex an HMAC-SHA-256 of the path, compared without regard to case
/// as Windows compares paths, keyed by a secret beside the path (`pipe.key`, DECISIONS.md D-010). Only the user can
/// read that secret, so another user cannot work out the name and take it first. Only the user can open the pipe: its
/// DACL grants that user's SID alone, a client asks the server for no more than identification, and a client talks only
/// to a server process that runs as the same user. A request is one message; the server reads it whole, which is what
/// a sender closing its writing side means on a socket, and answers with one message before disconnecting.
enum NamedPipes {
    /// The pipe that serves the socket path `path`; nil when the key beside it cannot be read, or, with `creating`,
    /// made. A hook process does not create the key: without one no application serves the path.
    static func name(for path: String, creating: Bool = false) -> String? {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
        guard let key = PipeKey.read(in: folder, creating: creating) else { return nil }
        let mac = PortableHMAC.sha256(key: key, message: Array("agenthud-pipe\0\(normalized)".utf8))
        let hex = mac.prefix(12).map { String(format: "%02x", $0) }.joined()
        return #"\\.\pipe\agenthud-"# + (Win32.currentUserSID ?? "unknown") + "-" + hex
    }

    /// Writes all of `data` to `handle`, opened for overlapped I/O, waiting at most `milliseconds`.
    static func write(_ handle: HANDLE, _ data: Data, milliseconds: DWORD = INFINITE) -> Bool {
        guard !data.isEmpty else { return true }
        guard let overlapped = Overlapped() else { return false }
        return data.withUnsafeBytes { buffer -> Bool in
            var written: DWORD = 0
            if !WriteFile(handle, buffer.baseAddress, DWORD(buffer.count), nil, overlapped.pointer) {
                guard GetLastError() == DWORD(ERROR_IO_PENDING) else { return false }
                guard wait(overlapped, handle: handle, milliseconds: milliseconds) else { return false }
            }
            // With overlapped I/O the count written is known from the operation's result alone.
            guard GetOverlappedResult(handle, overlapped.pointer, &written, false) else { return false }
            return Int(written) == buffer.count
        }
    }

    enum ReadOutcome {
        /// A whole message.
        case message(Data)
        /// The other side closed the pipe before a message began.
        case closed
        /// More than the limit arrived, the deadline passed, `cancel` was set, or the read failed.
        case failed
    }

    /// Reads one whole message from `handle` (message read mode, overlapped I/O), at most `limit` bytes, by `deadline`.
    static func readMessage(_ handle: HANDLE, limit: Int, deadline: Date? = nil, cancel: HANDLE? = nil) -> ReadOutcome {
        guard let overlapped = Overlapped() else { return .failed }
        var message = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            overlapped.reset()
            var count: DWORD = 0
            let result = buffer.withUnsafeMutableBytes { bytes -> DWORD in
                if !ReadFile(handle, bytes.baseAddress, DWORD(bytes.count), nil, overlapped.pointer) {
                    let error = GetLastError()
                    // A part of a longer message (ERROR_MORE_DATA) is a completed read too.
                    guard error == DWORD(ERROR_IO_PENDING) || error == DWORD(ERROR_MORE_DATA) else { return error }
                    if error == DWORD(ERROR_IO_PENDING) {
                        let milliseconds = deadline.map {
                            DWORD(clamping: max(0, Int(($0.timeIntervalSinceNow * 1000).rounded(.up))))
                        } ?? INFINITE
                        guard wait(overlapped, handle: handle, milliseconds: milliseconds, cancel: cancel) else {
                            return DWORD(ERROR_TIMEOUT)
                        }
                    }
                }
                // With overlapped I/O the count read is known from the operation's result alone, also when it ended at once.
                return GetOverlappedResult(handle, overlapped.pointer, &count, false) ? 0 : GetLastError()
            }
            if result == 0 || result == DWORD(ERROR_MORE_DATA) {
                message.append(contentsOf: buffer[..<Int(count)])
                guard message.count <= limit else { return .failed }
                if result == 0 { return .message(message) }
                continue
            }
            if (result == DWORD(ERROR_BROKEN_PIPE) || result == DWORD(ERROR_PIPE_NOT_CONNECTED)) && message.isEmpty {
                return .closed
            }
            return .failed
        }
    }

    /// Waits for an overlapped operation; on timeout or `cancel` the operation is cancelled, waited out, and false
    /// returned.
    static func wait(_ overlapped: Overlapped, handle: HANDLE, milliseconds: DWORD, cancel: HANDLE? = nil) -> Bool {
        let status: DWORD
        if let cancel {
            var handles: [HANDLE?] = [overlapped.event, cancel]
            status = WaitForMultipleObjects(2, &handles, false, milliseconds)
        } else {
            status = WaitForSingleObject(overlapped.event, milliseconds)
        }
        if status == WAIT_OBJECT_0 { return true }
        CancelIoEx(handle, overlapped.pointer)
        var ignored: DWORD = 0
        _ = GetOverlappedResult(handle, overlapped.pointer, &ignored, true)
        return false
    }

    /// Whether the process at the other end of the pipe, its server, runs as this user.
    static func serverIsCurrentUser(_ handle: HANDLE) -> Bool {
        var pid: ULONG = 0
        guard GetNamedPipeServerProcessId(handle, &pid), let sid = Win32.currentUserSID else { return false }
        return Win32.userSID(ofProcess: DWORD(pid)) == sid
    }
}

/// An `OVERLAPPED` and its event on the heap, where it stays put for as long as the I/O it describes is in flight.
final class Overlapped {
    let pointer = UnsafeMutablePointer<OVERLAPPED>.allocate(capacity: 1)
    let event: HANDLE

    init?() {
        guard let event = CreateEventW(nil, true, false, nil) else {
            pointer.deallocate()
            return nil
        }
        self.event = event
        reset()
    }

    /// Ready for the next operation.
    func reset() {
        pointer.initialize(to: OVERLAPPED())
        pointer.pointee.hEvent = event
        ResetEvent(event)
    }

    deinit {
        pointer.deallocate()
        CloseHandle(event)
    }
}

// MARK: - Client side

/// The hook process's side of the channel: the same calls as on macOS, over a named pipe. A descriptor is a C runtime
/// file descriptor over the pipe handle, so `close(_:)` lets it go as it does a socket.
public enum UnixSocket {
    /// Pipe names hold 256 characters, far more than the name made from any path, so every path fits.
    public static func fits(_ path: String) -> Bool { !path.isEmpty }

    /// Connects to the pipe that serves `path`. Nil when none does, nothing accepts in time, or its server runs as
    /// another user.
    public static func connect(to path: String) -> Int32? {
        guard let name = NamedPipes.name(for: path) else { return nil }
        for _ in 0..<3 {
            let handle = Win32.withWide(name) {
                CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_EXISTING),
                            DWORD(FILE_FLAG_OVERLAPPED) | DWORD(SECURITY_SQOS_PRESENT) | Win32.securityIdentification, nil)
            }
            if let handle, handle != Win32.invalidHandle {
                var mode = DWORD(PIPE_READMODE_MESSAGE)
                guard SetNamedPipeHandleState(handle, &mode, nil, nil), NamedPipes.serverIsCurrentUser(handle) else {
                    CloseHandle(handle)
                    return nil
                }
                let descriptor = _open_osfhandle(Int(bitPattern: handle), 0)
                guard descriptor >= 0 else {
                    CloseHandle(handle)
                    return nil
                }
                return descriptor
            }
            guard GetLastError() == DWORD(ERROR_PIPE_BUSY) else { return nil }
            guard Win32.withWide(name, { WaitNamedPipeW($0, 2000) }) else { return nil }
        }
        return nil
    }

    /// Sends `data` as the request, one message; false when the other side went away.
    public static func send(_ descriptor: Int32, _ data: Data) -> Bool {
        guard let handle = handle(descriptor) else { return false }
        return NamedPipes.write(handle, data)
    }

    /// Sends `data` as the request, giving up at `deadline`: an application that stopped reading must not hold the
    /// caller in the middle of a request.
    static func send(_ descriptor: Int32, _ data: Data, until deadline: Date) -> Bool {
        guard let handle = handle(descriptor) else { return false }
        let milliseconds = DWORD(clamping: max(1, Int((deadline.timeIntervalSinceNow * 1000).rounded(.up))))
        return NamedPipes.write(handle, data, milliseconds: milliseconds)
    }

    /// Reads the answer until the other side closes the connection, or until more than `limit` bytes arrived.
    public static func readToEnd(_ descriptor: Int32, limit: Int) -> Data {
        guard let handle = handle(descriptor) else { return Data() }
        var reply = Data()
        while reply.count <= limit {
            switch NamedPipes.readMessage(handle, limit: limit + 1 - reply.count) {
            case .message(let data): reply.append(data)
            case .closed, .failed: return reply
            }
        }
        return reply
    }

    /// The answer, or nil when it has not ended by `deadline` or is longer than `limit`.
    static func read(_ descriptor: Int32, limit: Int, until deadline: Date) -> Data? {
        guard let handle = handle(descriptor) else { return nil }
        var reply = Data()
        while true {
            switch NamedPipes.readMessage(handle, limit: limit - reply.count, deadline: deadline) {
            case .message(let data): reply.append(data)
            case .closed: return reply
            case .failed: return nil
            }
        }
    }

    private static func handle(_ descriptor: Int32) -> HANDLE? {
        let raw = _get_osfhandle(descriptor)
        guard raw != -1, raw != -2 else { return nil }
        return HANDLE(bitPattern: raw)
    }
}

// MARK: - Server side

/// One client's connection to a `UnixSocketListener`, with the calls the application makes on a macOS `NWConnection`:
/// its state and the handler told of changes, sending the answer, and letting it go. Handlers run on the main queue,
/// as an `NWConnection` started on `.main` calls them.
public final class PipeConnection: @unchecked Sendable {
    public enum State: Sendable {
        case setup, ready, cancelled
        case failed(String)
    }

    public enum SendCompletion: Sendable {
        case contentProcessed(@Sendable (Error?) -> Void)
    }

    private enum Command {
        case send(Data, @Sendable (Error?) -> Void)
        case cancel
    }

    // Main-queue state.
    public private(set) var state: State = .setup
    public var stateUpdateHandler: ((State) -> Void)?

    private let handle: HANDLE
    private let wake: HANDLE
    private let lock = NSLock()
    private var commands: [Command] = []

    init(handle: HANDLE) {
        self.handle = handle
        wake = CreateEventW(nil, false, false, nil)!
    }

    deinit { CloseHandle(wake) }

    /// Writes `content` as the answer, one message, and then calls the completion on the main queue.
    public func send(content: Data?, completion: SendCompletion) {
        guard case .contentProcessed(let done) = completion else { return }
        enqueue(.send(content ?? Data(), done))
    }

    /// Ends the connection: the client sees the pipe close.
    public func cancel() { enqueue(.cancel) }

    private func enqueue(_ command: Command) {
        lock.lock()
        commands.append(command)
        lock.unlock()
        SetEvent(wake)
    }

    private func setState(_ new: State) {
        DispatchQueue.main.async { [self] in
            switch state {
            case .cancelled, .failed: return
            default: break
            }
            state = new
            stateUpdateHandler?(new)
        }
    }

    /// The connection's worker: reads the request, hands it over, then waits for the answer or for the client to go.
    func serve(requestLimit: Int, onRequest: @escaping @Sendable (Data, PipeConnection) -> Void) {
        let request: Data
        switch NamedPipes.readMessage(handle, limit: requestLimit, cancel: wake) {
        case .message(let data): request = data
        case .closed, .failed:
            finish()
            return
        }
        setState(.ready)
        onRequest(request, self)
        watch()
    }

    /// Waits for commands, and notices a client that closes its end meanwhile through a read that only ends then.
    private func watch() {
        guard let overlapped = Overlapped() else { return finish() }
        var probe = [UInt8](repeating: 0, count: 1)
        var reading = false
        while true {
            if !reading {
                overlapped.reset()
                var count: DWORD = 0
                let started = probe.withUnsafeMutableBytes { ReadFile(handle, $0.baseAddress, 1, &count, overlapped.pointer) }
                let error = started ? 0 : GetLastError()
                if !started && error != DWORD(ERROR_IO_PENDING) && error != DWORD(ERROR_MORE_DATA) { return finish() }
                // A client that writes again is ignored: one request per connection.
                reading = !started && error == DWORD(ERROR_IO_PENDING)
                if !reading { continue }
            }
            var handles: [HANDLE?] = [overlapped.event, wake]
            let status = WaitForMultipleObjects(2, &handles, false, INFINITE)
            if status == WAIT_OBJECT_0 {
                reading = false
                var count: DWORD = 0
                if !GetOverlappedResult(handle, overlapped.pointer, &count, false), GetLastError() != DWORD(ERROR_MORE_DATA) {
                    return finish()
                }
                continue
            }
            lock.lock()
            let pending = commands
            commands.removeAll()
            lock.unlock()
            for command in pending {
                switch command {
                case .send(let data, let done):
                    let sent = NamedPipes.write(handle, data)
                    // The client reads the answer whole before the pipe is disconnected, which would discard it.
                    if sent { FlushFileBuffers(handle) }
                    DispatchQueue.main.async { done(sent ? nil : Win32.Failure("WriteFile")) }
                case .cancel:
                    if reading {
                        CancelIoEx(handle, overlapped.pointer)
                        var ignored: DWORD = 0
                        _ = GetOverlappedResult(handle, overlapped.pointer, &ignored, true)
                    }
                    return finish()
                }
            }
        }
    }

    private func finish() {
        DisconnectNamedPipe(handle)
        CloseHandle(handle)
        setState(.cancelled)
    }
}

/// On Windows the application's end of a hook's channel is a `PipeConnection`; the shared code calls it by the name it
/// has on macOS.
public typealias NWConnection = PipeConnection

/// The application's side of a `UnixSocket` on Windows: it serves the named pipe of `path` and hands each request, read
/// whole, to `onRequest` with the connection, which answers it or lets it go. One process serves a path: the first
/// instance of a pipe is made with `FILE_FLAG_FIRST_PIPE_INSTANCE`, which fails while another process serves it.
@MainActor
public final class UnixSocketListener {
    public let path: String
    /// The largest request read; a longer one closes its connection.
    public let requestLimit: Int
    private let onRequest: @MainActor (Data, NWConnection) -> Void
    private let category: String
    private var acceptor: Acceptor?

    /// - category: names the channel in the application's log.
    public init(path: String, requestLimit: Int, category: String, onRequest: @escaping @MainActor (Data, NWConnection) -> Void) {
        self.path = path
        self.requestLimit = requestLimit
        self.category = category
        self.onRequest = onRequest
    }

    /// Whether the pipe is served: false once its accept thread has ended on an error it logged.
    public var isListening: Bool { acceptor?.isRunning == true }

    /// Starts serving; false when another process serves the path or the pipe cannot be made.
    @discardableResult
    public func start() -> Bool {
        guard acceptor == nil else { return true }
        let handler = onRequest
        guard let name = NamedPipes.name(for: path, creating: true) else {
            PlatformLog.error(category, "No pipe key could be read or made beside \(path)")
            return false
        }
        let acceptor = Acceptor(name: name, requestLimit: requestLimit, category: category) { data, connection in
            DispatchQueue.main.async { MainActor.assumeIsolated { handler(data, connection) } }
        }
        do {
            try acceptor.start()
        } catch {
            PlatformLog.info(category, "Another instance serves \(path), or its pipe cannot be made: \(error)")
            return false
        }
        self.acceptor = acceptor
        return true
    }

    /// Stops serving. Connections already handed over stay until they are answered or let go.
    public func stop() {
        acceptor?.stop()
        acceptor = nil
    }

    /// The thread that keeps one pipe instance waiting for the next client.
    private final class Acceptor: @unchecked Sendable {
        let name: String
        let requestLimit: Int
        let onRequest: @Sendable (Data, PipeConnection) -> Void
        let category: String
        private let stopEvent = CreateEventW(nil, true, false, nil)!
        private let security: Win32.OwnerOnlySecurity?
        private let running = NSLock()
        private var runs = true

        init(name: String, requestLimit: Int, category: String, onRequest: @escaping @Sendable (Data, PipeConnection) -> Void) {
            self.name = name
            self.requestLimit = requestLimit
            self.category = category
            self.onRequest = onRequest
            security = try? Win32.OwnerOnlySecurity()
        }

        /// Whether the accept thread still keeps an instance waiting.
        var isRunning: Bool { running.withLock { runs } }

        private func ended() { running.withLock { runs = false } }

        deinit { CloseHandle(stopEvent) }

        func start() throws {
            guard security != nil else { throw Win32.Failure("ConvertStringSecurityDescriptorToSecurityDescriptorW") }
            let first = Win32.SendableHandle(handle: try makeInstance(first: true))
            let thread = Thread { [self] in run(first.handle) }
            thread.name = "app.agenthud.pipe-accept"
            thread.start()
        }

        func stop() { SetEvent(stopEvent) }

        private func makeInstance(first: Bool) throws -> HANDLE {
            var flags = DWORD(PIPE_ACCESS_DUPLEX) | DWORD(FILE_FLAG_OVERLAPPED)
            if first { flags |= DWORD(FILE_FLAG_FIRST_PIPE_INSTANCE) }
            let mode = DWORD(PIPE_TYPE_MESSAGE) | DWORD(PIPE_READMODE_MESSAGE) | DWORD(PIPE_WAIT) | DWORD(PIPE_REJECT_REMOTE_CLIENTS)
            let handle = security!.withAttributes { attributes in
                Win32.withWide(name) {
                    CreateNamedPipeW($0, flags, mode, DWORD(PIPE_UNLIMITED_INSTANCES), 64 * 1024, 64 * 1024, 0, attributes)
                }
            }
            guard let handle, handle != Win32.invalidHandle else { throw Win32.Failure("CreateNamedPipeW") }
            return handle
        }

        private func run(_ first: HANDLE) {
            defer { ended() }
            guard let overlapped = Overlapped() else {
                PlatformLog.error(category, "The pipe stops serving: no event for overlapped I/O (\(GetLastError()))")
                CloseHandle(first)
                return
            }
            var instance: HANDLE? = first
            while let handle = instance {
                overlapped.reset()
                var isConnected = ConnectNamedPipe(handle, overlapped.pointer)
                if !isConnected {
                    switch GetLastError() {
                    case DWORD(ERROR_PIPE_CONNECTED):
                        isConnected = true
                    case DWORD(ERROR_IO_PENDING):
                        guard NamedPipes.wait(overlapped, handle: handle, milliseconds: INFINITE, cancel: stopEvent) else {
                            CloseHandle(handle)
                            return
                        }
                        var ignored: DWORD = 0
                        isConnected = GetOverlappedResult(handle, overlapped.pointer, &ignored, false)
                    default:
                        break
                    }
                }
                // The next client finds an instance waiting while this one is served.
                if WaitForSingleObject(stopEvent, 0) == WAIT_OBJECT_0 {
                    instance = nil
                } else {
                    do {
                        instance = try makeInstance(first: false)
                    } catch {
                        // Not swallowed: the listener says it no longer listens, and the log says why.
                        PlatformLog.error(category, "The pipe stops serving: its next instance cannot be made: \(error)")
                        instance = nil
                    }
                }
                if isConnected {
                    let connection = PipeConnection(handle: handle)
                    let limit = requestLimit, onRequest = onRequest
                    let worker = Thread { connection.serve(requestLimit: limit, onRequest: onRequest) }
                    worker.name = "app.agenthud.pipe-connection"
                    worker.start()
                } else {
                    DisconnectNamedPipe(handle)
                    CloseHandle(handle)
                }
            }
        }
    }
}
#endif
