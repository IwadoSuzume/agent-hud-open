#if os(Windows)
import CWinHTTP
import Foundation
import WinSDK

/// A client WebSocket to a loopback host over WinHTTP, the Windows side of the DeepSeek Harness question stream
/// (DECISIONS.md D-040). swift-corelibs' `URLSessionWebSocketTask` ends a stream on which the host sends nothing, which a
/// question stream mostly is; WinHTTP's socket waits for as long as the connection lasts.
///
/// The socket lives on a thread of its own, which opens it and reads it, so that a quiet stream holds no thread of the
/// Swift runtime's pool; each whole message (fragments joined, up to `messageLimit`) comes out of `messages`, which
/// finishes when the connection ends, whichever side ends it. Only `ws://127.0.0.1` is asked for, with the rules
/// provider requests go by (no proxy, no redirect, no cookie, no WinHTTP authentication; a request whose rules cannot all
/// be set is not sent). `cancel()` sends a close frame (1001, going away) and drops the connection without waiting for
/// the host's.
final class WindowsWebSocket: @unchecked Sendable {
    enum Message: Sendable, Equatable {
        case data(Data)
        case string(String)
    }

    static let messageLimit = 16 * 1024 * 1024

    let messages: AsyncStream<Message>
    private let continuation: AsyncStream<Message>.Continuation
    private let lock = NSLock()
    private var cancelled = false
    /// The handle a cancel must close to end whichever call the thread is waiting in: the request during the handshake,
    /// the socket after it.
    private var waiting: Win32.SendableHandle?

    /// Starts connecting to `ws://127.0.0.1:<port><path>`; `timeout` bounds each step of the handshake.
    init(port: Int, path: String, timeout: TimeInterval) {
        (messages, continuation) = AsyncStream.makeStream(of: Message.self, bufferingPolicy: .unbounded)
        let thread = Thread { [self] in run(port: port, path: path, timeout: timeout) }
        thread.name = "app.agenthud.websocket"
        thread.start()
    }

    /// Ends the connection; `messages` finishes. Calling it again does nothing.
    func cancel() {
        let handle = lock.withLock { () -> Win32.SendableHandle? in
            guard !cancelled else { return nil }
            cancelled = true
            defer { waiting = nil }
            return waiting
        }
        guard let handle else { return }
        // The close frame only goes out on an open socket; on a request handle it fails, which is fine.
        _ = WinHttpWebSocketShutdown(handle.handle, USHORT(WINHTTP_WEB_SOCKET_ENDPOINT_TERMINATED_CLOSE_STATUS.rawValue), nil, 0)
        WinHttpCloseHandle(handle.handle)
    }

    /// Hands `handle` to `cancel` while the thread waits on it; false when a cancel came first.
    private func wait(on handle: HINTERNET) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            waiting = Win32.SendableHandle(handle: handle)
            return true
        }
    }

    /// Runs `body` — calls on the handle `cancel` may close, that do not block — while `cancel` cannot close it; nil
    /// when a cancel came first. A blocking call (the handshake's send and receive, a socket receive) is only begun after
    /// `stillOpen()`: `cancel` closing its handle is what ends it, and the window between the check and the call is the
    /// one race left (D-040).
    private func whileOpen<Result>(_ body: () -> Result) -> Result? {
        lock.withLock { cancelled ? nil : body() }
    }

    private func stillOpen() -> Bool { lock.withLock { !cancelled } }

    /// Takes `handle` back from `cancel`: true when the thread still owns it and must close it itself.
    private func reclaim() -> Bool {
        lock.withLock {
            defer { waiting = nil }
            return waiting != nil
        }
    }

    private func run(port: Int, path: String, timeout: TimeInterval) {
        defer { continuation.finish() }
        guard (1...65535).contains(port) else { return }
        let milliseconds = Int32(clamping: Int(max(1, timeout) * 1000))
        guard let session = Win32.withWide("Agent HUD Open", { WinHttpOpen($0, DWORD(WINHTTP_ACCESS_TYPE_NO_PROXY), nil, nil, 0) }) else {
            return
        }
        defer { WinHttpCloseHandle(session) }
        WinHttpSetTimeouts(session, milliseconds, milliseconds, milliseconds, milliseconds)
        guard let connection = Win32.withWide("127.0.0.1", { WinHttpConnect(session, $0, INTERNET_PORT(port), 0) }) else { return }
        defer { WinHttpCloseHandle(connection) }
        guard let request = Win32.withWide("GET", { verb in
            Win32.withWide(path) { target in WinHttpOpenRequest(connection, verb, target, nil, nil, nil, 0) }
        }) else { return }
        guard wait(on: request) else { WinHttpCloseHandle(request); return }

        var never = DWORD(WINHTTP_OPTION_REDIRECT_POLICY_NEVER)
        var disabled = DWORD(WINHTTP_DISABLE_COOKIES) | DWORD(WINHTTP_DISABLE_AUTHENTICATION)
        var status: DWORD = 0
        var size = DWORD(MemoryLayout<DWORD>.size)
        let configured = whileOpen {
            WinHttpSetOption(request, DWORD(WINHTTP_OPTION_REDIRECT_POLICY), &never, DWORD(MemoryLayout<DWORD>.size))
                && WinHttpSetOption(request, DWORD(WINHTTP_OPTION_DISABLE_FEATURE), &disabled, DWORD(MemoryLayout<DWORD>.size))
                && WinHttpSetOption(request, DWORD(WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET), nil, 0)
        } == true
        let answered = configured && stillOpen() && WinHttpSendRequest(request, nil, 0, nil, 0, 0, 0)
            && stillOpen() && WinHttpReceiveResponse(request, nil)
        let socket = answered ? whileOpen { () -> HINTERNET? in
            let query = DWORD(WINHTTP_QUERY_STATUS_CODE) | DWORD(WINHTTP_QUERY_FLAG_NUMBER)
            guard WinHttpQueryHeaders(request, query, nil, &status, &size, nil), status == 101 else { return nil }
            return WinHttpWebSocketCompleteUpgrade(request, 0)
        } ?? nil : nil
        if reclaim() { WinHttpCloseHandle(request) }
        guard let socket else { return }
        guard wait(on: socket) else { WinHttpCloseHandle(socket); return }
        defer { if reclaim() { WinHttpCloseHandle(socket) } }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var message = Data()
        while stillOpen() {
            var count: DWORD = 0
            var type = WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE
            let failure = buffer.withUnsafeMutableBytes {
                WinHttpWebSocketReceive(socket, $0.baseAddress, DWORD($0.count), &count, &type)
            }
            guard failure == DWORD(ERROR_SUCCESS), type != WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE else { return }
            message.append(contentsOf: buffer[..<Int(count)])
            guard message.count <= Self.messageLimit else { return }
            switch type {
            case WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE:
                continuation.yield(.data(message))
            case WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE:
                // A text message is UTF-8 by the protocol; one that is not is dropped, as a frame Core cannot read.
                if let text = String(data: message, encoding: .utf8) { continuation.yield(.string(text)) }
            default:
                continue // a fragment: the rest of the message follows
            }
            message = Data()
        }
    }
}
#endif
