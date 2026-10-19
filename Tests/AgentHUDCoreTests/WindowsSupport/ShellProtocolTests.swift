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
        // The Windows demo's requests: the macOS demo's, then a question and a plan (`DemoData.windowsDemoRequests`).
        PermissionRequests.shared.showDemo(DemoData.windowsDemoRequests(now: Self.now))
        defer { PermissionRequests.shared.showDemo([]) }
        let approvals = PermissionRequests.shared.pending
        let plan = try XCTUnwrap(approvals.first { $0.id == "demo-plan" })
        XCTAssertFalse(store.view.rows.isEmpty)
        XCTAssertTrue(store.view.sessions.contains { $0.phase.state == .waitingForApproval }, "a demo request makes a session wait")
        XCTAssertNotNil(plan.plan, "the plan request carries its plan")
        // 1.4: two displays, one with a placement of its own on the left edge, the other on Core's default.
        settings.update { $0.screens["DISPLAY-B"] = ScreenPlacement(mode: .logos, edge: .left, offset: 0.3) }
        let displays = [ShellProtocol.Display(key: "DISPLAY-A", hasNotch: false), ShellProtocol.Display(key: "DISPLAY-B", hasNotch: false)]
        let state = try ShellProtocol.state(store: store, approvals: approvals, displays: displays)
        let sessions = state["panel"]["sessions"].arrayValue ?? []
        XCTAssertTrue(sessions.contains { $0["phase"].stringValue == "waitingForApproval" && $0["phaseText"].stringValue == "Needs approval" },
                      "the status words are UsageStore.sessionStatusLabel's")
        XCTAssertEqual(state["placements"]["DISPLAY-A"]["mode"].stringValue, "logos", "a display without a notch defaults to the dock")
        XCTAssertEqual(state["placements"]["DISPLAY-A"]["edge"].stringValue, "top")
        XCTAssertEqual(state["placements"]["DISPLAY-B"]["edge"].stringValue, "left", "a display keeps its own placement")
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

    /// 1.5: the clients the build looks for, as the settings window lists them: the demo's sources, and the clients
    /// this build does not read, which say so.
    func testTheSourcesAreTheSharedFixture() throws {
        XCTAssertFalse(ShellSources.isSupported(SourceStatus(id: "zcode", name: "ZCode", detail: "", state: .notDetected)))
        XCTAssertFalse(ShellSources.isSupported(SourceStatus(id: "antigravity", name: "Antigravity", detail: "", state: .installed)))
        XCTAssertFalse(ShellSources.isSupported(SourceStatus(id: "grok-bot", name: "Grok Bot", detail: "", state: .installed)))
        XCTAssertTrue(ShellSources.isSupported(SourceStatus(id: "claude-code", name: "Claude", detail: "", state: .installed)))
        let unsupported = SourceStatus(id: "workbuddy", name: "WorkBuddy", detail: "Sessions", state: .installed, provider: "WorkBuddy")
        let message = ShellSources.message(sources: DemoData.sources + [unsupported])
        let listed = message["sources"].arrayValue ?? []
        // The demo's Antigravity has no Windows location (PlatformSupport): it is listed and says so, as WorkBuddy does.
        let unread = listed.filter { $0["supported"] == .bool(false) }
        XCTAssertEqual(unread.map { $0["id"].stringValue }, ["antigravity", "workbuddy"])
        XCTAssertTrue(unread.allSatisfy { $0["status"].stringValue == "Not supported on Windows" })
        try assertMatches(message, "engine-sources.json")
    }

    /// 1.3: the statistics window's Recent usage card, as the Desktop's UsagePeriodsCard makes it from the demo's report:
    /// three periods, each with its total, cost and cache share and the models that spent the most.
    @MainActor
    func testTheStatisticsAreTheSharedFixture() throws {
        let agents = DemoData.everyAgent
        let settings = SettingsStore(defaults: try XCTUnwrap(SettingsFile(url: nil)), defaultAgents: agents)
        let report = DemoUsageProvider.report(agents: agents, historyHours: 24 * 30, now: Self.now, stage: nil)
        let store = UsageStore(provider: DemoUsageProvider(), settings: settings, clock: { Self.now })
        store.replace(report: report)
        let statistics = ShellStatistics.message(store: store)
        let periods = statistics["periods"].arrayValue ?? []
        XCTAssertEqual(periods.map { $0["period"].stringValue }, ["today", "days7", "days30"])
        XCTAssertFalse(periods.allSatisfy { ($0["models"].arrayValue ?? []).isEmpty }, "the demo spent tokens")
        for period in periods {
            let shares = (period["models"].arrayValue ?? []).compactMap { model -> Double? in
                if case .number(let share) = model["share"] { return share }
                return nil
            }
            if !shares.isEmpty { XCTAssertEqual(shares.reduce(0, +), 1, accuracy: 1e-9, "the shares make the whole bar") }
        }
        try assertMatches(statistics, "engine-statistics.json")
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
            "shell-hello.json": .hello(minor: ShellProtocol.minor, shellVersion: "0.1.0"),
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
            "shell-statistics.json": .statistics,
            "shell-displays.json": .displays([.init(key: "DISPLAY-A", hasNotch: false)]),
            "shell-sources.json": .sources,
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
        // White space aside: the Desktop breaks a long pair over two lines.
        func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let flat = squeezed(sources)
        for (key, pair) in ShellStrings.pairs {
            // A template's `{vendor}` is the Desktop's interpolation of the request's vendor.
            let zh = pair.zh.replacingOccurrences(of: "{vendor}", with: #"\(request.vendor)"#)
            let en = pair.en.replacingOccurrences(of: "{vendor}", with: #"\(request.vendor)"#)
            XCTAssertTrue(flat.contains(squeezed("L10n.text(\"\(zh)\", \"\(en)\")")), "\(key): \(pair.zh) / \(pair.en)")
        }
        L10n.setLanguage(.zhHans)
        XCTAssertEqual(ShellStrings.current["menu.quit"], "退出")
        XCTAssertEqual(ShellStrings.current["settings.wait.1"], "1 分钟")
        L10n.setLanguage(.en)
        XCTAssertEqual(ShellStrings.current["menu.quit"], "Quit")
        XCTAssertEqual(ShellStrings.current["settings.wait.1"], "1 minute")
        XCTAssertEqual(ShellStrings.current["settings.wait.30"], "30 minutes")
        XCTAssertEqual(Settings.approvalWaitChoices.filter { ShellStrings.current["settings.wait.\($0)"] == nil }, [], "every choice is named")
    }

    /// 1.5's source rules are the Desktop's (`SourceDetector.resolve` and `detect`, macOS code the engine may not link):
    /// the two functions' bodies are compared as written, white space aside, so an upstream change to either shows here.
    /// The one difference meant is the home folder, `UserHome.directory` for `fileManager.homeDirectoryForCurrentUser`.
    func testTheSourcesRulesAreTheDesktopsCopy() throws {
        func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        /// The function `name`'s text, from its declaration to the brace that closes it.
        func function(_ name: String, in text: String) throws -> String {
            let start = try XCTUnwrap(text.range(of: "static func \(name)("), name)
            var depth = 0, opened = false
            var index = start.lowerBound
            while index < text.endIndex {
                let character = text[index]
                if character == "{" { depth += 1; opened = true }
                if character == "}" { depth -= 1; if opened, depth == 0 { return String(text[start.lowerBound...index]) } }
                index = text.index(after: index)
            }
            XCTFail("\(name) has no closing brace")
            return ""
        }
        let desktop = try String(contentsOf: Self.root.appendingPathComponent("Sources/AgentHUDDesktop/System/SourceDetector.swift"),
                                 encoding: .utf8)
        let engine = try String(contentsOf: Self.root.appendingPathComponent("Sources/AgentHUDCore/Platform/Windows/Shell/ShellSources.swift"),
                                encoding: .utf8)
        for name in ["resolve", "detect"] {
            let theirs = squeezed(try function(name, in: desktop))
                .replacingOccurrences(of: "fileManager.homeDirectoryForCurrentUser", with: "UserHome.directory")
            XCTAssertEqual(squeezed(try function(name, in: engine)), theirs, "ShellSources.\(name) is SourceDetector.\(name)")
        }
    }

    /// An event's words (protocol 1.2) are the Desktop's copy: every `L10n.text` call of ShellEventCopy.swift is found
    /// in the Desktop's sources as written, interpolations and all (white space aside, as the two indent differently).
    func testTheEventsWordsAreTheDesktopsCopy() throws {
        func squeezed(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let desktop = Self.root.appendingPathComponent("Sources/AgentHUDDesktop", isDirectory: true)
        var sources = ""
        let walker = try XCTUnwrap(FileManager.default.enumerator(atPath: desktop.path))
        for case let path as String in walker where path.hasSuffix(".swift") {
            sources += (try? String(contentsOf: desktop.appendingPathComponent(path), encoding: .utf8)) ?? ""
        }
        sources = squeezed(sources)
        // A call with words of its own (not ShellStrings' `L10n.text($0.zh, $0.en)`), its interpolations one level deep:
        // `L10n.text("\(names)额度仍已耗尽", "Still exhausted: \(names)")`. ShellStrings' calls made from Core's values
        // (the approval wait's choices) are held to the Desktop's the same way.
        let call = try NSRegularExpression(pattern: #"L10n\.text\("(?:[^()]|\([^()]*\))*\)"#)
        var calls: [String] = []
        for file in ["ShellEventCopy.swift", "ShellStrings.swift", "ShellStatistics.swift", "ShellSources.swift"] {
            let text = try String(contentsOf: Self.root.appendingPathComponent("Sources/AgentHUDCore/Platform/Windows/Shell/\(file)"),
                                  encoding: .utf8)
            calls += call.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        }
        XCTAssertGreaterThanOrEqual(calls.count, 21, "the calls are found")
        for found in calls {
            XCTAssertTrue(sources.contains(squeezed(found)), found)
        }
    }
}
#endif
