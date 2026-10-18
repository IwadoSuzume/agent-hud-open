#if os(Windows)
import AgentHUDSupport
import Foundation

/// The Windows demo's two cards the macOS demo does not seed: a question and a plan, for the shell's `--demo` and its
/// snapshot (G5) and for the protocol's state fixture. `DemoData.permissionRequest(_:at:)` reaches them by id.
extension DemoData {
    static func windowsPermissionRequest(_ id: String, at: Date) -> PermissionRequest? {
        switch id {
        case "demo-question":
            return PermissionRequest(
                id: "demo-question", source: .claude, sessionID: "s1", toolName: "AskUserQuestion", summary: "Which database?",
                detail: nil, cwd: "~/work/agent-hud",
                questions: [PermissionQuestion(question: "Which database?", header: "Storage",
                                               options: [.init(label: "SQLite", description: "One file"), .init(label: "Postgres")]),
                            PermissionQuestion(question: "Anything else?", options: [], multiSelect: true)],
                at: at)
        case "demo-plan":
            return PermissionRequest(
                id: "demo-plan", source: .claude, sessionID: "s1", toolName: "ExitPlanMode", summary: "Plan", detail: nil,
                cwd: "~/work/agent-hud", answerInput: .object(["plan": .string("1. Read the ledger\n2. Split step 2")]), at: at)
        default:
            return nil
        }
    }

    /// The Windows demo's requests: the macOS demo's, then the question and the plan, asked last.
    static func windowsDemoRequests(now: Date) -> [(id: String, at: Date)] {
        permissionRequests(now: now).map { (id: $0.id, at: $0.at) } + [(id: "demo-question", at: now), (id: "demo-plan", at: now)]
    }
}
#endif
