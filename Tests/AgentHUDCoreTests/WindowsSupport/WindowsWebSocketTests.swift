#if os(Windows)
import Foundation
import XCTest
@testable import AgentHUDCore

/// The WinHTTP WebSocket the DeepSeek question stream uses on Windows (`Platform/Windows/WindowsWebSocket.swift`, D-040),
/// against Winsock hosts on 127.0.0.1: a quiet stream stays open past its handshake's timeout, messages come out whole,
/// the stream ends when the host closes or answers without upgrading, and a cancel says goodbye and ends it.
final class WindowsWebSocketTests: XCTestCase, @unchecked Sendable {
    private func host() throws -> IdleQuestionHost {
        let host = try IdleQuestionHost()
        addTeardownBlock { host.stop() }
        return host
    }

    private func eventually(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The next message, or nil when the stream finished first.
    private func next(_ socket: WindowsWebSocket) async -> WindowsWebSocket.Message? {
        var iterator = socket.messages.makeAsyncIterator()
        return await iterator.next()
    }

    func testAQuietStreamOutlastsItsHandshakeTimeoutAndDeliversWholeMessages() async throws {
        let host = try host()
        let socket = WindowsWebSocket(port: host.port, path: "/api/events.mux", timeout: 1)
        defer { socket.cancel() }
        try await eventually { host.connected }
        // Silence for longer than every timeout of the handshake.
        try await Task.sleep(for: .milliseconds(2500))
        XCTAssertTrue(host.send(opcode: 0x1, Array(#"{"type":"问题"}"#.utf8)))
        var messages = socket.messages.makeAsyncIterator()
        let first = await messages.next()
        XCTAssertEqual(first, .string(#"{"type":"问题"}"#))
        // A message in two fragments comes out as one; a binary one as data.
        XCTAssertTrue(host.send(opcode: 0x1, Array(#"{"a":"#.utf8), final: false))
        XCTAssertTrue(host.send(opcode: 0x0, Array("1}".utf8)))
        XCTAssertTrue(host.send(opcode: 0x2, [0, 1, 2]))
        let joined = await messages.next(), binary = await messages.next()
        XCTAssertEqual(joined, .string(#"{"a":1}"#))
        XCTAssertEqual(binary, .data(Data([0, 1, 2])))
    }

    func testTheStreamEndsWhenTheHostCloses() async throws {
        let host = try host()
        let socket = WindowsWebSocket(port: host.port, path: "/api/events.mux", timeout: 5)
        defer { socket.cancel() }
        try await eventually { host.connected }
        XCTAssertTrue(host.send(opcode: 0x8, [0x03, 0xE8])) // close, 1000
        let message = await next(socket)
        XCTAssertNil(message, "the stream finished")
    }

    func testAHostThatDoesNotUpgradeEndsTheStream() async throws {
        let host = try LoopbackHTTPHost { _ in LoopbackHTTPHost.response(200, "OK", body: Data(#"{"type":"x"}"#.utf8)) }
        defer { host.stop() }
        let socket = WindowsWebSocket(port: host.port, path: "/api/events.mux", timeout: 5)
        let message = await next(socket)
        XCTAssertNil(message, "no WebSocket, no message")
        XCTAssertEqual(host.requests.first?.line, "GET /api/events.mux HTTP/1.1")
        XCTAssertEqual(host.requests.first?.header("Upgrade")?.lowercased(), "websocket")
    }

    func testCancellingSaysGoingAwayAndEndsTheConnection() async throws {
        let host = try host()
        let socket = WindowsWebSocket(port: host.port, path: "/api/events.mux", timeout: 5)
        try await eventually { host.connected }
        socket.cancel()
        let message = await next(socket)
        XCTAssertNil(message)
        try await eventually(2) { host.disconnected }
        // The client's close frame: FIN + close, masked, a two-byte payload; unmasked, the status 1001.
        let frame = host.received
        XCTAssertGreaterThanOrEqual(frame.count, 8, "\(frame)")
        guard frame.count >= 8 else { return }
        XCTAssertEqual(frame[0], 0x88)
        XCTAssertEqual(frame[1], 0x80 | 2)
        let mask = Array(frame[2..<6])
        XCTAssertEqual([frame[6] ^ mask[0], frame[7] ^ mask[1]], [0x03, 0xE9])
        socket.cancel() // again: nothing happens
    }

    func testCancellingBeforeTheHandshakeEndsAtOnce() async throws {
        // A host that never answers the upgrade: the cancel ends the waiting handshake, not its timeout.
        let host = try LoopbackHTTPHost { _ in .silent }
        defer { host.stop() }
        let socket = WindowsWebSocket(port: host.port, path: "/api/events.mux", timeout: 30)
        try await eventually { host.requests.count == 1 }
        let started = Date()
        socket.cancel()
        let message = await next(socket)
        XCTAssertNil(message)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}
#endif
