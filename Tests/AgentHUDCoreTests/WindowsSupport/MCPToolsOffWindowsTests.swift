#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// The Windows counterparts of `MCPToolsOffTests`' two lock cases (SKIPPED_TESTS.md): the holder the `--mcp` process
/// reads is the record `<executable>\n<pid>` (D-009), which counts only while that process runs that executable, so the
/// fake application here is this test process itself. Windows has no bundles: every holder keeps its data in
/// `Agent HUD Open`.
final class MCPToolsOffWindowsTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("off 关闭-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private let request = MCPToolRequest(tool: MCPTools.getPanel)

    /// This process's own executable, which the lock's record must name for its holder to count as running.
    private func me() throws -> URL {
        try XCTUnwrap(Bundle.main.executableURL)
    }

    func testAnUnservedPipeIsOffWhileTheApplicationHoldsTheLockAndNotRunningOtherwise() throws {
        let directory = try directory()
        let socket = MCPAppChannel.socketPath(in: directory)
        let lock = directory.appendingPathComponent("instance.lock")
        func answer(_ name: String = "Agent HUD Open") -> MCPAppClient.Answer {
            MCPAppClient.call(request, socket: socket, lock: lock, dataDirectoryName: name, timeout: 1)
        }
        XCTAssertEqual(answer(), .notRunning, "no lock and no pipe")
        XCTAssertNil(InstanceLock.runningApplication(at: lock))

        let me = try me()
        var running: InstanceLock.Claim? = InstanceLock.claim(at: lock, executable: me)
        guard case .acquired = running else { return XCTFail("the fake application holds the lock") }
        XCTAssertEqual(InstanceLock.runningApplication(at: lock)?.path.lowercased(), me.path.lowercased())
        XCTAssertEqual(answer(), .off, "the application runs and serves no pipe")
        XCTAssertEqual(answer("Agent HUD"), .notRunning, "a copy of another application, with its own data directory, does not count")
        guard case .held = InstanceLock.claim(at: lock) else {
            return XCTFail("asking never took or freed the lock: a second copy is still turned away")
        }

        // The copy quits: its handle goes, and its record stays with the id of a process that is gone (this process
        // runs on, so the id it wrote would still count; InstanceLockWindowsTests holds the record to that rule).
        running = nil
        try "\(me.path)\n4294967294".write(to: lock, atomically: true, encoding: .utf8)
        XCTAssertNotNil(InstanceLock.holder(at: lock), "the name of the copy that quit stays in the file")
        XCTAssertNil(InstanceLock.runningApplication(at: lock), "but no process of it runs")
        XCTAssertEqual(answer(), .notRunning)
        guard case .acquired = InstanceLock.claim(at: lock) else {
            return XCTFail("asking holds nothing: a copy that starts next is not turned away")
        }
    }

    /// The counterpart of `testABundledHolderCountsByTheDataDirectoryItsBundleNames`: a holder that is a program, not a
    /// bundle, keeps its data in `Agent HUD Open`, and one whose record names another program does not count at all.
    func testAProgramHolderCountsForTheOpenDataDirectoryOnly() throws {
        let directory = try directory()
        let lock = directory.appendingPathComponent("instance.lock")
        let running = InstanceLock.claim(at: lock, executable: try me())
        guard case .acquired = running else { return XCTFail("the fake application holds the lock") }
        withExtendedLifetime(running) {
            XCTAssertTrue(MCPAppClient.applicationRuns(lock: lock, dataDirectoryName: "Agent HUD Open"))
            XCTAssertFalse(MCPAppClient.applicationRuns(lock: lock, dataDirectoryName: "Agent HUD"))
        }

        let other = directory.appendingPathComponent("other")
        let elsewhere = InstanceLock.claim(at: other.appendingPathComponent("instance.lock"),
                                           executable: URL(fileURLWithPath: #"C:\Program Files\Agent HUD Open\AgentHUD.exe"#))
        guard case .acquired = elsewhere else { return XCTFail("the second fake application holds its lock") }
        withExtendedLifetime(elsewhere) {
            XCTAssertFalse(MCPAppClient.applicationRuns(lock: other.appendingPathComponent("instance.lock"), dataDirectoryName: "Agent HUD Open"),
                           "this process's id with another program's name: not that program running")
        }
    }
}
#endif
