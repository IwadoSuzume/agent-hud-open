#if os(Windows)
import Foundation
import WinSDK

/// An HTTP/1.1 host on 127.0.0.1 and a port the system picks, on Winsock, for ProviderHTTPWindowsTests: each connection
/// is read as one request (its head up to the blank line and a `Content-Length` body), recorded, and answered with what
/// `reply` gives, or left silent until the host stops. Nothing leaves the machine.
final class LoopbackHTTPHost: @unchecked Sendable {
    struct Request: Sendable {
        /// The request line, `GET /path HTTP/1.1`.
        let line: String
        let headers: [(name: String, value: String)]
        let body: Data

        /// The value of the header called `name`, whatever its case; nil when the request has none.
        func header(_ name: String) -> String? {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    enum Reply: Sendable {
        case send(Data)
        /// Read the request, then say nothing until the host stops.
        case silent
    }

    let port: Int
    private let listener: SOCKET
    private let reply: @Sendable (Request) -> Reply
    private let lock = NSLock()
    private var stopped = false
    private var accepted = 0
    private var recorded: [Request] = []
    private var open: [SOCKET] = []

    /// How many connections the host accepted.
    var connections: Int { lock.withLock { accepted } }
    var requests: [Request] { lock.withLock { recorded } }

    init(reply: @escaping @Sendable (Request) -> Reply) throws {
        self.reply = reply
        var startup = WSADATA()
        guard WSAStartup(0x0202, &startup) == 0 else { throw Failure.socket }
        let descriptor = WinSDK.socket(AF_INET, Int32(SOCK_STREAM), Int32(IPPROTO_TCP.rawValue))
        guard descriptor != INVALID_SOCKET else { throw Failure.socket }
        listener = descriptor
        var exclusive: Int32 = 1
        _ = withUnsafePointer(to: &exclusive) {
            $0.withMemoryRebound(to: CChar.self, capacity: 4) {
                // SO_EXCLUSIVEADDRUSE, a macro Swift does not import: ~SO_REUSEADDR.
                setsockopt(descriptor, SOL_SOCKET, ~SO_REUSEADDR, $0, Int32(MemoryLayout<Int32>.size))
            }
        }
        var address = sockaddr_in()
        address.sin_family = ADDRESS_FAMILY(AF_INET)
        address.sin_addr.S_un.S_addr = UInt32(0x7F00_0001).bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, Int32(MemoryLayout<sockaddr_in>.size)) }
        }
        var size = Int32(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
        }
        guard bound == 0, named == 0, listen(descriptor, 8) == 0 else {
            closesocket(descriptor)
            throw Failure.socket
        }
        port = Int(UInt16(bigEndian: address.sin_port))
        let thread = Thread { [self] in serve() }
        thread.name = "app.agenthud.tests.http-host"
        thread.start()
    }

    /// Stops accepting and ends every connection still open, a silent one too.
    func stop() {
        let sockets = lock.withLock { () -> [SOCKET]? in
            guard !stopped else { return nil }
            stopped = true
            return open
        }
        guard let sockets else { return }
        for socket in sockets { shutdown(socket, Int32(SD_BOTH)) }
        closesocket(listener)
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func serve() {
        while !isStopped {
            var ready = WSAPOLLFD(fd: listener, events: Int16(POLLRDNORM), revents: 0)
            guard WSAPoll(&ready, 1, 100) >= 0 else { return }
            guard ready.revents != 0, !isStopped else { continue }
            let socket = accept(listener, nil, nil)
            guard socket != INVALID_SOCKET else { continue }
            lock.withLock { accepted += 1; open.append(socket) }
            DispatchQueue.global().async { self.answer(socket) }
        }
    }

    private func answer(_ socket: SOCKET) {
        defer {
            lock.withLock { open.removeAll { $0 == socket } }
            closesocket(socket)
        }
        var timeout = DWORD(5000)
        _ = withUnsafePointer(to: &timeout) {
            $0.withMemoryRebound(to: CChar.self, capacity: 4) {
                setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, $0, Int32(MemoryLayout<DWORD>.size))
            }
        }
        guard let request = read(socket) else { return }
        lock.withLock { recorded.append(request) }
        switch reply(request) {
        case .send(let data):
            var bytes = [UInt8](data), offset = 0
            while offset < bytes.count {
                let count = Int32(min(bytes.count - offset, 1 << 20))
                let sent = bytes.withUnsafeMutableBytes {
                    send(socket, $0.baseAddress!.advanced(by: offset).assumingMemoryBound(to: CChar.self), count, 0)
                }
                guard sent > 0 else { return }
                offset += Int(sent)
            }
            shutdown(socket, Int32(SD_SEND))
            // Wait for the client to close its end, so it reads everything before the socket goes.
            var byte = [UInt8](repeating: 0, count: 256)
            while receive(socket, &byte) > 0 { }
        case .silent:
            var byte = [UInt8](repeating: 0, count: 256)
            while !isStopped, receive(socket, &byte) != 0 { }
        }
    }

    private func receive(_ socket: SOCKET, _ buffer: inout [UInt8]) -> Int32 {
        let count = Int32(buffer.count)
        return buffer.withUnsafeMutableBytes { recv(socket, $0.baseAddress!.assumingMemoryBound(to: CChar.self), count, 0) }
    }

    private func read(_ socket: SOCKET) -> Request? {
        var head = Data()
        var byte = [UInt8](repeating: 0, count: 1)
        while !head.suffix(4).elementsEqual([13, 10, 13, 10]) {
            guard receive(socket, &byte) == 1, head.count < 64 * 1024 else { return nil }
            head.append(byte[0])
        }
        let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard let line = lines.first else { return nil }
        let headers = lines.dropFirst().compactMap { field -> (name: String, value: String)? in
            guard let colon = field.firstIndex(of: ":") else { return nil }
            return (String(field[..<colon]), field[field.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        let length = headers.first { $0.name.lowercased() == "content-length" }.flatMap { Int($0.value) } ?? 0
        var body = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while body.count < length {
            let count = receive(socket, &chunk)
            guard count > 0 else { return nil }
            body.append(contentsOf: chunk[..<Int(count)])
        }
        return Request(line: line, headers: headers, body: body)
    }

    /// A whole HTTP/1.1 response that closes its connection.
    static func response(_ status: Int, _ reason: String, headers: [String: String] = [:], body: Data = Data()) -> Reply {
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        return .send(Data((head + "\r\n").utf8) + body)
    }

    private enum Failure: Error { case socket }
}
#endif
