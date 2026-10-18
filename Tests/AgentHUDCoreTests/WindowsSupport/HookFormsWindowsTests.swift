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
        }
        // Antigravity's approvals use no hook on any platform (`usesHook`), so it is not in this list.
        for source in [PermissionHooks.Source.qoderCN, .qoderWork, .zcode, .workbuddy] {
            XCTAssertThrowsError(try PermissionHooks.configure(source, enabled: true, executable: engine, home: home), "\(source)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.configuration(home: home).path), "\(source)")
            XCTAssertNoThrow(try PermissionHooks.configure(source, enabled: false, executable: engine, home: home), "\(source)")
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
