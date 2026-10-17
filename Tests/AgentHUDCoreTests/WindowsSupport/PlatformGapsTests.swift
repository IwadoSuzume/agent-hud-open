#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// The small Windows stand-ins Core uses in place of POSIX and macOS calls, each tried directly
/// (Platform/Windows/PosixCompat.swift, WindowsProcesses.swift, ProviderHTTP+Windows.swift, PipeKey.swift).
final class PlatformGapsTests: XCTestCase {
    func testMemmemFindsTheFirstOccurrence() {
        let haystack = Array("abcabcd".utf8), needle = Array("bcd".utf8)
        haystack.withUnsafeBytes { hay in
            needle.withUnsafeBytes { pin in
                let hit = memmem(hay.baseAddress, hay.count, pin.baseAddress, pin.count)
                XCTAssertEqual(hit.map { UnsafeRawPointer($0) - hay.baseAddress! }, 4)
                XCTAssertEqual(memmem(hay.baseAddress, hay.count, pin.baseAddress, 0).map { UnsafeRawPointer($0) - hay.baseAddress! }, 0,
                               "an empty needle is found at the start")
                XCTAssertNil(memmem(hay.baseAddress, 2, pin.baseAddress, pin.count), "a haystack shorter than the needle")
            }
            let missing = Array("xyz".utf8)
            missing.withUnsafeBytes { XCTAssertNil(memmem(hay.baseAddress, hay.count, $0.baseAddress, $0.count)) }
        }
    }

    func testStrcasestrMatchesASCIILettersWhateverTheirCase() {
        "Agent HUD Open".withCString { text in
            XCTAssertEqual(strcasestr(text, "hud").map { $0 - text }, 6)
            XCTAssertEqual(strcasestr(text, "").map { $0 - text }, 0)
            XCTAssertNil(strcasestr(text, "huds"))
            XCTAssertNil(strcasestr(text, "Opened"))
        }
        "Ä".withCString { XCTAssertNil(strcasestr($0, "ä"), "only ASCII letters are folded, as in the C locale") }
    }

    func testWalkingUpStopsAtRootsAndRelativePaths() {
        for root in ["C:/", #"C:\"#, "c:", #"\\server\share"#, "//server/share/", "C:/Users/..", "relative/path", "", "/usr/bin"] {
            XCTAssertTrue(WindowsPaths.isRootOrRelative(root), root)
        }
        for path in ["C:/Users", #"D:\Projects\app"#, #"\\server\share\folder"#, "C:/a/../b"] {
            XCTAssertFalse(WindowsPaths.isRootOrRelative(path), path)
        }
    }

    /// Junctions are followed in LogFilesWindowsTests; here, the spelling and a path that names nothing.
    func testTheFinalPathIsWrittenAsURLPathIsAndIsNilForNothing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud 终 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let resolved = try XCTUnwrap(WindowsPaths.finalPath(folder.path.replacingOccurrences(of: "/", with: "\\").uppercased()))
        XCTAssertFalse(resolved.hasPrefix("//?/"))
        XCTAssertFalse(resolved.contains("\\"), "written with forward slashes, as URL.path is")
        XCTAssertTrue(resolved.hasSuffix("/" + folder.lastPathComponent), "the folder's own spelling, not the one asked for")
        XCTAssertNil(WindowsPaths.finalPath(folder.appendingPathComponent("missing").path))
    }

    /// D-012: only the two inspection tools the providers run are answered; no other program is started for them.
    func testOnlyPsAndLsofAreAnswered() async {
        for (tool, arguments) in [("/usr/bin/git", ["status"]), ("/bin/sh", ["-c", "true"]), ("cmd.exe", ["/c", "ver"]),
                                  ("/bin/ps", ["-ax"]), ("/usr/sbin/lsof", ["-i"])] {
            do {
                _ = try await ProviderCommand.run(tool, arguments)
                XCTFail("\(tool) \(arguments) is answered")
            } catch {}
        }
    }

    /// What refuses a header that would add lines of its own. swift-corelibs already drops such a value from a
    /// `URLRequest`; the request code refuses one anyway, whatever builds the request (nothing is sent here).
    func testAHeaderWithALineBreakIsRecognised() {
        XCTAssertTrue(WindowsHTTP.breaksLine("token\r\nX-Injected: 1"))
        XCTAssertTrue(WindowsHTTP.breaksLine("a\nb"))
        XCTAssertTrue(WindowsHTTP.breaksLine("a\rb"))
        XCTAssertFalse(WindowsHTTP.breaksLine("Bearer abc.def"))
        XCTAssertFalse(WindowsHTTP.breaksLine(""))
    }

    /// A `pipe.key` this user did not make owner-only (planted, or copied with its folder's permissions) is no secret:
    /// it is refused, and no pipe name comes of it.
    func testAKeyOthersCanReadIsRefused() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud-pipekey-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Written the ordinary way, the file inherits the temporary folder's entries (SYSTEM, Administrators).
        try Data(repeating: 7, count: PipeKey.length).write(to: folder.appendingPathComponent(PipeKey.fileName))
        XCTAssertNil(PipeKey.read(in: folder, creating: false))
        XCTAssertNil(PipeKey.read(in: folder, creating: true), "nor is it replaced by one of this process's own")
        XCTAssertNil(NamedPipes.name(for: folder.appendingPathComponent("x.sock").path, creating: true))
    }
}
#endif
