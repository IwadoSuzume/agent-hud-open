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

    private var language: AppLanguage = .system
    private var zone = TimeZone.current

    /// English and UTC, so that a fixture is the same on every machine: the engine's labels (a reset more than a day
    /// off, by weekday and time) follow the process's time zone, as the macOS panel's do.
    override func setUp() {
        language = L10n.language
        L10n.setLanguage(.en)
        zone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "UTC")!
    }

    override func tearDown() {
        L10n.setLanguage(language)
        NSTimeZone.default = zone
    }

    /// `message` with the random `id` of an alert or a grant (a `UUID` Core draws) replaced by a fixed one.
    private func fixingID(_ message: JSONValue) -> JSONValue {
        guard case .object(var fields) = message, case .object(var event)? = fields["event"] else { return message }
        event["id"] = .string("00000000-0000-0000-0000-000000000000")
        fields["event"] = .object(event)
        return .object(fields)
    }

    /// The fixture's one line without its LF; a fixture with a CR anywhere (a checkout that converted it) fails, as it
    /// does in the C# tests and `check-protocol.py`.
    private func fixture(_ name: String) throws -> Data {
        var data = try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
        XCTAssertEqual(data.last, 0x0A, "\(name) ends with LF")
        if data.last == 0x0A { data.removeLast() }
        XCTAssertFalse(data.contains(0x0D) || data.contains(0x0A), "\(name) is one line, with no CR")
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
    }

    /// The state as the engine builds it: a store on a fixed clock over the demo's report, with the demo's requests
    /// waiting (so sessions show "Needs approval"), plus a question and a plan, which the demo has none of.
    @MainActor
    func testTheStateIsTheSharedFixture() throws {
        let agents = DemoData.everyAgent
        let settings = SettingsStore(defaults: try XCTUnwrap(SettingsFile(url: nil)), defaultAgents: agents)
        let report = DemoUsageProvider.report(agents: agents, historyHours: 24, now: Self.now, stage: nil)
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings, clock: { Self.now })
        store.replace(report: report)
        PermissionRequests.shared.seedDemo(now: Self.now)
        defer { PermissionRequests.shared.showDemo([]) }
        let question = PermissionRequest(
            id: "demo-question", source: .claude, sessionID: "s1", toolName: "AskUserQuestion", summary: "Which database?",
            detail: nil, cwd: "~/work/agent-hud",
            questions: [PermissionQuestion(question: "Which database?", header: "Storage",
                                           options: [.init(label: "SQLite", description: "One file"), .init(label: "Postgres")]),
                        PermissionQuestion(question: "Anything else?", options: [], multiSelect: true)],
            at: Self.now)
        let plan = PermissionRequest(
            id: "demo-plan", source: .claude, sessionID: "s1", toolName: "ExitPlanMode", summary: "Plan", detail: nil,
            cwd: "~/work/agent-hud", answerInput: .object(["plan": .string("1. Read the ledger\n2. Split step 2")]), at: Self.now)
        let approvals = PermissionRequests.shared.pending + [question, plan]
        XCTAssertFalse(store.view.rows.isEmpty)
        XCTAssertTrue(store.view.sessions.contains { $0.phase.state == .waitingForApproval }, "a demo request makes a session wait")
        XCTAssertNotNil(plan.plan, "the plan request carries its plan")
        let state = try ShellProtocol.state(store: store, approvals: approvals)
        let sessions = state["panel"]["sessions"].arrayValue ?? []
        XCTAssertTrue(sessions.contains { $0["phase"].stringValue == "waitingForApproval" && $0["phaseText"].stringValue == "Needs approval" },
                      "the status words are UsageStore.sessionStatusLabel's")
        try assertMatches(state, "engine-state.demo.json")
    }

    /// The same report eight days on, with Claude's live status off: the labels a quick look at the demo never shows —
    /// "Pending update" for a reset whose time has passed (no confirmed reset), "Live status off" for its sessions.
    @MainActor
    func testTheLaterStateIsTheSharedFixture() throws {
        let agents = DemoData.everyAgent
        let settings = SettingsStore(defaults: try XCTUnwrap(SettingsFile(url: nil)), defaultAgents: agents)
        settings.update { $0.setLiveStatus(for: "Claude", enabled: false) }
        let report = DemoUsageProvider.report(agents: agents, historyHours: 24, now: Self.now, stage: nil)
        let later = Self.now.addingTimeInterval(8 * 86_400)
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings, clock: { later })
        store.replace(report: report)
        let state = try ShellProtocol.state(store: store, approvals: [])
        let agentsShown = state["panel"]["agents"].arrayValue ?? [], sessions = state["panel"]["sessions"].arrayValue ?? []
        XCTAssertTrue(agentsShown.contains { $0["resetText"].stringValue == "Pending update" }, "a passed reset is not a confirmed one")
        XCTAssertTrue(sessions.contains { $0["phaseText"].stringValue == "Live status off" })
        try assertMatches(state, "engine-state.later.json")
    }

    @MainActor
    func testEventsAreTheSharedFixtures() throws {
        let report = DemoUsageProvider.report(agents: DemoData.everyAgent, historyHours: 24, now: Self.now, stage: nil)
        let snapshot = try XCTUnwrap(report.snapshots.first)
        let agent = try XCTUnwrap(DemoData.everyAgent.first { $0.id == snapshot.agentId } ?? DemoData.everyAgent.first)
        let alert = QuotaAlert(kind: .exhaustion, agent: agent, snapshot: snapshot, timeToExhaust: 5_400,
                               otherExhaustedWindows: [], isPreview: false)
        let account = try XCTUnwrap(DemoData.accounts(now: Self.now)["Codex"]?.first)
        let grant = ResetCreditGrant(account: account, credits: DemoData.codexResetCredits(now: Self.now), added: 2)
        let completion = SessionCompletion(sessionID: "claude:demo-session", vendor: "Anthropic", turnID: "turn-7",
                                           task: "Anthropic · agent-hud", model: "claude-opus-4-1",
                                           startedAt: Self.now.addingTimeInterval(-90), completedAt: Self.now)
        let events = ShellProtocol.events(IslandEventTracker.Update(completions: [completion], quotaAlerts: [alert],
                                                                    resetCreditGrants: [grant]), now: Self.now)
        XCTAssertEqual(events.count, 3)
        try assertMatches(fixingID(events[0]), "engine-event-quota-alert.json")
        try assertMatches(fixingID(events[1]), "engine-event-reset-credits.json")
        try assertMatches(events[2], "engine-event-completion.json")
        XCTAssertEqual(events[0]["event"]["timeToExhaustText"].stringValue, Countdown.forecast(5_400))
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
