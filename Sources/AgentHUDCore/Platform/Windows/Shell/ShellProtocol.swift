#if os(Windows)
import AgentHUDSupport
import Foundation

/// The messages between the engine and the Windows shell (docs/windows-port/PROTOCOL.md, D-041): what Core computed,
/// projected for the shell to show, and what the shell sends back. Every value the shell shows is made here, by Core's
/// own rules and formatting; the shell recomputes nothing.
public enum ShellProtocol {
    public static let major: Int64 = 1
    public static let minor: Int64 = 3
    /// The longest line either side takes.
    public static let lineLimit = 16 * 1024 * 1024

    // MARK: Engine → shell

    public static func hello(engineVersion: String, demo: Bool, language: String, strings: [String: String]) -> JSONValue {
        message("hello", ["minor": .integer(minor), "engine": .object(["version": .string(engineVersion)]),
                          "demo": .bool(demo), "language": .string(language),
                          "strings": .object(strings.mapValues(JSONValue.string))])
    }

    public static func lockHeld(holder: URL?) -> JSONValue {
        message("lock-held", ["holder": holder.map { .string($0.path.replacingOccurrences(of: "/", with: "\\")) } ?? .null])
    }

    public static func error(_ text: String) -> JSONValue { message("error", ["message": .string(text)]) }

    /// The whole of what the HUD shows, as `store` shows it on macOS: its view, and its labels by the same rules
    /// (`AgentRow.resetLabel`, `UsageStore.sessionStatusLabel`), so the shell has nothing to decide.
    @MainActor
    public static func state(store: UsageStore, approvals: [PermissionRequest]) throws -> JSONValue {
        message("state", ["generatedAt": time(store.report?.generatedAt), "paused": .bool(store.isPaused),
                          "error": text(store.lastError), "settings": try JSONValue.from(store.settings.settings),
                          "panel": panel(store), "approvals": .array(approvals.map(approval))])
    }

    /// What the HUD presents once, as `IslandEventTracker` decided it.
    public static func events(_ update: IslandEventTracker.Update, now: Date) -> [JSONValue] {
        update.quotaAlerts.map { alert in
            message("event", ["event": .object([
                "kind": .string("quotaAlert"), "id": .string(alert.id.uuidString.lowercased()),
                "alert": .string(alert.kind.rawValue), "agentId": .string(alert.agent.id), "vendor": .string(alert.agent.vendor),
                "model": .string(alert.agent.model), "preview": .bool(alert.isPreview),
                "timeToExhaust": alert.timeToExhaust.map { .integer(Int64($0.rounded())) } ?? .null,
                "timeToExhaustText": alert.timeToExhaust.map { .string(Countdown.forecast($0)) } ?? .null,
                "alsoExhausted": .array(alert.otherExhaustedWindows.map { .string($0.id) }),
                // 1.2: the card's words, by the Desktop's own copy (ShellEventCopy).
                "copy": ShellEventCopy.quota(alert), "mark": .string(VendorMark.key(alert.agent.vendor)),
            ])])
        } + update.resetCreditGrants.map { grant in
            message("event", ["event": .object([
                "kind": .string("resetCredits"), "id": .string(grant.id.uuidString.lowercased()),
                "added": .integer(Int64(grant.added)), "preview": .bool(grant.isPreview),
                "provider": .string(grant.account.account.provider), "accountLabel": text(grant.account.label),
                "copy": ShellEventCopy.resetCredits(grant),
            ])])
        } + update.completions.map { completion in
            message("event", ["event": .object([
                "kind": .string("completion"), "id": .string(completion.id), "sessionID": .string(completion.sessionID),
                "vendor": .string(completion.agentVendor), "task": .string(completion.task), "model": .string(completion.model),
                "startedAt": time(completion.startedAt), "completedAt": time(completion.completedAt),
                "copy": ShellEventCopy.completion(completion), "mark": .string(VendorMark.key(completion.agentVendor)),
            ])])
        }
    }

    /// One line as it goes over the pipe: the message, its keys sorted, and `\n`.
    public static func line(_ message: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(message) + Data([0x0A])
    }

    // MARK: Projections

    @MainActor
    static func panel(_ store: UsageStore) -> JSONValue {
        let view = store.view
        return .object([
            "now": time(view.now),
            "maxUsedPct": view.maxUsedPct.map(JSONValue.number) ?? .null,
            "glow": .array(view.glowSegments.map { .object(["vendor": .string($0.vendor), "level": .string($0.level.rawValue)]) }),
            // 1.1: the resting HUD's marks, Core's logo queue (`queueMarks`): vendors that share artwork share a mark.
            "marks": .array(view.queueMarks.map { mark in
                .object(["key": .string(mark.key), "vendor": .string(mark.vendor), "isWorking": .bool(mark.isWorking),
                         "waiting": .bool(mark.waitedLongest != nil)])
            }),
            "agents": .array(view.rows.map { row in agent(row, view: view) }),
            "sessions": .array(view.sessions.map {
                session($0, statusText: store.sessionStatusLabel($0.session),
                        project: projectTitle($0.session, report: store.report?.generatedAt))
            }),
        ])
    }

    static func agent(_ row: AgentRow, view: ReportView) -> JSONValue {
        .object([
            "id": .string(row.id), "vendor": .string(row.agent.vendor), "model": .string(row.agent.model),
            "shortModel": text(row.agent.shortModel),
            // 1.1: the row's label as the panel writes it ("Current session", "Weekly limit · Fable"), its short form,
            // and the mark it is drawn with.
            "modelText": .string(L10n.modelLabel(row.agent.model)),
            "shortModelText": .string(L10n.shortModelLabel(row.agent.model)),
            "mark": .string(VendorMark.key(row.agent.vendor)),
            "level": row.level.map { .string($0.rawValue) } ?? .null,
            "usedPct": row.usedPct.map(JSONValue.number) ?? .null,
            "remainingPct": row.remainingPct.map(JSONValue.number) ?? .null,
            "weeklyRemainingPct": row.weeklyRemainingPct.map(JSONValue.number) ?? .null,
            "resetAt": time(row.resetAt),
            // "Pending update" for a reset whose time has passed (a passed deadline is no confirmed reset), "—" for an
            // account not current, "<1m" within the minute: AgentRow's own rule, as the macOS panel shows it.
            "resetText": .string(row.resetLabel(now: view.now)),
            "missingQuotaLabel": .string(row.missingQuotaLabel),
            "paletteIndex": .integer(Int64(row.paletteIndex)),
            "isCurrentAccount": .bool(row.isCurrentAccount),
            "forecastHint": text(view.forecastHint(for: row.id)),
        ])
    }

    /// The titles `SessionProject` gave the working directories of the report `report` was made at: it walks folders
    /// and reads Git's pointers, which is not done again for every state of the same report.
    @MainActor private static var projectTitles: (report: Date?, titles: [String: String?]) = (nil, [:])

    @MainActor
    static func projectTitle(_ live: LiveSession, report: Date?) -> String? {
        if projectTitles.report != report { projectTitles = (report, [:]) }
        let key = live.workingDirectory ?? ""
        if let known = projectTitles.titles[key] { return known }
        let project = SessionProject(live)
        let title = project.path == nil ? nil : project.title
        projectTitles.titles[key] = title
        return title
    }

    /// `statusText` is `UsageStore.sessionStatusLabel`: "Needs approval", "Status out of date", "Live status off" or
    /// the running or idle time; `project` is `SessionProject`'s title.
    static func session(_ session: ReportView.Session, statusText: String, project: String?) -> JSONValue {
        let live = session.session
        return .object([
            "id": .string(live.id), "agentId": .string(live.agentId), "task": .string(live.task),
            "project": text(project),
            // 1.1: the agent the session ran in, and its mark.
            "vendor": text(session.source.agentVendor),
            "mark": text(session.source.agentVendor.map(VendorMark.key)),
            "phase": .string(session.phase.state.rawValue),
            "phaseText": .string(statusText),
            "startedAt": time(live.startedAt), "lastEventAt": time(session.lastEventAt),
            "message": text(session.message), "liveStatus": .bool(session.liveStatus),
            "tokensIn": .integer(Int64(live.tokensIn)), "tokensOut": .integer(Int64(live.tokensOut)),
            "cacheReadTokens": .integer(Int64(live.cacheReadTokens)),
            "tokensText": .string(TokenFormat.inOut(in: live.tokensIn, out: live.tokensOut)),
        ])
    }

    static func approval(_ request: PermissionRequest) -> JSONValue {
        .object([
            "id": .string(request.id), "source": .string(request.source.rawValue), "vendor": .string(request.vendor),
            "mark": .string(VendorMark.key(request.vendor)),
            "sessionID": .string(request.sessionID), "toolName": text(request.toolName), "summary": .string(request.summary),
            "detail": text(request.detail), "project": text(request.project), "path": text(request.path),
            "removed": text(request.removed), "added": text(request.added), "at": time(request.at),
            "isQuestion": .bool(request.isQuestion),
            "questions": .array(request.questions.map { question in
                .object(["key": .string(question.answerKey), "question": .string(question.question),
                         "header": text(question.header), "multiSelect": .bool(question.multiSelect),
                         "options": .array(question.options.map { .object(["label": .string($0.label), "description": text($0.description)]) })])
            }),
            "isPlan": .bool(request.isPlan), "plan": text(request.plan), "answersPlan": .bool(request.answersPlan),
            "alwaysAllowRule": text(request.alwaysAllow == nil ? nil : request.alwaysAllowRule ?? ""),
        ])
    }

    // MARK: Shell → engine

    /// What the shell asked for.
    public enum Command: Equatable, Sendable {
        case hello(minor: Int64, shellVersion: String?)
        case refresh
        /// 1.3: the statistics window asks for its figures (`ShellStatistics`).
        case statistics
        case answer(id: String, Answer)
        case updateSettings([String: JSONValue])
        case quit
    }

    /// The user's answer to a request, before the engine turns it into Core's `PermissionDecision`: "Always allow"
    /// takes the request's own rule (`PermissionRequest.alwaysAllow`), which the shell never sees or builds.
    public enum Answer: Equatable, Sendable {
        case allow, deny, allowAlways, leave
        case answer([String: PermissionQuestion.Answer])
        case approvePlan(acceptEdits: Bool)
        case keepPlanning(note: String?)

        /// Core's decision for `request`; nil for "Always allow" on a request whose client offers no rule.
        public func decision(for request: PermissionRequest) -> PermissionDecision? {
            switch self {
            case .allow: .allow
            case .deny: .deny
            case .leave: .leave
            case .allowAlways: request.alwaysAllow.map(PermissionDecision.allowAlways)
            case .answer(let answers): .answer(answers)
            case .approvePlan(let acceptEdits): .approvePlan(acceptEdits: acceptEdits)
            case .keepPlanning(let note): .keepPlanning(note)
            }
        }
    }

    public struct Rejected: Error, CustomStringConvertible, Equatable {
        public let description: String
    }

    /// The command on one line from the shell; `Rejected` for a line of another version, an unknown type or a
    /// malformed field (D-022: such a line is answered with `error` and changes nothing).
    public static func command(_ line: Data) throws -> Command {
        guard line.count <= lineLimit else { throw Rejected(description: "line longer than \(lineLimit) bytes") }
        guard let value = try? JSONValue.parse(line), case .object(let fields) = value else {
            throw Rejected(description: "not a JSON object")
        }
        guard fields["v"] == .integer(major) else { throw Rejected(description: "not protocol version \(major)") }
        guard case .string(let type)? = fields["type"] else { throw Rejected(description: "no type") }
        switch type {
        case "hello":
            guard case .integer(let minor)? = fields["minor"] else { throw Rejected(description: "hello without minor") }
            return .hello(minor: minor, shellVersion: fields["shell"]?["version"].stringValue)
        case "refresh": return .refresh
        case "statistics": return .statistics
        case "quit": return .quit
        case "update-settings":
            guard case .object(let patch)? = fields["patch"] else { throw Rejected(description: "update-settings without patch") }
            return .updateSettings(patch)
        case "answer":
            guard case .string(let id)? = fields["id"], !id.isEmpty, case .string(let decision)? = fields["decision"] else {
                throw Rejected(description: "answer without id or decision")
            }
            return .answer(id: id, try answer(decision, fields))
        default:
            throw Rejected(description: "unknown type \(type)")
        }
    }

    private static func answer(_ decision: String, _ fields: [String: JSONValue]) throws -> Answer {
        switch decision {
        case "allow": return .allow
        case "deny": return .deny
        case "allowAlways": return .allowAlways
        case "leave": return .leave
        case "approvePlan":
            guard case .bool(let accept)? = fields["acceptEdits"] else { throw Rejected(description: "approvePlan without acceptEdits") }
            return .approvePlan(acceptEdits: accept)
        case "keepPlanning":
            switch fields["note"] {
            case nil, .null?: return .keepPlanning(note: nil)
            case .string(let note)?: return .keepPlanning(note: note)
            default: throw Rejected(description: "keepPlanning note is not text")
            }
        case "answer":
            guard case .object(let given)? = fields["answers"] else { throw Rejected(description: "answer without answers") }
            var answers: [String: PermissionQuestion.Answer] = [:]
            for (key, value) in given {
                guard case .object(let parts) = value, case .array(let selected)? = parts["selected"] else {
                    throw Rejected(description: "answer \(key) without selected")
                }
                let labels = selected.compactMap(\.stringValue)
                guard labels.count == selected.count else { throw Rejected(description: "answer \(key) selects a non-text") }
                let custom: String?
                switch parts["custom"] {
                case nil, .null?: custom = nil
                case .string(let text)?: custom = text
                default: throw Rejected(description: "answer \(key) custom is not text")
                }
                answers[key] = PermissionQuestion.Answer(selected: labels, custom: custom)
            }
            return .answer(answers)
        default:
            throw Rejected(description: "unknown decision \(decision)")
        }
    }

    /// `settings` with `patch` applied by Core: merged into Core's own encoding and decoded by it, so a value Core does
    /// not take is refused here rather than half-applied.
    public static func settings(_ settings: Settings, applying patch: [String: JSONValue]) throws -> Settings {
        guard case .object(var fields) = try JSONValue.from(settings) else { throw Rejected(description: "settings") }
        for (key, value) in patch {
            guard fields[key] != nil else { throw Rejected(description: "unknown setting \(key)") }
            fields[key] = value
        }
        do { return try JSONValue.object(fields).decode(Settings.self) } catch {
            throw Rejected(description: "settings Core does not take: \(error)")
        }
    }

    // MARK: Helpers

    private static func message(_ type: String, _ fields: [String: JSONValue]) -> JSONValue {
        var fields = fields
        fields["v"] = .integer(major)
        fields["type"] = .string(type)
        return .object(fields)
    }

    private static func time(_ date: Date?) -> JSONValue { date.map { .integer(RecordCoding.milliseconds($0)) } ?? .null }
    private static func text(_ value: String?) -> JSONValue { value.map(JSONValue.string) ?? .null }
}
#endif
