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
    func testClientsWithoutAWindowsSourceAreNeverRead() async throws {
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
        XCTAssertFalse(PlatformSupport.supportsDesktopApps)
        XCTAssertNil(DeepSeekScriptRuntime.desktopApplication(in: [home]))
        // Not read, not watched: no session layout, so the local store has no roots.
        for source in [AdditionalSource.antigravity, .zcode, .workbuddy] {
            XCTAssertNil(source.layout, "\(source)")
            let roots = await AdditionalLocalStore(source: source).roots
            XCTAssertEqual(roots, [], "\(source)")
        }
        XCTAssertNotNil(AdditionalSource.qwen.layout)
        // Given no hook: the permission hooks' own presence check says absent, whatever folders are there.
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".zcode/cli"), withIntermediateDirectories: true)
        for source in [PermissionHooks.Source.antigravity, .zcode, .workbuddy] {
            XCTAssertFalse(source.isInstalled(home: home), "\(source)")
        }
        XCTAssertTrue(PermissionHooks.Source.qwen.isInstalled(home: home))
        // No credential is taken from WorkBuddy's model list.
        let models = #"[{"vendor":"GLM Coding Plan","apiKey":"fixture-key","url":"https://open.bigmodel.cn/api/coding/paas/v4"}]"#
        try Data(models.utf8).write(to: home.appendingPathComponent(".workbuddy/models.json"))
        XCTAssertFalse(OpenAgentCredentials.discover(home: home, environment: [:]).contains { $0.token == "fixture-key" })
    }

    /// The desktop apps no source places on Windows (Claude's, Codex's, Grok Bot) are never looked for there, though
    /// their macOS folders sit in the home folder with programs in them.
    func testTheMacDesktopAppsLocationsAreNeverUsed() throws {
        let home = try directory()
        let claudeDesktop = home.appendingPathComponent("Library/Application Support/Claude/claude-code/2.1.295/1a2b3c/claude.app/Contents/MacOS/claude.exe")
        let claudeLocal = home.appendingPathComponent(".claude/local/claude.exe")
        let codexApp = home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex-cli/bin/codex.exe")
        for program in [claudeDesktop, claudeLocal, codexApp] { try TestEngine.write([], to: program) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Application Support/Grok Bot"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions"), withIntermediateDirectories: true)

        XCTAssertNil(ClaudeEngineLocator.find(home: home, path: ""))
        XCTAssertFalse(ClaudeEngineLocator.candidates(home: home, path: "").contains { $0.path.contains("Library") || $0.path.contains(".claude/local") || !WindowsFolders.isAbsolute($0.path) },
                       "only the native installer's places and PATH")
        XCTAssertNil(CodexLocator.find(home: home, applications: home.appendingPathComponent("Applications"), path: "", registered: []))
        XCTAssertFalse(CodexLocator.candidates(home: home, applications: home.appendingPathComponent("Applications"), path: "", registered: []).contains { $0.path.contains(".app") })
        XCTAssertFalse(GrokBotLocator.isInstalled(home: home))
        XCTAssertFalse(GrokLocalSessions.roots(home: home, environment: [:]).contains { $0.path.contains("Grok Bot") })
        let watched = ClaudeCodeProvider.standard(ledger: .inMemory(), persistent: false).watchedDirectories ?? []
        XCTAssertFalse(watched.contains { $0.path.contains("Library/Application Support/Claude") }, "the desktop app's Code sessions are not watched")
    }

    func testCursorIsReadFromItsRoamingFolder() {
        XCTAssertTrue(same(CursorClient.defaultDatabase,
                           WindowsFolders.roamingAppData.appendingPathComponent("Cursor/User/globalStorage/state.vscdb")))
    }
}
#endif
