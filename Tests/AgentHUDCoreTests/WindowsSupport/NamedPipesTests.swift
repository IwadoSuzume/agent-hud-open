#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// The named pipes that stand in for unix sockets on Windows (Platform/Windows/NamedPipes.swift): one process serves a
/// path, only this user reaches it, a request is one message read whole, and the client sees the answer and then the
/// end of the connection — the rules UnixSocketListenerTests holds the macOS socket to.
@MainActor
final class NamedPipesTests: XCTestCase {
    private func path() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("agenthud-pipe-\(UUID().uuidString).sock").path
    }

    /// Sends `request` the way a hook process does and returns what came back, off the main actor.
    nonisolated private static func exchange(_ request: Data, path: String) async -> Data? {
        await Task.detached {
            guard let descriptor = UnixSocket.connect(to: path) else { return nil }
            defer { _close(descriptor) }
            guard UnixSocket.send(descriptor, request) else { return nil }
            return UnixSocket.readToEnd(descriptor, limit: 1024 * 1024)
        }.value
    }

    func testARequestIsReadWholeAndTheAnswerEndsTheConnection() async throws {
        let path = path()
        var received: [Data] = []
        let listener = UnixSocketListener(path: path, requestLimit: 1024 * 1024, category: "test") { data, connection in
            received.append(data)
            connection.send(content: Data("answer to ".utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
        }
        XCTAssertTrue(listener.start())
        defer { listener.stop() }
        // Larger than a pipe buffer, so the message arrives in pieces.
        let request = Data(String(repeating: "é中😀", count: 40_000).utf8)
        let answer = await Self.exchange(request, path: path)
        XCTAssertEqual(answer, Data("answer to ".utf8) + request)
        XCTAssertEqual(received, [request])
    }

    func testOneProcessServesAPathAndAnotherPathIsItsOwn() throws {
        let path = path()
        let first = UnixSocketListener(path: path, requestLimit: 1024, category: "test") { _, connection in connection.cancel() }
        let second = UnixSocketListener(path: path, requestLimit: 1024, category: "test") { _, connection in connection.cancel() }
        let differentCase = UnixSocketListener(path: path.uppercased(), requestLimit: 1024, category: "test") { _, c in c.cancel() }
        let other = UnixSocketListener(path: self.path(), requestLimit: 1024, category: "test") { _, connection in connection.cancel() }
        XCTAssertTrue(first.start())
        defer { first.stop(); other.stop() }
        XCTAssertFalse(second.start(), "a second listener does not take the path from the first")
        XCTAssertFalse(differentCase.start(), "Windows paths are the same whatever their case")
        XCTAssertTrue(other.start())
        XCTAssertTrue(first.isListening)
        XCTAssertFalse(second.isListening)
    }

    func testAStoppedListenerLeavesThePathFree() async throws {
        let path = path()
        let listener = UnixSocketListener(path: path, requestLimit: 1024, category: "test") { _, connection in connection.cancel() }
        XCTAssertTrue(listener.start())
        listener.stop()
        // The accept thread lets its instance go once it sees the stop.
        var restarted = false
        for _ in 0..<50 where !restarted {
            let again = UnixSocketListener(path: path, requestLimit: 1024, category: "test") { _, connection in connection.cancel() }
            restarted = again.start()
            if restarted { again.stop() } else { try await Task.sleep(for: .milliseconds(20)) }
        }
        XCTAssertTrue(restarted)
        XCTAssertNil(UnixSocket.connect(to: self.path()), "nothing serves a path nobody listens on")
    }

    func testARequestOverTheLimitIsLetGoUnanswered() async throws {
        let path = path()
        var calls = 0
        let listener = UnixSocketListener(path: path, requestLimit: 16, category: "test") { _, connection in
            calls += 1
            connection.cancel()
        }
        XCTAssertTrue(listener.start())
        defer { listener.stop() }
        let answer = await Self.exchange(Data(repeating: 0x41, count: 17), path: path)
        XCTAssertEqual(answer, Data(), "the connection closes without an answer")
        XCTAssertEqual(calls, 0, "an oversized request never reaches the handler")
    }

    func testAClientThatGoesAwayIsSeenAsCancelled() async throws {
        let path = path()
        let ended = expectation(description: "the request is withdrawn when its client goes")
        let listener = UnixSocketListener(path: path, requestLimit: 1024, category: "test") { _, connection in
            connection.stateUpdateHandler = { state in
                if case .cancelled = state { ended.fulfill() }
            }
        }
        XCTAssertTrue(listener.start())
        defer { listener.stop() }
        await Task.detached {
            guard let descriptor = UnixSocket.connect(to: path) else { return XCTFail("connects") }
            XCTAssertTrue(UnixSocket.send(descriptor, Data("waiting".utf8)))
            Sleep(200)
            _close(descriptor)
        }.value
        await fulfillment(of: [ended], timeout: 5)
    }

    func testThePipeLetsOnlyThisUserIn() throws {
        let path = path()
        let listener = UnixSocketListener(path: path, requestLimit: 1024, category: "test") { _, connection in connection.cancel() }
        XCTAssertTrue(listener.start())
        defer { listener.stop() }
        let name = try XCTUnwrap(NamedPipes.name(for: path))
        XCTAssertTrue(name.hasPrefix(#"\\.\pipe\agenthud-"# + (Win32.currentUserSID ?? "?") + "-"))
        // The pipe's DACL names one trustee, this user, and lets nobody else in.
        let handle = Win32.withWide(name) {
            CreateFileW($0, DWORD(READ_CONTROL), 0, nil, DWORD(OPEN_EXISTING), 0, nil)
        }
        guard let handle, handle != Win32.invalidHandle else { return XCTFail("the pipe opens for reading its security") }
        defer { CloseHandle(handle) }
        assertOwnerOnly(try daclText(handle, type: SE_KERNEL_OBJECT))
    }

    func testThePipeKeyIsMadeOnceAndOnlyThisUserCanReadIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud-pipekey-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("x.sock").path
        XCTAssertNil(NamedPipes.name(for: path), "without a key nothing serves the path and a client does not connect")
        XCTAssertNil(UnixSocket.connect(to: path))
        let listener = UnixSocketListener(path: path, requestLimit: 1024, category: "test") { _, connection in connection.cancel() }
        XCTAssertTrue(listener.start())
        defer { listener.stop() }
        let key = folder.appendingPathComponent(PipeKey.fileName)
        XCTAssertEqual(try Data(contentsOf: key).count, PipeKey.length)
        let first = try XCTUnwrap(NamedPipes.name(for: path))
        XCTAssertEqual(NamedPipes.name(for: path, creating: true), first, "the key is made once")
        let handle = Win32.withWide(key.path.replacingOccurrences(of: "/", with: "\\")) {
            CreateFileW($0, DWORD(READ_CONTROL), DWORD(FILE_SHARE_READ), nil, DWORD(OPEN_EXISTING), 0, nil)
        }
        guard let handle, handle != Win32.invalidHandle else { return XCTFail("the key opens for reading its security") }
        defer { CloseHandle(handle) }
        assertOwnerOnly(try daclText(handle, type: SE_FILE_OBJECT))
    }

    func testPipeNamesFollowThePathNotItsSpelling() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("a b \(UUID().uuidString)/中文")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let base = folder.appendingPathComponent("x.sock").path
        let name = try XCTUnwrap(NamedPipes.name(for: base, creating: true))
        XCTAssertEqual(NamedPipes.name(for: base.uppercased()), name)
        XCTAssertEqual(NamedPipes.name(for: base.replacingOccurrences(of: "/", with: "\\")), name)
        XCTAssertNotEqual(NamedPipes.name(for: base + "2"), name)
        XCTAssertLessThan(name.count, 256, "a pipe name holds 256 characters")
    }

    func testTheHMACMatchesRFC4231() {
        // RFC 4231, test case 2.
        let mac = PortableHMAC.sha256(key: Array("Jefe".utf8), message: Array("what do ya want for nothing?".utf8))
        XCTAssertEqual(mac.map { String(format: "%02x", $0) }.joined(),
                       "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    /// The DACL of the object behind `handle`, in SDDL.
    private func daclText(_ handle: HANDLE, type: SE_OBJECT_TYPE) throws -> String {
        var descriptor: PSECURITY_DESCRIPTOR?
        var dacl: PACL?
        XCTAssertEqual(GetSecurityInfo(handle, type, SECURITY_INFORMATION(DACL_SECURITY_INFORMATION), nil, nil, &dacl, nil,
                                       &descriptor), DWORD(ERROR_SUCCESS))
        defer { LocalFree(descriptor) }
        var text: LPWSTR?
        XCTAssertTrue(ConvertSecurityDescriptorToStringSecurityDescriptorW(descriptor, DWORD(SDDL_REVISION_1),
                                                                         SECURITY_INFORMATION(DACL_SECURITY_INFORMATION), &text, nil))
        defer { LocalFree(text) }
        return try XCTUnwrap(text.map { Win32.string($0) })
    }

    /// The ways SDDL text names this user: its SID, and the alias SDDL writes for a well-known account instead
    /// (`LA` for the built-in Administrator, which a CI runner runs as).
    private var userNames: [String] {
        guard let sid = Win32.currentUserSID else { return [] }
        var names = [sid]
        var descriptor: PSECURITY_DESCRIPTOR?
        let made = Win32.withWide("O:" + sid) {
            ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil)
        }
        if made, let descriptor {
            defer { LocalFree(descriptor) }
            var text: LPWSTR?
            if ConvertSecurityDescriptorToStringSecurityDescriptorW(descriptor, DWORD(SDDL_REVISION_1),
                                                                    SECURITY_INFORMATION(OWNER_SECURITY_INFORMATION), &text, nil),
               let text {
                defer { LocalFree(text) }
                names.append(String(Win32.string(text).dropFirst(2)))
            }
        }
        return names
    }

    /// A protected DACL with one entry, for this user.
    private func assertOwnerOnly(_ sddl: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(sddl.hasPrefix("D:P"), "the DACL is protected from inheritance: \(sddl)", file: file, line: line)
        XCTAssertEqual(sddl.components(separatedBy: "(").count - 1, 1, "one entry: \(sddl)", file: file, line: line)
        XCTAssertTrue(userNames.contains { sddl.hasSuffix(";;;\($0))") }, "\(sddl) names \(userNames)", file: file, line: line)
    }
}
#endif
