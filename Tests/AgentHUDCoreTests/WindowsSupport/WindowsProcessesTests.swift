#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// What the Windows build reads about this user's processes, and the two fixed inspection tools it answers itself
/// (Platform/Windows/WindowsProcesses.swift, DECISIONS.md D-012).
final class WindowsProcessesTests: XCTestCase {
    func testThisProcessIsListedWithItsCommandLine() throws {
        let me = GetCurrentProcessId()
        let line = try XCTUnwrap(WindowsProcesses.listing().split(separator: "\n").first { $0.hasPrefix("\(me) ") })
        XCTAssertFalse(line.contains("\\"), "backslashes are written as forward slashes")
        let image = try XCTUnwrap(WindowsProcesses.imagePath(me))
        XCTAssertFalse(image.contains("\\"), "the image is written with forward slashes, as Foundation writes paths")
        // The system follows junctions and links in the image's name; the build folder may be reached through one.
        let mine = try XCTUnwrap(Bundle.main.executableURL)
        let final = try XCTUnwrap(WindowsPaths.finalPath(image), "the image exists")
        XCTAssertEqual(final.lowercased(), WindowsPaths.finalPath(mine.path)?.lowercased())
        XCTAssertTrue(WindowsProcesses.isCurrentUser(me))
        XCTAssertNotNil(WindowsProcesses.commandLine(me))
    }

    func testAnotherUsersProcessIsNeitherOpenedNorListed() {
        // The System process (pid 4) runs as SYSTEM.
        XCTAssertFalse(WindowsProcesses.isCurrentUser(4))
        XCTAssertFalse(WindowsProcesses.listing().split(separator: "\n").contains { $0.hasPrefix("4 ") })
    }

    func testTheSnapshotKnowsEachProcesssParent() {
        let entries = WindowsProcesses.snapshot()
        let me = entries.first { $0.pid == GetCurrentProcessId() }
        XCTAssertNotNil(me)
        XCTAssertTrue(entries.contains { $0.pid == me?.parent }, "the test runner was started by a process that still runs")
    }

    func testPsIsAnsweredInItsOwnFormat() async throws {
        let output = try await ProviderCommand.run("/bin/ps", ["-U", String(getuid()), "-o", "pid=,command="])
        XCTAssertTrue(output.split(separator: "\n").contains { $0.hasPrefix("\(GetCurrentProcessId()) ") })
        do {
            _ = try await ProviderCommand.run("/bin/ps", ["-ax"])
            XCTFail("only the listing the readers ask for is answered")
        } catch {}
    }

    func testLsofNamesTheTCPPortsAProcessListensOn() async throws {
        var data = WSADATA()
        XCTAssertEqual(WSAStartup(0x0202, &data), 0)
        defer { WSACleanup() }
        let listener = socket(AF_INET, SOCK_STREAM, Int32(IPPROTO_TCP.rawValue))
        XCTAssertNotEqual(listener, INVALID_SOCKET)
        defer { closesocket(listener) }
        var address = sockaddr_in()
        address.sin_family = ADDRESS_FAMILY(AF_INET)
        address.sin_addr.S_un.S_addr = UInt32(0x0100007F) // 127.0.0.1, network order
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, Int32(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(WinSDK.listen(listener, 1), 0)
        var size = Int32(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &size) }
        }
        let port = Int(UInt16(bigEndian: address.sin_port))
        let output = try await ProviderCommand.run("/usr/sbin/lsof", ["-nP", "-a", "-p", String(GetCurrentProcessId()),
                                                                      "-iTCP", "-sTCP:LISTEN", "-Fn"])
        XCTAssertTrue(output.contains("n127.0.0.1:\(port)\n"), output)
        XCTAssertEqual(AntigravityService.ports(output), AntigravityService.ports(output).filter { $0 > 0 })
        XCTAssertTrue(AntigravityService.ports(output).contains(port), "the shared reader takes the port from the emulated output")
        let other = try await ProviderCommand.run("/usr/sbin/lsof", ["-nP", "-a", "-p", "4", "-iTCP", "-sTCP:LISTEN", "-Fn"])
        XCTAssertEqual(other, "", "another user's process is not described")
    }

    func testGetuidIsNoUsersSoOwnershipChecksFailClosed() {
        // The C runtime reports every file as owned by 0, so a check that a file is this user's refuses on Windows.
        XCTAssertEqual(getuid(), uid_t.max)
        XCTAssertNotEqual(getuid(), 0)
    }
}
#endif
