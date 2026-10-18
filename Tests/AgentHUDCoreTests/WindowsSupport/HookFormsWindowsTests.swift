#if os(Windows)
import AgentHUDSupport
import Foundation
import WinSDK
import XCTest
@testable import AgentHUDCore

/// The handlers Agent HUD writes on Windows, in each client's form (DECISIONS.md D-037), the files they are written to
/// keeping their security (D-023), and each form run through the shell its client uses.
final class HookFormsWindowsTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("HUD Hooks 回调 \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// An engine path with a space, CJK, an apostrophe and an ampersand: everything a quoting mistake trips over.
    private var engine: URL { home.appendingPathComponent("Agent HUD 引擎 O'Neil & Co/agenthud-engine.exe") }

    private func json(_ url: URL) throws -> ProviderJSON { try ProviderJSON.read(Data(contentsOf: url)) }

    private func handlers(_ object: ProviderJSON, event: String) -> [ProviderJSON] {
        (object["hooks"][event].arrayValue ?? []).flatMap { $0["hooks"].arrayValue ?? [] }
    }

    private var nativeEngine: String { engine.path.replacingOccurrences(of: "/", with: "\\") }

    func testTheCommandLineQuotesTheEngineForTheCommandProcessor() {
        XCTAssertEqual(HookCommand.make(executable: engine, arguments: "--permission-hook codex"),
                       "\"\(nativeEngine)\" --permission-hook codex")
        XCTAssertTrue(HookCommand.runs("\"\(nativeEngine)\" --permission-hook codex", arguments: "--permission-hook codex"))
    }

    func testClaudeCodeIsGivenTheExecFormAndKeepsEverythingElse() throws {
        let settings = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mine: ProviderJSON = .object(["matcher": .string("Bash"),
                                          "hooks": .array([.object(["type": .string("command"), "command": .string("node lint.js")])])])
        try JSONEncoder().encode(ProviderJSON.object(["model": .string("opus"),
                                                      "hooks": .object(["PermissionRequest": .array([mine])])])).write(to: settings)

        try PermissionHooks.configure(.claude, enabled: true, executable: engine, home: home)
        var object = try json(settings)
        XCTAssertEqual(object["model"].stringValue, "opus")
        let written = handlers(object, event: "PermissionRequest")
        XCTAssertEqual(written.count, 2)
        XCTAssertEqual(written.first?["command"].stringValue, "node lint.js", "the user's handler is kept as it was")
        let handler = try XCTUnwrap(written.last)
        XCTAssertEqual(handler["command"].stringValue, nativeEngine, "the program alone, no shell quoting")
        XCTAssertEqual(handler["args"].arrayValue?.compactMap(\.stringValue), ["--permission-hook", "claude"])
        XCTAssertNil(handler["shell"].stringValue)
        XCTAssertTrue(PermissionHooks.isActive(.claude, home: home))

        // The same again rewrites nothing; another copy of Agent HUD takes the handler over in place.
        let before = try Data(contentsOf: settings)
        try PermissionHooks.configure(.claude, enabled: true, executable: engine, home: home)
        XCTAssertEqual(try Data(contentsOf: settings), before)
        let moved = home.appendingPathComponent("Moved/agenthud-engine.exe")
        try PermissionHooks.configure(.claude, enabled: true, executable: moved, home: home)
        object = try json(settings)
        XCTAssertEqual(handlers(object, event: "PermissionRequest").compactMap { $0["command"].stringValue },
                       ["node lint.js", moved.path.replacingOccurrences(of: "/", with: "\\")])

        try PermissionHooks.configure(.claude, enabled: false, executable: moved, home: home)
        object = try json(settings)
        XCTAssertEqual(handlers(object, event: "PermissionRequest").compactMap { $0["command"].stringValue }, ["node lint.js"])
        XCTAssertFalse(PermissionHooks.isActive(.claude, home: home))
    }

    func testCopilotCLIIsGivenItsExecField() throws {
        try CompletionHooks.configure(.copilot, enabled: true, executable: engine, home: home)
        let file = home.appendingPathComponent(".copilot/hooks/agent-hud.json")
        let handler = try XCTUnwrap(try json(file)["hooks"]["agentStop"].arrayValue?.first)
        XCTAssertEqual(handler["exec"].stringValue, nativeEngine)
        XCTAssertEqual(handler["args"].arrayValue?.compactMap(\.stringValue), ["--completion-hook", "copilot"])
        XCTAssertNil(handler["bash"].stringValue, "Copilot CLI forbids exec beside bash, powershell or command")
        XCTAssertNil(handler["command"].stringValue)
        XCTAssertTrue(CompletionHooks.isInstalled(.copilot, home: home))
        let before = try Data(contentsOf: file)
        try CompletionHooks.configure(.copilot, enabled: true, executable: engine, home: home)
        XCTAssertEqual(try Data(contentsOf: file), before)
        try CompletionHooks.configure(.copilot, enabled: false, executable: engine, home: home)
        XCTAssertFalse(CompletionHooks.isInstalled(.copilot, home: home))
    }

    func testCodexIsGivenACommandProcessorLine() throws {
        try PermissionHooks.configure(.codex, enabled: true, executable: engine, home: home)
        let file = PermissionHooks.Source.codex.configuration(home: home)
        let handler = try XCTUnwrap(handlers(try json(file), event: PermissionHooks.Source.codex.event).first)
        XCTAssertEqual(handler["command"].stringValue, "\"\(nativeEngine)\" --permission-hook codex")
        XCTAssertNil(handler["args"].arrayValue)
        XCTAssertTrue(PermissionHooks.isActive(.codex, home: home))
    }

    func testCodeBuddyIsGivenGitBashQuoting() throws {
        try CompletionHooks.configure(.codebuddy, enabled: true, executable: engine, home: home)
        let file = CompletionHooks.Source.codebuddy.configuration(home: home)
        let handler = try XCTUnwrap(handlers(try json(file), event: "Stop").first)
        // Forward slashes in double quotes: the apostrophe and ampersand need nothing, `$` and `` ` `` would be escaped.
        XCTAssertEqual(handler["command"].stringValue, "\"" + engine.path.replacingOccurrences(of: "\\", with: "/") + "\" --completion-hook codebuddy")
        XCTAssertEqual(HookCommand.gitBashPath(#"C:\a $b `c` "d"\x.exe"#), #""C:/a \$b \`c\` \"d\"/x.exe""#)
        XCTAssertTrue(CompletionHooks.isInstalled(.codebuddy, home: home))
        let before = try Data(contentsOf: file)
        try CompletionHooks.configure(.codebuddy, enabled: true, executable: engine, home: home)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testQwenCodeIsGivenPowerShell() throws {
        try CompletionHooks.configure(.qwen, enabled: true, executable: engine, home: home)
        let file = CompletionHooks.Source.qwen.configuration(home: home)
        let handler = try XCTUnwrap(handlers(try json(file), event: "Stop").first)
        XCTAssertEqual(handler["command"].stringValue, "& '" + nativeEngine.replacingOccurrences(of: "'", with: "''") + "' --completion-hook qwen")
        XCTAssertEqual(handler["shell"].stringValue, "powershell")
        XCTAssertEqual(handler["timeout"], .integer(Int64(QwenHookFormat.timeout)))
        let before = try Data(contentsOf: file)
        try CompletionHooks.configure(.qwen, enabled: true, executable: engine, home: home)
        XCTAssertEqual(try Data(contentsOf: file), before)
        try CompletionHooks.configure(.qwen, enabled: false, executable: engine, home: home)
        XCTAssertFalse(CompletionHooks.isInstalled(.qwen, home: home))
    }

    /// CompletionHooksTests' takeover case with Windows places: whichever copy wrote a handler, in whichever form, the
    /// running one takes it over or takes it out, and a copy running from inside a zip writes nothing.
    func testTheRunningEngineTakesOverAHandlerAnotherCopyWrote() throws {
        let current = home.appendingPathComponent("Programs/Agent HUD/agenthud-engine.exe")
        let zipCopy = FileManager.default.temporaryDirectory.appendingPathComponent("Temp1_Agent HUD.zip/Agent HUD/agenthud-engine.exe")
        let others = [home.appendingPathComponent("Agent HUD Open/agenthud-engine.exe"), zipCopy,
                      home.appendingPathComponent("Deleted/agenthud-engine.exe")]
        for source in CompletionHooks.Source.allCases where HookCommand.windowsForm(arguments: CompletionHooks.arguments(source)) != nil {
            let folder = home.appendingPathComponent(source.rawValue, isDirectory: true), file = source.configuration(home: folder)
            let arguments = CompletionHooks.arguments(source)
            let written = { (engine: URL) in HookCommand.clientForms(try source.format.updating([:], command: HookCommand.make(executable: engine, arguments: arguments)), arguments: arguments) }
            for other in others {
                for enabled in [false, true] {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(ProviderJSON.object(try written(other))).write(to: file)
                    try CompletionHooks.configure(source, enabled: enabled, executable: current, home: folder)
                    let removed = try source.format.updating(try source.format.updating([:], command: HookCommand.make(executable: other, arguments: arguments)), command: nil)
                    XCTAssertEqual(try json(file).objectValue, enabled ? try written(current) : removed,
                                   "\(source): the handler \(other.path) wrote is \(enabled ? "taken over" : "removed")")
                }
            }
            let taken = try Data(contentsOf: file)
            XCTAssertThrowsError(try CompletionHooks.configure(source, enabled: true, executable: zipCopy, home: folder))
            XCTAssertEqual(try Data(contentsOf: file), taken, "\(source): a copy running from inside a zip writes nothing")
        }
    }

    /// Every client D-037 gives no Windows hook: the counterpart of the skipped Antigravity and ZCode installation tests
    /// (SKIPPED_TESTS.md).
    func testClientsWithoutAWindowsHookShellAreGivenNoHandler() throws {
        for source in [CompletionHooks.Source.cursor, .antigravity] {
            XCTAssertThrowsError(try CompletionHooks.configure(source, enabled: true, executable: engine, home: home), "\(source)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.configuration(home: home).path), "\(source)")
            XCTAssertNoThrow(try CompletionHooks.configure(source, enabled: false, executable: engine, home: home), "\(source)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.configuration(home: home).path), "\(source): removing creates nothing")
        }
        // Antigravity's approvals use no hook on any platform (`usesHook`), so it is not in this list.
        for source in [PermissionHooks.Source.qoderCN, .qoderWork, .zcode, .workbuddy] {
            XCTAssertThrowsError(try PermissionHooks.configure(source, enabled: true, executable: engine, home: home), "\(source)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.configuration(home: home).path), "\(source)")
            XCTAssertNoThrow(try PermissionHooks.configure(source, enabled: false, executable: engine, home: home), "\(source)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.configuration(home: home).path), "\(source): removing creates nothing")
        }
    }

    func testPathsACommandLineCannotQuoteAreRefused() {
        for name in ["100%", "Wow!", "Quote\u{2019}s"] {
            let program = home.appendingPathComponent("\(name)/agenthud-engine.exe")
            XCTAssertThrowsError(try PermissionHooks.configure(.claude, enabled: true, executable: program, home: home), name)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/settings.json").path))
    }

    func testAZipsCopyRemovableAndNetworkPlacesAreTransient() {
        let temporary = FileManager.default.temporaryDirectory
        XCTAssertTrue(HookCommand.isTransient(temporary.appendingPathComponent("Temp1_Agent HUD.zip/Agent HUD/agenthud-engine.exe").path))
        XCTAssertTrue(HookCommand.isTransient(temporary.appendingPathComponent("TEMP12_x.ZIP/agenthud-engine.exe").path))
        XCTAssertFalse(HookCommand.isTransient(temporary.appendingPathComponent("x/agenthud-engine.exe").path), "the folder as such is not")
        XCTAssertFalse(HookCommand.isTransient(temporary.appendingPathComponent("Temp_x.zip/agenthud-engine.exe").path))
        XCTAssertFalse(HookCommand.isTransient(temporary.appendingPathComponent("Tempo1_x.zip/agenthud-engine.exe").path))
        XCTAssertTrue(HookCommand.isTransient(#"\\server\share\agenthud-engine.exe"#))
        XCTAssertTrue(HookCommand.isTransient("//server/share/agenthud-engine.exe"))
        let programs = (Win32.environment("ProgramFiles") ?? #"C:\Program Files"#) + #"\Agent HUD\agenthud-engine.exe"#
        XCTAssertFalse(HookCommand.isTransient(programs))
        XCTAssertFalse(HookCommand.isTransient(WindowsFolders.localAppData.appendingPathComponent("Programs/Agent HUD/agenthud-engine.exe").path))
    }

    /// A temporary folder named in its 8.3 form still holds a zip's copy spelled in full (M5 review round 1).
    func testAZipsCopyIsTransientWhicheverWayTheTemporaryFolderIsSpelled() throws {
        // A temporary folder of its own whose name needs an 8.3 form, as `C:\Users\<long or CJK name>` does.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HUD temporary folder 临时 \(UUID().uuidString)")
        let copy = folder.appendingPathComponent("Temp7_Agent HUD for Windows long name.zip/Agent HUD/agenthud-engine.exe")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: copy)
        defer { try? FileManager.default.removeItem(at: folder) }
        let long = Win32.longPath(folder.path.replacingOccurrences(of: "/", with: "\\"))
        let length = Win32.withWide(long) { GetShortPathNameW($0, nil, 0) }
        var buffer = [WCHAR](repeating: 0, count: Int(length) + 1)
        let written = Win32.withWide(long) { GetShortPathNameW($0, &buffer, DWORD(buffer.count)) }
        let short = String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
        try XCTSkipIf(written == 0 || short.lowercased() == long.lowercased(), "the volume keeps no 8.3 names for the temporary folder")
        let saved = (Win32.environment("TEMP"), Win32.environment("TMP"))
        defer {
            _ = Win32.withWide("TEMP") { name in saved.0.map { Win32.withWide($0) { SetEnvironmentVariableW(name, $0) } } }
            _ = Win32.withWide("TMP") { name in saved.1.map { Win32.withWide($0) { SetEnvironmentVariableW(name, $0) } } }
        }
        for name in ["TEMP", "TMP"] { _ = Win32.withWide(name) { name in Win32.withWide(short) { SetEnvironmentVariableW(name, $0) } } }
        let spelledInFull = long + #"\Temp7_Agent HUD for Windows long name.zip\Agent HUD\agenthud-engine.exe"#
        XCTAssertTrue(HookCommand.isTransient(spelledInFull), "TEMP \(short), engine \(spelledInFull)")
        // The other way round: TEMP spelled in full, the engine's path in 8.3 names (zip folder included).
        for name in ["TEMP", "TMP"] { _ = Win32.withWide(name) { name in Win32.withWide(long) { SetEnvironmentVariableW(name, $0) } } }
        let copyLength = Win32.withWide(spelledInFull) { GetShortPathNameW($0, nil, 0) }
        var copyBuffer = [WCHAR](repeating: 0, count: Int(copyLength) + 1)
        _ = Win32.withWide(spelledInFull) { GetShortPathNameW($0, &copyBuffer, DWORD(copyBuffer.count)) }
        let spelledShort = String(decoding: copyBuffer.prefix { $0 != 0 }, as: UTF16.self)
        XCTAssertNotEqual(spelledShort.lowercased(), spelledInFull.lowercased())
        XCTAssertTrue(HookCommand.isTransient(spelledShort), "TEMP \(long), engine \(spelledShort)")
    }

    /// A local path with the long-path prefix is the drive it names, not a share; a prefixed share still is one.
    func testALongPathPrefixedLocalEngineIsNoShare() {
        let programs = (Win32.environment("ProgramFiles") ?? #"C:\Program Files"#) + #"\Agent HUD\agenthud-engine.exe"#
        XCTAssertFalse(HookCommand.isTransient(#"\\?\"# + programs))
        XCTAssertTrue(HookCommand.isTransient(#"\\?\UNC\server\share\agenthud-engine.exe"#))
        XCTAssertEqual(Win32.unprefixed(#"\\?\C:\Tools\a.exe"#), #"C:\Tools\a.exe"#)
        XCTAssertEqual(Win32.unprefixed(#"\\?\UNC\server\share\a.exe"#), #"\\server\share\a.exe"#)
        XCTAssertEqual(Win32.unprefixed(#"C:\Tools\a.exe"#), #"C:\Tools\a.exe"#)
    }

    /// `Win32.longPath` beyond MAX_PATH: asked in its `\\?\` form, given back without it.
    func testTheLongFormOfAPathBeyondMaxPath() throws {
        var folder = home!
        while folder.path.utf16.count < 300 { folder.appendPathComponent("深层 long folder name \(folder.pathComponents.count)") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let long = folder.path.replacingOccurrences(of: "/", with: "\\")
        let prefixed = #"\\?\"# + long
        let length = Win32.withWide(prefixed) { GetShortPathNameW($0, nil, 0) }
        var buffer = [WCHAR](repeating: 0, count: Int(length) + 1)
        let written = Win32.withWide(prefixed) { GetShortPathNameW($0, &buffer, DWORD(buffer.count)) }
        let short = Win32.unprefixed(String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self))
        try XCTSkipIf(written == 0 || short.lowercased() == long.lowercased(), "the volume keeps no 8.3 names")
        XCTAssertEqual(Win32.longPath(short).lowercased(), long.lowercased())
        XCTAssertEqual(Win32.longPath(long).lowercased(), long.lowercased())
        XCTAssertEqual(Win32.longPath(#"C:\does not exist\x"#), #"C:\does not exist\x"#, "a path that does not exist comes back as given")
    }

    // MARK: Security descriptors (D-023)

    private func dacl(_ url: URL) throws -> String {
        var descriptor: PSECURITY_DESCRIPTOR?
        let status = Win32.withWide(url.path.replacingOccurrences(of: "/", with: "\\")) {
            GetNamedSecurityInfoW($0, SE_FILE_OBJECT, SECURITY_INFORMATION(DACL_SECURITY_INFORMATION), nil, nil, nil, nil, &descriptor)
        }
        XCTAssertEqual(status, DWORD(ERROR_SUCCESS))
        defer { LocalFree(descriptor) }
        var text: LPWSTR?
        XCTAssertTrue(ConvertSecurityDescriptorToStringSecurityDescriptorW(descriptor, DWORD(SDDL_REVISION_1),
                                                                            SECURITY_INFORMATION(DACL_SECURITY_INFORMATION), &text, nil))
        defer { LocalFree(text) }
        return Win32.string(try XCTUnwrap(text))
    }

    private func setDACL(_ sddl: String, on url: URL) throws {
        var descriptor: PSECURITY_DESCRIPTOR?
        XCTAssertTrue(Win32.withWide(sddl) { ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil) })
        defer { LocalFree(descriptor) }
        var present: WindowsBool = false, defaulted: WindowsBool = false
        var list: PACL?
        XCTAssertTrue(GetSecurityDescriptorDacl(descriptor, &present, &list, &defaulted))
        let status = Win32.withWide(url.path.replacingOccurrences(of: "/", with: "\\")) {
            SetNamedSecurityInfoW(UnsafeMutablePointer(mutating: $0), SE_FILE_OBJECT,
                                  SECURITY_INFORMATION(DACL_SECURITY_INFORMATION) | SECURITY_INFORMATION(PROTECTED_DACL_SECURITY_INFORMATION),
                                  nil, nil, list, nil)
        }
        XCTAssertEqual(status, DWORD(ERROR_SUCCESS))
    }

    func testASettingsFileKeepsTheSecurityTheUserGaveIt() throws {
        let settings = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model":"opus"}"#.utf8).write(to: settings)
        let sid = try XCTUnwrap(Win32.currentUserSID)
        // Protected, so nothing is inherited from the folder: the user and Administrators only, unlike the folder's.
        try setDACL("D:P(A;;FA;;;\(sid))(A;;FR;;;BA)", on: settings)
        let before = try dacl(settings)
        XCTAssertTrue(before.hasPrefix("D:P"), before)

        try PermissionHooks.configure(.claude, enabled: true, executable: engine, home: home)
        XCTAssertEqual(try dacl(settings), before, "ReplaceFileW keeps the replaced file's DACL")
        XCTAssertEqual(try json(settings)["model"].stringValue, "opus")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: settings.deletingLastPathComponent().path).filter { $0.hasSuffix(".tmp") }
        XCTAssertEqual(leftovers, [], "the staged file is gone")
    }

    /// What is left beside a settings file: staged or backup copies of Agent HUD's.
    private func leftovers(beside file: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
            .filter { $0.contains(".agenthud-") }
    }

    /// A replace that fails, in each way `ReplaceFileW` can, never costs the user their file (M5 review round 1).
    func testAFailedReplaceLeavesTheUsersFileWhereItWas() throws {
        let file = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"model":"opus"}"#.utf8), new = Data(#"{"model":"sonnet"}"#.utf8)
        try original.write(to: file)
        let move: @Sendable (String, String) -> Bool = { from, to in
            Win32.withWide(from) { from in Win32.withWide(to) { to in MoveFileExW(from, to, 0) } }
        }
        let failures: [(String, HookSettings.Replace)] = [
            // The old file renamed to the backup, the new one not moved in: only the backup holds the user's content.
            ("ERROR_UNABLE_TO_MOVE_REPLACEMENT_2", { target, _, backup in XCTAssertTrue(move(target, backup)); return 1177 }),
            // Neither moved.
            ("ERROR_UNABLE_TO_MOVE_REPLACEMENT", { _, _, _ in 1176 }),
            ("ERROR_UNABLE_TO_REMOVE_REPLACED", { _, _, _ in 1175 }),
        ]
        for (name, replace) in failures {
            XCTAssertThrowsError(try HookSettings.replaceKeepingSecurity(new, at: file, replace: replace), name)
            XCTAssertEqual(try Data(contentsOf: file), original, "\(name): the user's file is back in place")
            XCTAssertEqual(try leftovers(beside: file), [], "\(name): nothing of Agent HUD's is left")
        }
        try HookSettings.replaceKeepingSecurity(new, at: file)
        XCTAssertEqual(try Data(contentsOf: file), new)
        XCTAssertEqual(try leftovers(beside: file), [], "the backup goes once the new file is in place")
    }

    /// When the old file cannot even be moved back (something holds the backup), nothing is deleted: the user's content
    /// stays in the backup, beside the file's name, and the error is thrown.
    func testARestoreThatFailsKeepsTheUsersCopy() throws {
        let file = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"model":"opus"}"#.utf8)
        try original.write(to: file)
        final class Held: @unchecked Sendable { var handle: HANDLE? }
        let held = Held()
        defer { if let handle = held.handle { CloseHandle(handle) } }
        XCTAssertThrowsError(try HookSettings.replaceKeepingSecurity(Data("{}".utf8), at: file) { target, _, backup in
            _ = Win32.withWide(target) { target in Win32.withWide(backup) { backup in MoveFileExW(target, backup, 0) } }
            // Open without FILE_SHARE_DELETE: the move back is refused.
            held.handle = Win32.withWide(backup) {
                CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ), nil, DWORD(OPEN_EXISTING), 0, nil)
            }
            return 1177
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "the move back was refused")
        let kept = try leftovers(beside: file).filter { $0.hasSuffix(".backup") }
        XCTAssertEqual(kept.count, 1)
        let backup = file.deletingLastPathComponent().appendingPathComponent(try XCTUnwrap(kept.first))
        XCTAssertEqual(try Data(contentsOf: backup), original, "the user's content is kept, not deleted")
        if let handle = held.handle { CloseHandle(handle); held.handle = nil }
        for name in try leftovers(beside: file) {
            try FileManager.default.removeItem(at: file.deletingLastPathComponent().appendingPathComponent(name))
        }
    }

    /// The file went away on its own between the check and the replace: no copy of the user's exists, and Agent HUD's
    /// staged one is not left behind.
    func testAFileThatVanishesMeanwhileLeavesNothingBehind() throws {
        let file = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model":"opus"}"#.utf8).write(to: file)
        XCTAssertThrowsError(try HookSettings.replaceKeepingSecurity(Data("{}".utf8), at: file) { target, _, _ in
            _ = Win32.withWide(target) { DeleteFileW($0) }
            return DWORD(ERROR_FILE_NOT_FOUND)
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try leftovers(beside: file), [])
    }

    /// A real failure: the client holds its settings file open without letting it be replaced.
    func testASettingsFileTheClientHoldsIsLeftAsItWas() throws {
        let file = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"model":"opus"}"#.utf8)
        try original.write(to: file)
        let held = Win32.withWide(file.path.replacingOccurrences(of: "/", with: "\\")) {
            CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE), nil, DWORD(OPEN_EXISTING), 0, nil)
        }
        let handle = try XCTUnwrap(held == Win32.invalidHandle ? nil : held)
        defer { CloseHandle(handle) }
        XCTAssertThrowsError(try PermissionHooks.configure(.claude, enabled: true, executable: engine, home: home))
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try leftovers(beside: file), [])
    }

    func testASettingsFileDeeperThanMaxPathIsWritten() throws {
        var folder = home!
        while folder.path.count < 300 { folder.appendPathComponent("深层文件夹 deep folder \(folder.pathComponents.count)") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("settings.json")
        try HookSettings.write(["model": .string("opus")], to: file)
        try HookSettings.write(["model": .string("sonnet")], to: file)
        XCTAssertEqual(try json(file)["model"].stringValue, "sonnet")
        XCTAssertEqual(try leftovers(beside: file), [])
    }

    /// The Windows counterpart of `ClientHooksTests.testASettingsFileKeptAsALinkIsWrittenWhereItLeadsAndKeepsItsPermissions`:
    /// a settings file kept as a symbolic link is written where the link leads, the link stays a link, and the file it
    /// leads to keeps its DACL (D-023). File links need Developer Mode or an elevated token; this machine and the
    /// GitHub runner have one of them.
    func testASettingsFileKeptAsALinkIsWrittenWhereItLeadsAndKeepsItsSecurity() throws {
        let dotfiles = home.appendingPathComponent("dotfiles 配置", isDirectory: true)
        let claude = dotfiles.appendingPathComponent("claude.json"), copilot = dotfiles.appendingPathComponent("copilot/agent-hud.json")
        try FileManager.default.createDirectory(at: copilot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"model":"opus"}"#.utf8).write(to: claude)
        try Data(#"{"version":1}"#.utf8).write(to: copilot)
        let sid = try XCTUnwrap(Win32.currentUserSID)
        try setDACL("D:P(A;;FA;;;\(sid))(A;;FR;;;BA)", on: claude)
        try setDACL("D:P(A;;FA;;;\(sid))", on: copilot)
        let protections = [try dacl(claude), try dacl(copilot)]
        // One link names its file from the folder it sits in, the other by its whole path.
        let claudeLink = home.appendingPathComponent(".claude/settings.json")
        let copilotLink = CompletionHooks.Source.copilot.configuration(home: home)
        for link in [claudeLink, copilotLink] {
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(atPath: claudeLink.path, withDestinationPath: #"..\dotfiles 配置\claude.json"#)
        try FileManager.default.createSymbolicLink(atPath: copilotLink.path, withDestinationPath: copilot.path)

        try PermissionHooks.configure(.claude, enabled: true, executable: engine, home: home)
        try AttentionHooks.configure(.claude, enabled: true, executable: engine, home: home)
        try CompletionHooks.configure(.copilot, enabled: true, executable: engine, home: home)
        for (link, file, protection) in [(claudeLink, claude, protections[0]), (copilotLink, copilot, protections[1])] {
            XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "\(link.lastPathComponent) stays a link")
            XCTAssertEqual(try dacl(file), protection, "\(file.lastPathComponent) keeps its DACL")
            let leftovers: [String] = try FileManager.default.contentsOfDirectory(atPath: link.deletingLastPathComponent().path)
                + FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
            XCTAssertEqual(leftovers.filter { $0.hasSuffix(".tmp") }, [], "no staged file is left beside \(file.lastPathComponent)")
        }
        let settings = try json(claude)
        XCTAssertEqual(settings["model"].stringValue, "opus")
        let events = settings["hooks"].objectValue?.keys.sorted() ?? []
        XCTAssertEqual(events.flatMap { handlers(settings, event: $0) }.count, 2, "the permission and the attention handler: \(events)")
        XCTAssertTrue(CompletionHooks.isInstalled(.copilot, home: home))
    }

    // MARK: Each form run as its client runs it

    /// Writes the fake engine at `engine`, recording its arguments, and returns the record's file.
    private func recordingEngine() throws -> URL {
        let record = home.appendingPathComponent("record.jsonl")
        try TestEngine.write([.record(record.path), .out("{}"), .exit(0)], to: engine)
        return record
    }

    private func recordedArguments(_ record: URL) throws -> [[String]] {
        try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map {
            let object = try ProviderJSON.read(Data($0.utf8))
            return (object["arguments"].arrayValue ?? []).compactMap(\.stringValue)
        }
    }

    /// Runs a raw command line with `CreateProcessW`, as Codex's runner and Node's `spawn` hand one to Windows, and
    /// returns its exit status.
    private func run(commandLine: String) throws -> DWORD {
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        var information = PROCESS_INFORMATION()
        var line = Array(commandLine.utf16) + [0]
        let started = CreateProcessW(nil, &line, nil, nil, false, DWORD(CREATE_NO_WINDOW), nil, nil, &startup, &information)
        XCTAssertTrue(started, "CreateProcessW failed: \(GetLastError())")
        guard started else { return DWORD.max }
        defer { CloseHandle(information.hProcess); CloseHandle(information.hThread) }
        XCTAssertEqual(WaitForSingleObject(information.hProcess, 30_000), DWORD(WAIT_OBJECT_0))
        var status: DWORD = 0
        GetExitCodeProcess(information.hProcess, &status)
        return status
    }

    /// `"…"` as the Microsoft C runtime reads one argument: backslashes before a quote doubled, quotes escaped.
    private func argument(_ text: String) -> String {
        guard text.contains(where: { $0 == " " || $0 == "\t" || $0 == "\"" }) else { return text }
        var result = "\"", slashes = 0
        for character in text {
            if character == "\\" { slashes += 1; continue }
            if character == "\"" { result += String(repeating: "\\", count: slashes * 2 + 1) + "\"" }
            else { result += String(repeating: "\\", count: slashes) + String(character) }
            slashes = 0
        }
        return result + String(repeating: "\\", count: slashes * 2) + "\""
    }

    private var system32: String { (Win32.environment("SystemRoot") ?? #"C:\Windows"#) + #"\System32"# }

    func testTheExecFormStartsTheEngineWithItsArguments() throws {
        let record = try recordingEngine()
        try PermissionHooks.configure(.claude, enabled: true, executable: engine, home: home)
        let handler = try XCTUnwrap(handlers(try json(home.appendingPathComponent(".claude/settings.json")), event: "PermissionRequest").first)
        let program = try XCTUnwrap(handler["command"].stringValue), args = handler["args"].arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertEqual(try run(commandLine: ([program] + args).map(argument).joined(separator: " ")), 0)
        XCTAssertEqual(try recordedArguments(record), [["--permission-hook", "claude"]])
    }

    func testCodexsCommandProcessorRunsTheLine() throws {
        let record = try recordingEngine()
        let line = HookCommand.make(executable: engine, arguments: "--permission-hook codex")
        // codex-rs hooks/src/engine/command_runner.rs: `%ComSpec% /C` and the line in quotes, as a raw argument.
        let comspec = Win32.environment("ComSpec") ?? system32 + #"\cmd.exe"#
        XCTAssertEqual(try run(commandLine: argument(comspec) + " /C \"" + line + "\""), 0)
        XCTAssertEqual(try recordedArguments(record), [["--permission-hook", "codex"]])
    }

    func testQwenCodesPowerShellRunsTheCommand() throws {
        let record = try recordingEngine()
        try CompletionHooks.configure(.qwen, enabled: true, executable: engine, home: home)
        let handler = try XCTUnwrap(handlers(try json(CompletionHooks.Source.qwen.configuration(home: home)), event: "Stop").first)
        let command = try XCTUnwrap(handler["command"].stringValue)
        // qwen-code hooks/hookRunner.ts: `powershell -Command <command>`, spawned without a shell.
        let powershell = system32 + #"\WindowsPowerShell\v1.0\powershell.exe"#
        try XCTSkipUnless(FileManager.default.fileExists(atPath: powershell), "no Windows PowerShell")
        XCTAssertEqual(try run(commandLine: [powershell, "-Command", command].map(argument).joined(separator: " ")), 0)
        XCTAssertEqual(try recordedArguments(record), [["--completion-hook", "qwen"]])
    }

    func testCodeBuddysGitBashRunsTheCommand() throws {
        let record = try recordingEngine()
        try CompletionHooks.configure(.codebuddy, enabled: true, executable: engine, home: home)
        let handler = try XCTUnwrap(handlers(try json(CompletionHooks.Source.codebuddy.configuration(home: home)), event: "Stop").first)
        let command = try XCTUnwrap(handler["command"].stringValue)
        // Git for Windows' Bash, found from its `git.exe` on PATH (`<Git>\cmd\git.exe` beside `<Git>\bin\bash.exe`).
        let path = ProcessInfo.processInfo.environment.first { $0.key.uppercased() == "PATH" }?.value ?? ""
        let bash = path.split(separator: ";").map { URL(fileURLWithPath: String($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("git.exe").path) }
            .map { $0.deletingLastPathComponent().appendingPathComponent("bin/bash.exe").path }
            .first { FileManager.default.fileExists(atPath: $0) }
        guard let found = bash else { throw XCTSkip("Git for Windows is not on PATH") }
        // Started with pipes for its standard handles, as CodeBuddy starts it: Git Bash's runtime will not run without.
        let bashProcess = Process()
        bashProcess.executableURL = URL(fileURLWithPath: found)
        bashProcess.arguments = ["-c", command]
        bashProcess.standardInput = Pipe()
        bashProcess.standardOutput = Pipe()
        bashProcess.standardError = Pipe()
        try bashProcess.run()
        bashProcess.waitUntilExit()
        XCTAssertEqual(bashProcess.terminationStatus, 0)
        XCTAssertEqual(try recordedArguments(record), [["--completion-hook", "codebuddy"]])
    }
}
#endif
