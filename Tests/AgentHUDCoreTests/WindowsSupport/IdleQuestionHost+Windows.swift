#if os(Windows)
import AgentHUDSupport
import Foundation
import WinSDK

/// DeepSeekQuestionObserverTests' idle Harness host on Winsock, with the API of the macOS one in that file: on
/// 127.0.0.1 and a port the system picks, the WebSocket handshake completes, then the host stays silent until the
/// client closes its socket. On Windows it can also send frames and keeps what the client sent after the handshake
/// (WindowsWebSocketTests).
final class IdleQuestionHost: @unchecked Sendable {
    let port: Int
    private let listener: SOCKET
    private let lock = NSLock()
    private var client: SOCKET?
    private var stopped = false
    private var opened = false
    private var ended = false
    private var after: [UInt8] = []
    var connected: Bool { lock.withLock { opened } }
    /// The bytes the client sent after the handshake: its frames, masked as a client's are.
    var received: [UInt8] { lock.withLock { after } }
    var disconnected: Bool { lock.withLock { ended } }

    init() throws {
        var startup = WSADATA()
        guard WSAStartup(0x0202, &startup) == 0 else { throw Failure.socket }
        let descriptor = WinSDK.socket(AF_INET, Int32(SOCK_STREAM), Int32(IPPROTO_TCP.rawValue))
        guard descriptor != INVALID_SOCKET else { throw Failure.socket }
        listener = descriptor
        // No other socket may share the port, on any address.
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
        guard bound == 0, named == 0, listen(descriptor, 1) == 0 else {
            closesocket(descriptor)
            throw Failure.socket
        }
        port = Int(UInt16(bigEndian: address.sin_port))
        DispatchQueue.global().async { self.serve() }
    }

    func stop() {
        let state = lock.withLock { () -> (Bool, SOCKET?) in
            guard !stopped else { return (false, nil) }
            stopped = true
            return (true, client)
        }
        guard state.0 else { return }
        if let client = state.1 { shutdown(client, Int32(SD_BOTH)) }
        closesocket(listener)
    }

    /// Sends one unmasked server frame (`FIN` set unless `final` is false) once the handshake is done; false otherwise.
    @discardableResult
    func send(opcode: UInt8, _ payload: [UInt8], final: Bool = true) -> Bool {
        guard let socket = lock.withLock({ opened ? client : nil }), payload.count < 126 else { return false }
        let frame = [(final ? 0x80 : 0) | opcode, UInt8(payload.count)] + payload
        return frame.withUnsafeBytes { WinSDK.send(socket, $0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32($0.count), 0) } == Int32(frame.count)
    }

    private func receive(_ socket: SOCKET, _ buffer: inout [UInt8]) -> Int32 {
        let count = Int32(buffer.count)
        return buffer.withUnsafeMutableBytes { recv(socket, $0.baseAddress!.assumingMemoryBound(to: CChar.self), count, 0) }
    }

    private func serve() {
        var ready = WSAPOLLFD(fd: listener, events: Int16(POLLRDNORM), revents: 0)
        guard WSAPoll(&ready, 1, 2000) > 0 else { return }
        let socket = accept(listener, nil, nil)
        guard socket != INVALID_SOCKET else { return }
        lock.withLock { client = socket }
        defer { lock.withLock { client = nil; ended = true }; closesocket(socket) }
        var timeout = DWORD(2000)
        _ = withUnsafePointer(to: &timeout) {
            $0.withMemoryRebound(to: CChar.self, capacity: 4) {
                setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, $0, Int32(MemoryLayout<DWORD>.size))
            }
        }
        var header = Data()
        var byte = [UInt8](repeating: 0, count: 1)
        while !header.suffix(4).elementsEqual([13, 10, 13, 10]) {
            guard receive(socket, &byte) == 1 else { return }
            header.append(byte[0])
        }
        guard let request = String(data: header, encoding: .utf8),
              let line = request.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("sec-websocket-key:") }),
              let key = line.split(separator: ":", maxSplits: 1).last else { return }
        let challenge = key.trimmingCharacters(in: .whitespaces) + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let accept = Data(Insecure.SHA1.hash(data: Data(challenge.utf8))).base64EncodedString()
        let response = Array(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                              + "Connection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n").utf8)
        let sent = response.withUnsafeBytes { WinSDK.send(socket, $0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32($0.count), 0) }
        guard sent == Int32(response.count) else { return }
        lock.withLock { opened = true }
        var bytes = [UInt8](repeating: 0, count: 256)
        while true {
            let count = receive(socket, &bytes)
            // The 2 s receive timeout only bounds the handshake; a quiet client is waited for until it goes or the
            // host stops.
            if count < 0, WSAGetLastError() == WSAETIMEDOUT, !lock.withLock({ stopped }) { continue }
            guard count > 0 else { break }
            lock.withLock { after += bytes[..<Int(count)] }
        }
    }

    private enum Failure: Error { case socket }
}
#endif
