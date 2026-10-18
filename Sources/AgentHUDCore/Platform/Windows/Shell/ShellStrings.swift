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
        "alert.dismiss": ("知道了", "Dismiss"),
    ]

    /// Every string, in the resolved language (`L10n`).
    public static var current: [String: String] { pairs.mapValues { L10n.text($0.zh, $0.en) } }
}
#endif
