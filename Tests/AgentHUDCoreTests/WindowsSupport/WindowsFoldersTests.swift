#if os(Windows)
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// The folders the Windows build reads and writes (Platform/Windows/WindowsFolders.swift, SettingsFile.swift;
/// DECISIONS.md D-008, D-018, D-020).
final class WindowsFoldersTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agenthud 文件夹 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Runs `body` with the environment variable `name` set to `value`, restoring it afterwards.
    private func with(_ name: String, _ value: String?, _ body: () throws -> Void) rethrows {
        func set(_ value: String?) {
            Win32.withWide(name) { key in
                if let value { _ = Win32.withWide(value) { SetEnvironmentVariableW(key, $0) } } else { SetEnvironmentVariableW(key, nil) }
            }
        }
        let saved = ProcessInfo.processInfo.environment[name]
        set(value)
        defer { set(saved) }
        try body()
    }

    func testTheHomeIsUserProfileWhenItNamesAnExistingFolder() throws {
        let home = try directory()
        with("USERPROFILE", home.path) {
            XCTAssertEqual(UserHome.directory.standardizedFileURL.path.lowercased(), home.standardizedFileURL.path.lowercased())
        }
        for bad in ["", "relative\\home", "C:\\does not exist \(UUID().uuidString)"] {
            with("USERPROFILE", bad) {
                XCTAssertNotEqual(UserHome.directory.path, URL(fileURLWithPath: bad).path, "\(bad) is not a home")
                XCTAssertTrue(WindowsFolders.isAbsolute(UserHome.directory.path))
            }
        }
    }

    func testDataFoldersFollowTheirVariablesOnlyWhenAbsoluteAndExisting() throws {
        let roaming = try directory(), local = try directory()
        with("APPDATA", roaming.path) {
            with("LOCALAPPDATA", local.path) {
                XCTAssertTrue(AppSupport.directory.path.lowercased().hasPrefix(roaming.path.lowercased()))
                XCTAssertTrue(InstanceLock.sharedURL.path.lowercased().hasPrefix(local.path.lowercased()))
            }
        }
        with("APPDATA", "Roaming") {
            XCTAssertTrue(WindowsFolders.isAbsolute(WindowsFolders.roamingAppData.path), "a relative value is not used")
        }
    }

    func testAbsolutePathsAreDriveOrUNCPaths() {
        for path in [#"C:\Users\x"#, "d:/data", #"\\server\share\x"#, "//server/share"] {
            XCTAssertTrue(WindowsFolders.isAbsolute(path), path)
        }
        for path in ["", "C:", "C:relative", "/opt/homebrew/bin/node", #"\Windows"#, "relative", "1:/x"] {
            XCTAssertFalse(WindowsFolders.isAbsolute(path), path)
        }
    }

    func testSettingsAreKeptInTheirFileAndNothingElse() throws {
        let folder = try directory()
        let url = folder.appendingPathComponent("settings.json")
        let localBefore = Set((try? FileManager.default.contentsOfDirectory(atPath: WindowsFolders.localAppData.path)) ?? [])
        do {
            let settings = try XCTUnwrap(SettingsFile(url: url))
            settings.set(Data("{\"a\":1}".utf8), forKey: "settings.v1")
            settings.set(true, forKey: "onboarding")
            settings.set(Data("x".utf8) as Any?, forKey: "other")
            settings.removeObject(forKey: "other")
            settings.set(42, forKey: "unsupported")
            XCTAssertEqual(settings.data(forKey: "settings.v1"), Data("{\"a\":1}".utf8))
            XCTAssertTrue(settings.bool(forKey: "onboarding"))
            XCTAssertNil(settings.object(forKey: "other"))
            XCTAssertNil(settings.object(forKey: "unsupported"), "a value of another type is not stored")
        }
        let reopened = try XCTUnwrap(SettingsFile(url: url))
        XCTAssertEqual(reopened.data(forKey: "settings.v1"), Data("{\"a\":1}".utf8), "the values survive a restart")
        XCTAssertTrue(reopened.bool(forKey: "onboarding"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["settings.json"],
                       "the atomic write leaves no temporary file")
        let localAfter = Set((try? FileManager.default.contentsOfDirectory(atPath: WindowsFolders.localAppData.path)) ?? [])
        XCTAssertFalse(localAfter.subtracting(localBefore).contains { $0.hasSuffix(".plist") }, "nothing fell through to a plist")
    }

    @MainActor
    func testTheStoresKeepTheirSettingsInTheFile() throws {
        let url = try directory().appendingPathComponent("settings.json")
        do {
            let store = SettingsStore(defaults: try XCTUnwrap(SettingsFile(url: url)))
            store.update { $0.clientHooks = false }
        }
        let again = SettingsStore(defaults: try XCTUnwrap(SettingsFile(url: url)))
        XCTAssertFalse(again.settings.clientHooks)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"version\" : 1"), text)
    }

    func testAnUnreadableFileStartsEmptyAndIsReplaced() throws {
        let url = try directory().appendingPathComponent("settings.json")
        try Data("not json".utf8).write(to: url)
        let settings = try XCTUnwrap(SettingsFile(url: url))
        XCTAssertNil(settings.data(forKey: "settings.v1"))
        settings.set(true, forKey: "onboarding")
        XCTAssertTrue(try XCTUnwrap(SettingsFile(url: url)).bool(forKey: "onboarding"))
    }
}
#endif
