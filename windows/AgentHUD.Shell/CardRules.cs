// Which card a request gets and what it shows beside its answers, as the macOS Desktop's PermissionOpenRow decides
// (Sources/AgentHUDDesktop/Notch/Alerts/PermissionAlertViews.swift): a question its card, whatever it holds; a plan its
// client answers here its plan card; a plan answered in its own client a notice; any other request its answers, always
// beside what an allow lets run (docs/hud.md, Approvals) — the lines a change would make (PermissionDiff: every removed
// line marked −, every added one +, blank lines kept), else the detail.
using AgentHUD.Protocol;

namespace AgentHUD.Shell;

public enum CardKind { Plain, Question, Plan, PlanElsewhere }

/// <summary>One line of a change: <c>Added</c> false for a removed line (−), true for an added one (+).</summary>
public sealed record DiffLine(bool Added, string Text)
{
    public string Sign => Added ? "+" : "−";
}

public static class CardRules
{
    public static CardKind Kind(Approval request) =>
        request.IsQuestion ? CardKind.Question
        : request.AnswersPlan ? CardKind.Plan
        : request.IsPlan ? CardKind.PlanElsewhere
        : CardKind.Plain;

    /// <summary>The change's lines when the request carries one; then the detail is not shown, as on the Desktop. A
    /// question's card and a plan's own card show neither, whatever the request carries (PermissionOpenRow asks
    /// <c>isQuestion</c> and <c>answersPlan</c> first).</summary>
    public static IReadOnlyList<DiffLine> Diff(Approval request) =>
        Kind(request) is CardKind.Question or CardKind.Plan || request.Removed is null && request.Added is null ? []
        : Lines(request.Removed, added: false).Concat(Lines(request.Added, added: true)).ToList();

    /// <summary>The detail, for a request that carries no change (a question's card and a plan's own card show neither).</summary>
    public static string? Detail(Approval request) =>
        Kind(request) is CardKind.Question or CardKind.Plan || Diff(request).Count > 0 ? null : request.Detail;

    static IEnumerable<DiffLine> Lines(string? text, bool added) =>
        text is null ? [] : text.Split('\n').Select(line => new DiffLine(added, line));
}
