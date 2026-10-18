#if os(Windows)
import AgentHUDSupport
import Foundation
import XCTest
@testable import AgentHUDCore

/// The shell protocol's Swift side against the fixtures the C# side reads too (`windows/protocol/fixtures`,
/// PROTOCOL.md): every engine message is built from Core and compared byte for byte; every shell message is parsed
/// into the command it stands for; the lines a reader must refuse are refused. `AGENT_HUD_WRITE_PROTOCOL_FIXTURES=1`
/// writes the engine fixtures again, for a deliberate change of the protocol.
final class ShellProtocolTests: XCTestCase, @unchecked Sendable {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private static let fixtures = root.appendingPathComponent("windows/protocol/fixtures", isDirectory: true)
    /// A fixed moment, so that every time and countdown in the fixtures is the same on every machine.
    private static let now = Date(timeIntervalSince1970: 1_792_000_000)
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var language: AppLanguage = .system

    override func setUp() {
        language = L10n.language
        L10n.setLanguage(.en)
    }

    override func tearDown() { L10n.setLanguage(language) }

    private func fixture(_ name: String) throws -> Data {
        var data = try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
        while data.last == 0x0A || data.last == 0x0D { data.removeLast() }
        return data
    }

    /// `message` as its line, against the fixture `name` (or written to it when fixtures are being made).
    private func assertMatches(_ message: JSONValue, _ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        var encoded = try ShellProtocol.line(message)
        XCTAssertEqual(encoded.last, 0x0A, "a line ends with LF", file: file, line: line)
        encoded.removeLast()
        XCTAssertFalse(encoded.contains(0x0A), "one message is one line", file: file, line: line)
        if ProcessInfo.processInfo.environment["AGENT_HUD_WRITE_PROTOCOL_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: Self.fixtures, withIntermediateDirectories: true)
            try (encoded + Data([0x0A])).write(to: Self.fixtures.appendingPathComponent(name))
            return
        }
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), String(decoding: try fixture(name), as: UTF8.self),
                       name, file: file, line: line)
    }

    // MARK: Engine → shell

    func testEngineMessagesAreTheSharedFixtures() throws {
        try assertMatches(ShellProtocol.hello(engineVersion: "0", demo: true, language: "en", strings: ShellStrings.current),
                          "engine-hello.json")
        try assertMatches(ShellProtocol.lockHeld(holder: URL(fileURLWithPath: #"C:\Program Files\Agent HUD\agenthud-engine.exe"#)),
                          "engine-lock-held.json")
        try assertMatches(ShellProtocol.error("unknown type nap"), "engine-error.json")

        let agents = DemoData.everyAgent, settings = Settings()
        let report = DemoUsageProvider.report(agents: agents, historyHours: 24, now: Self.now, stage: nil)
        let approvals = DemoData.permissionRequests(now: Self.now)
        let view = ReportView(report: report, agents: agents, settings: settings, approvals: approvals, now: Self.now)
        XCTAssertFalse(view.rows.isEmpty)
        XCTAssertFalse(view.sessions.isEmpty)
        XCTAssertFalse(approvals.isEmpty)
        try assertMatches(try ShellProtocol.state(view: view, generatedAt: report.generatedAt, settings: settings, paused: false,
                                                  error: nil, approvals: approvals, calendar: Self.utc),
                          "engine-state.demo.json")

        let completion = SessionCompletion(sessionID: "claude:demo-session", vendor: "Anthropic", turnID: "turn-7",
                                           task: "Anthropic · agent-hud", model: "claude-opus-4-1",
                                           startedAt: Self.now.addingTimeInterval(-90), completedAt: Self.now)
        let events = ShellProtocol.events(IslandEventTracker.Update(completions: [completion]), now: Self.now)
        XCTAssertEqual(events.count, 1)
        try assertMatches(events[0], "engine-event-completion.json")
    }

    /// Every message the engine sends is the current major version with a type, as the shell requires (D-022).
    func testEveryEngineMessageCarriesTheVersionAndAType() throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path) where name.hasPrefix("engine-") {
            let value = try JSONValue.parse(try fixture(name))
            XCTAssertEqual(value["v"], .integer(1), name)
            XCTAssertNotNil(value["type"].stringValue, name)
        }
    }

    // MARK: Shell → engine

    func testShellMessagesAreTheCommandsTheyStandFor() throws {
        let expected: [String: ShellProtocol.Command] = [
            "shell-hello.json": .hello(minor: 0, shellVersion: "0.1.0"),
            "shell-refresh.json": .refresh,
            "shell-quit.json": .quit,
            "shell-answer-allow.json": .answer(id: "demo-tests", .allow),
            "shell-answer-deny.json": .answer(id: "demo-tests", .deny),
            "shell-answer-always.json": .answer(id: "demo-tests", .allowAlways),
            "shell-answer-leave.json": .answer(id: "demo-tests", .leave),
            "shell-answer-question.json": .answer(id: "demo-question", .answer([
                "Which database?": PermissionQuestion.Answer(selected: ["SQLite"], custom: nil),
                "Anything else?": PermissionQuestion.Answer(selected: [], custom: "Keep the 用量 ledger"),
            ])),
            "shell-answer-plan.json": .answer(id: "demo-plan", .approvePlan(acceptEdits: true)),
            "shell-answer-keep-planning.json": .answer(id: "demo-plan", .keepPlanning(note: "Split step 2")),
            "shell-update-settings.json": .updateSettings(["language": .string("zh-Hans"), "approvalWaitMinutes": .integer(5)]),
        ]
        let present = Set(try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path).filter { $0.hasPrefix("shell-") })
        XCTAssertEqual(present, Set(expected.keys), "every shell fixture is checked here")
        for (name, command) in expected {
            XCTAssertEqual(try ShellProtocol.command(try fixture(name)), command, name)
        }
    }

    func testLinesAReaderMustRefuseAreRefused() throws {
        let folder = Self.fixtures.appendingPathComponent("invalid", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }
        XCTAssertGreaterThanOrEqual(names.count, 8)
        for name in names {
            XCTAssertThrowsError(try ShellProtocol.command(try fixture("invalid/\(name)")), name) {
                XCTAssertTrue($0 is ShellProtocol.Rejected, name)
            }
        }
        var long = Data(#"{"v":1,"type":"refresh","pad":""#.utf8)
        long.append(Data(repeating: 0x61, count: ShellProtocol.lineLimit))
        long.append(Data(#""}"#.utf8))
        XCTAssertThrowsError(try ShellProtocol.command(long), "a line over the limit")
    }

    // MARK: What a command does in Core

    func testAnAnswerBecomesCoresOwnDecision() throws {
        let requests = DemoData.permissionRequests(now: Self.now)
        let ruled = try XCTUnwrap(requests.first { $0.alwaysAllow != nil }, "a demo request offers a rule")
        XCTAssertEqual(ShellProtocol.Answer.allowAlways.decision(for: ruled), .allowAlways(try XCTUnwrap(ruled.alwaysAllow)),
                       "Always allow takes the client's own rule, which the shell never builds")
        if let unruled = requests.first(where: { $0.alwaysAllow == nil }) {
            XCTAssertNil(ShellProtocol.Answer.allowAlways.decision(for: unruled), "no rule offered, no Always allow")
        }
        XCTAssertEqual(ShellProtocol.Answer.allow.decision(for: ruled), .allow)
        XCTAssertEqual(ShellProtocol.Answer.deny.decision(for: ruled), .deny)
        XCTAssertEqual(ShellProtocol.Answer.leave.decision(for: ruled), .leave)
        XCTAssertEqual(ShellProtocol.Answer.keepPlanning(note: "x").decision(for: ruled), .keepPlanning("x"))
    }

    func testASettingsPatchIsAppliedByCoreOrNotAtAll() throws {
        let current = Settings()
        let changed = try ShellProtocol.settings(current, applying: ["approvalWaitMinutes": .integer(5), "language": .string("en")])
        XCTAssertEqual(changed.approvalWaitMinutes, 5)
        XCTAssertEqual(changed.language, .en)
        XCTAssertEqual(changed.clientHooks, current.clientHooks, "fields the patch leaves out keep their values")
        XCTAssertThrowsError(try ShellProtocol.settings(current, applying: ["noSuchSetting": .bool(true)]))
        XCTAssertThrowsError(try ShellProtocol.settings(current, applying: ["language": .string("klingon")]))
        XCTAssertThrowsError(try ShellProtocol.settings(current, applying: ["approvalWaitMinutes": .string("five")]))
    }

    /// The shell's chrome is the macOS Desktop's own words (TASK.md M6): each pair is found as written in its sources.
    func testTheShellsWordsAreTheDesktopsOwn() throws {
        let desktop = Self.root.appendingPathComponent("Sources/AgentHUDDesktop", isDirectory: true)
        var sources = ""
        let walker = try XCTUnwrap(FileManager.default.enumerator(atPath: desktop.path))
        for case let path as String in walker where path.hasSuffix(".swift") {
            sources += (try? String(contentsOf: desktop.appendingPathComponent(path), encoding: .utf8)) ?? ""
        }
        XCTAssertFalse(sources.isEmpty)
        for (key, pair) in ShellStrings.pairs {
            XCTAssertTrue(sources.contains("L10n.text(\"\(pair.zh)\", \"\(pair.en)\")"), "\(key): \(pair.zh) / \(pair.en)")
        }
        L10n.setLanguage(.zhHans)
        XCTAssertEqual(ShellStrings.current["menu.quit"], "退出")
        L10n.setLanguage(.en)
        XCTAssertEqual(ShellStrings.current["menu.quit"], "Quit")
    }
}
#endif
