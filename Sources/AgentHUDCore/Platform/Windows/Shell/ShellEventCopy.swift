#if os(Windows)
import AgentHUDSupport
import Foundation

/// The words an event's card shows on Windows (protocol 1.2, `event.copy`), made by the rules of the macOS Desktop's
/// own copy (`QuotaAlertCopy` in Notch/Alerts/QuotaAlertViews.swift, `ResetCreditAlertCopy` in ResetCreditAlertViews.swift,
/// the reply cards of IslandAlertViews.swift), which are private to the Desktop and drawn with its theme. Each
/// `L10n.text` call here is written exactly as the Desktop writes it, its interpolations named the same, and
/// `ShellProtocolTests` holds every one of them to the Desktop's sources; the shell shows these words and decides none.
enum ShellEventCopy {
    struct QuotaAlertCopy {
        let alert: QuotaAlert
        var usedPct: Double? { alert.snapshot.remainingPct.map { max(0, 100 - $0) } }
        var used: String { usedPct.map(TokenFormat.percent) ?? "N/A" }
        var remaining: String { alert.snapshot.remainingPct.map(TokenFormat.percent) ?? "N/A" }
        var exhaustion: String {
            guard alert.snapshot.remainingPct != nil, let duration = alert.timeToExhaust else { return "—" }
            return Countdown.compact(max(60, ceil(duration / 60) * 60))
        }
        var reset: String { Countdown.resetLabelCompact(alert.snapshot.resetAt, now: alert.snapshot.updatedAt) }
        var compactTitle: String {
            guard let remaining = alert.snapshot.remainingPct else { return L10n.text("额度不可用", "Quota unavailable") }
            if alert.kind == .reset { return L10n.text("已重置", "Reset") }
            if remaining <= AlertPolicy.exhaustedRemaining { return L10n.text("已耗尽", "Empty") }
            if alert.timeToExhaust != nil { return L10n.text("\(exhaustion) 后耗尽", "\(exhaustion) left") }
            return L10n.text("即将耗尽", "Running low")
        }
        var title: String {
            guard let remaining = alert.snapshot.remainingPct else { return L10n.text("额度暂不可用。", "Quota is unavailable.") }
            if alert.kind == .reset {
                return alert.otherExhaustedWindows.isEmpty
                    ? L10n.text("此窗口额度已重置。", "This quota window has reset.")
                    : L10n.text("此窗口已重置，其他窗口仍有限制。", "This window has reset; other limits still apply.")
            }
            if remaining <= AlertPolicy.exhaustedRemaining {
                return L10n.text("当前窗口额度已耗尽，等待重置。", "This window is empty. Waiting for reset.")
            }
            if alert.timeToExhaust != nil {
                return L10n.text("按最近的消耗速率，预计将在重置前耗尽。", "At the recent burn rate, this window may run out before it resets.")
            }
            return L10n.text("已用额度达到危险阈值，请留意后续任务。", "Usage has reached the critical threshold.")
        }
        var otherLimits: String {
            let names = alert.otherExhaustedWindows.map(\.name).joined(separator: "、")
            return L10n.text("\(names)额度仍已耗尽", "Still exhausted: \(names)")
        }
        /// The detail card's badge and the label of its second figure (`QuotaAlertDetailView`).
        var badge: String { alert.kind == .reset ? L10n.text("已重置", "reset") : L10n.text("额度预警", "running low") }
        var secondLabel: String {
            alert.kind == .reset ? L10n.text("剩余额度", "remaining") : L10n.text("预计耗尽", "until empty")
        }
        var second: String { alert.kind == .reset ? remaining : exhaustion }
    }

    struct ResetCreditAlertCopy {
        let grant: ResetCreditGrant
        var compactTitle: String {
            L10n.text("+\(grant.added) 次重置", grant.added == 1 ? "+1 reset" : "+\(grant.added) resets")
        }
        var title: String {
            L10n.text("此账户新增了 \(grant.added) 次额度重置。",
                      grant.added == 1 ? "A usage reset was added to this account." : "\(grant.added) usage resets were added to this account.")
        }
        /// The account's earliest deadline, as the usage panel names it.
        var expiry: String {
            guard let deadline = grant.credits.creditsByExpiry.compactMap(\.expirationDate).first else { return "—" }
            return deadline.formatted(Date.FormatStyle().month(.abbreviated).day()
                .locale(L10n.dateLocale))
        }
    }

    /// A quota alert's words (`QuotaAlertCompactView`, `QuotaAlertDetailView`).
    static func quota(_ alert: QuotaAlert) -> JSONValue {
        let copy = QuotaAlertCopy(alert: alert)
        return .object([
            "vendorName": .string(alert.agent.vendorName), "agentName": .string(alert.agent.name),
            "displayName": .string(alert.agent.displayName),
            "compactTitle": .string(copy.compactTitle), "title": .string(copy.title), "badge": .string(copy.badge),
            "warning": .bool(alert.kind == .exhaustion),
            "usedPct": copy.usedPct.map(JSONValue.number) ?? .null,
            "metrics": .array([
                metric(copy.used, L10n.text("已用额度", "used")), metric(copy.second, copy.secondLabel),
                metric(copy.reset, L10n.text("下次重置", "next reset")),
            ]),
            "otherLimits": alert.otherExhaustedWindows.isEmpty ? .null : .string(copy.otherLimits),
        ])
    }

    /// Reset credits' words (`ResetCreditAlertCompactView`, `ResetCreditAlertDetailView`).
    static func resetCredits(_ grant: ResetCreditGrant) -> JSONValue {
        let copy = ResetCreditAlertCopy(grant: grant)
        return .object([
            "vendorName": .string(grant.account.account.provider),
            "compactTitle": .string(copy.compactTitle), "title": .string(copy.title),
            "badge": .string(L10n.text("新增重置", "new reset")), "warning": .bool(false),
            "metrics": .array([
                metric("+\(grant.added)", L10n.text("新增", "added")),
                metric("\(grant.credits.availableCount)", L10n.text("可用次数", "available")),
                metric(copy.expiry, L10n.text("最早到期", "first expires")),
            ]),
        ])
    }

    /// A finished turn's words (the reply card, IslandAlertViews.swift).
    static func completion(_ completion: SessionCompletion) -> JSONValue {
        .object(["status": .string(L10n.text("有新回复", "New reply")), "title": .string(completion.task),
                 "vendorName": .string(completion.agentVendor), "warning": .bool(false)])
    }

    private static func metric(_ value: String, _ label: String) -> JSONValue {
        .object(["value": .string(value), "label": .string(label)])
    }
}
#endif
