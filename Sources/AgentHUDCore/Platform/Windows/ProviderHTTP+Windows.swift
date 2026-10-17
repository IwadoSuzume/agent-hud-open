#if os(Windows)
import CWinHTTP
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import WinSDK

extension ProviderHTTP {
    /// The request over WinHTTP, with the rules the macOS build sends it by: no redirect is followed (the redirect is
    /// the answer, and not a success), no cookie is stored or sent and nothing is cached, the request's timeout bounds
    /// each step and one second more the whole exchange, a body over 16 MB fails, and a loopback server's certificate,
    /// which a client's local service signs itself, is accepted for 127.0.0.1 alone. The system's proxy settings apply,
    /// as they do to URLSession on macOS; loopback requests never go through a proxy.
    static func requestData(_ request: URLRequest) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let (status, data) = try WindowsHTTP.send(request)
            guard (200..<300).contains(status) else { throw ProviderHTTPError(status: status) }
            return data
        }.value
    }
}

/// Synchronous WinHTTP exchanges, each in its own session, run off the main thread.
enum WindowsHTTP {
    static let bodyLimit = 16 * 1024 * 1024

    /// The status and body of one exchange.
    static func send(_ request: URLRequest) throws -> (status: Int, body: Data) {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = parts.host, !host.isEmpty else { throw ProviderFailure.format }
        let secure = scheme == "https"
        let loopback = ["127.0.0.1", "localhost", "::1"].contains(host.lowercased())
        let port = INTERNET_PORT(parts.port ?? (secure ? 443 : 80))
        var target = parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath
        if let query = parts.percentEncodedQuery { target += "?" + query }
        let timeout = max(1, request.timeoutInterval)
        let milliseconds = Int32(clamping: Int(timeout * 1000))

        let access = loopback ? DWORD(WINHTTP_ACCESS_TYPE_NO_PROXY) : DWORD(WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY)
        guard let session = Win32.withWide("Agent HUD Open", { WinHttpOpen($0, access, nil, nil, 0) }) else {
            throw ProviderFailure.local
        }
        defer { WinHttpCloseHandle(session) }
        WinHttpSetTimeouts(session, milliseconds, milliseconds, milliseconds, milliseconds)
        guard let connection = Win32.withWide(host, { WinHttpConnect(session, $0, port, 0) }) else { throw ProviderFailure.local }
        defer { WinHttpCloseHandle(connection) }
        let method = request.httpMethod ?? "GET"
        let flags = secure ? DWORD(WINHTTP_FLAG_SECURE) : 0
        let opened = Win32.withWide(method) { verb in
            Win32.withWide(target) { path in WinHttpOpenRequest(connection, verb, path, nil, nil, nil, flags) }
        }
        guard let handle = opened else { throw ProviderFailure.local }
        // The whole exchange is bounded too: closing the handle ends whichever call is waiting.
        let watchdog = Watchdog(handle: handle, seconds: timeout + 1)
        defer { watchdog.finish() }

        // A request whose rules cannot all be set is not sent: a credential must never follow a redirect (D-014).
        var never = DWORD(WINHTTP_OPTION_REDIRECT_POLICY_NEVER)
        var disabled = DWORD(WINHTTP_DISABLE_COOKIES) | DWORD(WINHTTP_DISABLE_AUTHENTICATION)
        guard WinHttpSetOption(handle, DWORD(WINHTTP_OPTION_REDIRECT_POLICY), &never, DWORD(MemoryLayout<DWORD>.size)),
              WinHttpSetOption(handle, DWORD(WINHTTP_OPTION_DISABLE_FEATURE), &disabled, DWORD(MemoryLayout<DWORD>.size))
        else { throw ProviderFailure.local }
        if secure, host == "127.0.0.1" {
            var ignore = DWORD(SECURITY_FLAG_IGNORE_UNKNOWN_CA) | DWORD(SECURITY_FLAG_IGNORE_CERT_CN_INVALID)
                | DWORD(SECURITY_FLAG_IGNORE_CERT_DATE_INVALID) | DWORD(SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE)
            guard WinHttpSetOption(handle, DWORD(WINHTTP_OPTION_SECURITY_FLAGS), &ignore, DWORD(MemoryLayout<DWORD>.size)) else {
                throw ProviderFailure.local
            }
        }
        let headers = (request.allHTTPHeaderFields ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        if !headers.isEmpty {
            _ = Win32.withWide(headers.joined(separator: "\r\n")) {
                WinHttpAddRequestHeaders(handle, $0, DWORD(bitPattern: -1),
                                         DWORD(WINHTTP_ADDREQ_FLAG_ADD) | DWORD(WINHTTP_ADDREQ_FLAG_REPLACE))
            }
        }
        var body = [UInt8](request.httpBody ?? Data())
        let sent = body.withUnsafeMutableBytes { bytes in
            WinHttpSendRequest(handle, nil, 0, bytes.baseAddress, DWORD(bytes.count), DWORD(bytes.count), 0)
        }
        guard sent, WinHttpReceiveResponse(handle, nil) else {
            throw watchdog.expired ? URLError(.timedOut) : URLError(.cannotConnectToHost)
        }
        var status: DWORD = 0
        var size = DWORD(MemoryLayout<DWORD>.size)
        let query = DWORD(WINHTTP_QUERY_STATUS_CODE) | DWORD(WINHTTP_QUERY_FLAG_NUMBER)
        guard WinHttpQueryHeaders(handle, query, nil, &status, &size, nil) else { throw ProviderFailure.format }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            var count: DWORD = 0
            let read = buffer.withUnsafeMutableBytes { WinHttpReadData(handle, $0.baseAddress, DWORD($0.count), &count) }
            guard read else { throw watchdog.expired ? URLError(.timedOut) : URLError(.networkConnectionLost) }
            if count == 0 { break }
            data.append(contentsOf: buffer[..<Int(count)])
            guard data.count <= bodyLimit else { throw ProviderFailure.limit }
        }
        return (Int(status), data)
    }

    /// Owns a request's handle: closes it once the exchange is over, or earlier when its time is up, which makes the
    /// call waiting on it fail.
    private final class Watchdog: @unchecked Sendable {
        private let done = CreateEventW(nil, true, false, nil)!
        private let handle: Win32.SendableHandle
        private let lock = NSLock()
        private var fired = false, finished = false

        init(handle: HINTERNET, seconds: TimeInterval) {
            self.handle = Win32.SendableHandle(handle: handle)
            let milliseconds = DWORD(clamping: Int(seconds * 1000))
            let thread = Thread { [self] in
                guard WaitForSingleObject(done, milliseconds) != WAIT_OBJECT_0 else { return }
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                fired = true
                WinHttpCloseHandle(self.handle.handle)
            }
            thread.name = "app.agenthud.http-watchdog"
            thread.start()
        }

        var expired: Bool {
            lock.lock()
            defer { lock.unlock() }
            return fired
        }

        /// The exchange is over: the handle is closed, unless the time ran out and closed it first.
        func finish() {
            lock.lock()
            finished = true
            let close = !fired
            lock.unlock()
            SetEvent(done)
            if close { WinHttpCloseHandle(handle.handle) }
        }

        deinit { CloseHandle(done) }
    }
}
#endif
