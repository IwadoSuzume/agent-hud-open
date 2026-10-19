#if os(Windows)
import Foundation

/// The words of the Windows shell's own chrome, in the language Core resolved, sent in `hello` (PROTOCOL.md): the shell
/// has none of its own. Each pair is the macOS Desktop's own text, word for word (TASK.md M6: the existing Chinese and
/// English are reused, not written again); `ShellProtocolTests` checks every pair against the Desktop's sources.
/// Keys are added as the shell needs them (M7); a key is never reused for other words.
public enum ShellStrings {
    /// Key → (Chinese, English).
    static let pairs: [String: (zh: String, en: String)] = [
        "menu.settings": ("设置…", "Settings…"),
        "menu.statistics": ("用量统计", "Usage statistics"),
        "menu.quit": ("退出", "Quit"),
        "menu.glow.show": ("显示灵动岛光晕", "Show notch glow"),
        "menu.glow.hide": ("隐藏灵动岛光晕", "Hide notch glow"),
        "menu.noAgents": ("没有启用的模型", "No agents enabled"),
        "approval.allow": ("同意", "Allow"),
        "approval.deny": ("拒绝", "Deny"),
        "approval.always": ("总是允许", "Always allow"),
        "approval.alwaysAdds": ("总是允许会添加", "Always allow adds"),
        "approval.needsApproval": ("等待批准", "Needs approval"),
        "approval.question": ("在问你问题", "Asks a question"),
        "approval.plan": ("有计划待审", "Has a plan to review"),
        // The request's line at rest (PermissionAlertCompactView.status).
        "approval.waitingShort": ("待批准", "Waiting"),
        "approval.questionShort": ("待回答", "Question"),
        "approval.planShort": ("计划待审", "Plan"),
        "alert.dismiss": ("知道了", "Dismiss"),
        "alert.viewStatistics": ("查看用量统计", "View usage statistics"),
        "reply.dismiss": ("关闭回复提醒", "Dismiss reply"),
        // A question card (PermissionQuestionViews.swift).
        "question.chooseAny": ("可多选", "Choose any"),
        "question.other": ("其他", "Other"),
        "question.answer": ("回答", "Answer"),
        "question.typeOwn": ("自己输入回答", "Type your own answer"),
        "question.skip": ("跳过", "Skip"),
        "question.next": ("继续", "Next"),
        "question.submit": ("提交", "Submit"),
        "card.back": ("返回", "Back"),
        // A plan card (PermissionPlanViews.swift, PermissionAlertViews.swift).
        "plan.keepPlanning": ("继续规划", "Keep planning"),
        "plan.approveEdits": ("批准并自动接受编辑", "Approve, accept edits"),
        "plan.approve": ("批准", "Approve"),
        "plan.note": ("要改什么（可不填）", "What should change? (optional)"),
        "plan.send": ("发送", "Send"),
        // `{vendor}` stands where the Desktop interpolates `request.vendor`; the shell puts the request's vendor there.
        "plan.elsewhere": ("请到 {vendor} 里审批这份计划", "Review this plan in {vendor}"),
        // The settings window (SettingsWindowController.swift, GeneralPane.swift).
        "settings.title": ("设置", "Settings"),
        "settings.general": ("通用", "General"),
        "settings.appearanceLanguage": ("外观与语言", "Appearance & language"),
        "settings.appearance": ("外观", "Appearance"),
        "settings.system": ("跟随系统", "System"),
        "settings.light": ("浅色", "Light"),
        "settings.dark": ("深色", "Dark"),
        "settings.language": ("语言", "Language"),
        "settings.startup": ("启动", "Startup"),
        "settings.launchAtLogin": ("登录时启动", "Launch at login"),
        "settings.clients": ("客户端", "Clients"),
        "settings.clientHooks": ("客户端回调", "Client hooks"),
        "settings.clientHooksNote": ("写入各客户端的设置，用来在 HUD 上回答权限请求、显示完成与等待批准。",
                                     "Added to each client's settings so the HUD can answer permission requests and show completions and waiting."),
        "settings.removeHooks": ("移除客户端回调？", "Remove client hooks?"),
        "settings.cancel": ("取消", "Cancel"),
        "settings.remove": ("移除", "Remove"),
        "settings.wait": ("等待回答", "Wait for an answer"),
        "settings.waitNote": ("到时没回答的权限请求交还客户端，由它自己询问。",
                              "After this, an unanswered permission request goes back to the client's own prompt."),
    ]

    /// Words the Windows build needs that the Desktop has no counterpart for, so no source check can hold them (D-053):
    /// a client this build does not read.
    static let windowsOnly: (zh: String, en: String) = ("Windows 暂不支持", "Not supported on Windows")

    static var notSupported: String { L10n.text(windowsOnly.zh, windowsOnly.en) }

    /// Every string, in the resolved language (`L10n`), and the words made from Core's own values: each of the
    /// approval wait's choices (`Settings.approvalWaitChoices`) as GeneralPane names it, under `settings.wait.<minutes>`.
    /// The calls are written as the Desktop writes them; `ShellProtocolTests` finds them in its sources.
    public static var current: [String: String] {
        var words = pairs.mapValues { L10n.text($0.zh, $0.en) }
        for minutes in Settings.approvalWaitChoices {
            words["settings.wait.\(minutes)"] = L10n.text("\(minutes) 分钟", minutes == 1 ? "1 minute" : "\(minutes) minutes")
        }
        return words
    }
}
#endif
