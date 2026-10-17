#if os(Windows)
import Foundation
import XCTest
@testable import AgentHUDCore

/// Where the Windows build reads the clients whose files are not in the home folder there
/// (docs/windows-port/SUPPORT_MATRIX.md, Sources).
final class ProviderPathsWindowsTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud 路径 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func same(_ url: URL, _ other: URL) -> Bool {
        url.standardizedFileURL.path.lowercased() == other.standardizedFileURL.path.lowercased()
    }

    /// gh's `hosts.yml`: `GH_CONFIG_DIR`, else `XDG_CONFIG_HOME\gh`, else `%AppData%\GitHub CLI`.
    func testGitHubCLISignInIsReadFromItsWindowsFolder() throws {
        let roaming = try directory(), moved = try directory()
        let home = try directory()
        var credentials = CopilotCredentials(environment: ["APPDATA": roaming.path], home: home)
        XCTAssertTrue(same(credentials.hostsFile, roaming.appendingPathComponent("GitHub CLI/hosts.yml")), credentials.hostsFile.path)
        credentials.environment["XDG_CONFIG_HOME"] = moved.path
        XCTAssertTrue(same(credentials.hostsFile, moved.appendingPathComponent("gh/hosts.yml")))
        credentials.environment["GH_CONFIG_DIR"] = moved.appendingPathComponent("gh-config").path
        XCTAssertTrue(same(credentials.hostsFile, moved.appendingPathComponent("gh-config/hosts.yml")))
        // An APPDATA that names no folder is not used: the profile's roaming folder is.
        let unset = CopilotCredentials(environment: ["APPDATA": "relative"], home: home)
        XCTAssertTrue(same(unset.hostsFile, WindowsFolders.roamingAppData.appendingPathComponent("GitHub CLI/hosts.yml")))
    }

    /// A client no source places on Windows is absent there, whatever its macOS folders hold; the others are read.
    func testClientsWithoutAWindowsSourceAreNeverRead() throws {
        let home = try directory()
        for path in [".gemini/antigravity", ".zcode/cli/db/db.sqlite", ".workbuddy/projects", ".qwen/projects", ".grok"] {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        for source in [AdditionalSource.antigravity, .zcode, .workbuddy] {
            XCTAssertFalse(PlatformSupport.supports(source))
            XCTAssertFalse(source.isInstalled(home: home), "\(source)")
        }
        for source in [AdditionalSource.qwen, .grok] {
            XCTAssertTrue(PlatformSupport.supports(source))
            XCTAssertTrue(source.isInstalled(home: home), "\(source)")
        }
        XCTAssertFalse(PlatformSupport.supportsDeepSeekDesktop)
        XCTAssertNil(DeepSeekScriptRuntime.desktopApplication(in: [home]))
    }

    func testCursorIsReadFromItsRoamingFolder() {
        XCTAssertTrue(same(CursorClient.defaultDatabase,
                           WindowsFolders.roamingAppData.appendingPathComponent("Cursor/User/globalStorage/state.vscdb")))
    }
}
#endif
