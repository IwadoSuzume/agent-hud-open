#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// One Agent HUD at a time on Windows (Platform/Windows/InstanceLock+Windows.swift), with the rules InstanceLockTests
/// holds the macOS lock to.
final class InstanceLockWindowsTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud 锁 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private let running = URL(fileURLWithPath: #"C:\Program Files\Agent HUD Open\agenthud-engine.exe"#)

    func testASecondClaimIsRefusedAndNamesTheCopyThatRuns() throws {
        let url = try directory().appendingPathComponent("app.agenthud/instance.lock")
        guard case .acquired(let first) = InstanceLock.claim(at: url, executable: running) else {
            return XCTFail("the first copy runs")
        }
        withExtendedLifetime(first) {
            guard case .held(let holder) = InstanceLock.claim(at: url, executable: URL(fileURLWithPath: #"C:\Temp\other.exe"#)) else {
                return XCTFail("a second copy must not run beside the first, even in the same process")
            }
            XCTAssertEqual(holder?.path, running.path, "the refused launch names the copy that runs")
        }
        XCTAssertEqual(InstanceLock.holder(at: url)?.path, running.path, "a refused claim writes nothing")
    }

    func testTheLockGoesWithTheCopyThatHeldIt() throws {
        let url = try directory().appendingPathComponent("instance.lock")
        var first: InstanceLock.Claim? = InstanceLock.claim(at: url, executable: running)
        guard case .acquired = first else { return XCTFail("the first copy runs") }
        guard case .held = InstanceLock.claim(at: url) else { return XCTFail("the lock is held") }
        first = nil
        let next = URL(fileURLWithPath: #"D:\Tools\Agent HUD\agenthud-engine.exe"#)
        guard case .acquired(let second) = InstanceLock.claim(at: url, executable: next) else {
            return XCTFail("a copy that quit leaves the lock free")
        }
        withExtendedLifetime(second) {
            XCTAssertEqual(InstanceLock.holder(at: url)?.path, next.path, "the new holder replaces the old name")
        }
    }

    func testOnlyARunningHolderCountsAsRunning() throws {
        let url = try directory().appendingPathComponent("instance.lock")
        XCTAssertNil(InstanceLock.runningApplication(at: url), "no lock file, no application")
        let me = try XCTUnwrap(Bundle.main.executableURL)
        do {
            // The claim lasts as long as the value, here this block.
            guard case .acquired(let lock) = InstanceLock.claim(at: url, executable: me) else { return XCTFail("claims") }
            withExtendedLifetime(lock) {
                XCTAssertEqual(InstanceLock.runningApplication(at: url)?.path.lowercased(), me.path.lowercased(),
                               "the holder runs that executable")
                guard case .held = InstanceLock.claim(at: url) else { return XCTFail("asking took the lock from nobody") }
            }
        }
        // A record left by a process that is gone, or naming an executable its process does not run, is no copy.
        try "C:/Program Files/Agent HUD Open/agenthud-engine.exe\n\(GetCurrentProcessId())".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(InstanceLock.runningApplication(at: url), "this process does not run that executable")
        try "\(me.path)\n4294967294".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(InstanceLock.runningApplication(at: url), "no process has that id")
    }

    func testAReadingProcessNeverTurnsAStartingCopyAway() throws {
        let url = try directory().appendingPathComponent("instance.lock")
        try "\(running.path)\n1".write(to: url, atomically: true, encoding: .utf8)
        // Opened as the readers open it: sharing reading, writing and deletion.
        let reader = Win32.withWide(url.path.replacingOccurrences(of: "/", with: "\\")) {
            CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE) | DWORD(FILE_SHARE_DELETE),
                        nil, DWORD(OPEN_EXISTING), 0, nil)
        }
        defer { if let reader { CloseHandle(reader) } }
        guard case .acquired = InstanceLock.claim(at: url, executable: running) else {
            return XCTFail("a copy starting while another process reads the lock still claims it")
        }
    }

    func testTheSharedLockLivesUnderLocalAppData() {
        let local = WindowsFolders.localAppData.path.lowercased()
        XCTAssertTrue(InstanceLock.sharedURL.path.lowercased().hasPrefix(local))
        XCTAssertTrue(InstanceLock.sharedURL.path.hasSuffix("app.agenthud/instance.lock"))
        XCTAssertTrue(AppSupport.directory.path.hasSuffix("/Agent HUD Open"))
        XCTAssertTrue(AppSupport.directory.path.lowercased().hasPrefix(WindowsFolders.roamingAppData.path.lowercased()))
    }
}
#endif
