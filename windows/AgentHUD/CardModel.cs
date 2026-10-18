// The open request's card, as the macOS Desktop draws it (Notch/Alerts: PermissionAlertViews, PermissionQuestionViews,
// PermissionPlanViews): a plain request's answers; a question, one at a time, its offered answers and the user's own
// words, skipped or answered and sent together after the last; a plan to read and approve, approve and accept edits,
// or keep planning with a note; a plan its client answers itself, pointed to there. One model per waiting request, kept
// while it waits, so a new state never takes a half-typed answer away.
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows.Media;
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD;

enum CardKind { Plain, Question, Plan, PlanElsewhere }

sealed class CardModel : INotifyPropertyChanged
{
    readonly ShellModel model;
    readonly QuestionDraft question;
    readonly PlanDraft plan;

    public CardModel(Approval request, ShellModel model, Drafts drafts)
    {
        Request = request;
        this.model = model;
        question = drafts.Question(request.Id);
        plan = drafts.Plan(request.Id);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public void Refresh() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));

    public Approval Request { get; private set; }

    /// <summary>The engine's newer copy of the same request.</summary>
    public void Update(Approval request)
    {
        Request = request;
        Refresh();
    }

    public ImageSource? Image => Artwork.Mark(Request.Mark);
    public string Initial => Request.Vendor.Length > 0 ? Request.Vendor[..1].ToUpperInvariant() : "?";

    public CardKind Kind => Request.IsQuestion && Request.Questions.Count > 0 ? CardKind.Question
                          : Request.IsPlan && Request.AnswersPlan ? CardKind.Plan
                          : Request.IsPlan ? CardKind.PlanElsewhere
                          : CardKind.Plain;
    public bool IsPlain => Kind == CardKind.Plain;
    public bool IsQuestion => Kind == CardKind.Question;
    public bool IsPlan => Kind == CardKind.Plan;
    public bool IsPlanElsewhere => Kind == CardKind.PlanElsewhere;

    public string KindText => Request.IsQuestion ? model.Text("approval.question")
                            : Request.IsPlan ? model.Text("approval.plan")
                            : model.Text("approval.needsApproval");

    // A plain request: Deny and Allow always, Always allow only with the client's own rule, written out first.
    public string Deny => model.Text("approval.deny");
    public string Allow => model.Text("approval.allow");
    public string Always => model.Text("approval.always");
    public bool OffersAlways => IsPlain && Request.AlwaysAllowRule is not null;
    public string? AlwaysRule => OffersAlways ? $"{model.Text("approval.alwaysAdds")} {Request.AlwaysAllowRule}" : null;
    /// <summary>What an allow lets run, always beside the answers: the detail, or the change's lines.</summary>
    public string? Subject => IsPlain ? Request.Detail ?? Diff : null;
    string? Diff => Request.Removed is null && Request.Added is null ? null
        : string.Join("\n", (Request.Removed ?? "").Split('\n').Where(l => l.Length > 0).Select(l => "- " + l)
                              .Concat((Request.Added ?? "").Split('\n').Where(l => l.Length > 0).Select(l => "+ " + l)));

    // A question.
    IReadOnlyList<Question> Questions => Request.Questions;
    int Page => System.Math.Clamp(question.Page, 0, System.Math.Max(0, Questions.Count - 1));
    Question? Current => Questions.Count > 0 ? Questions[Page] : null;
    bool IsLast => Page >= Questions.Count - 1;
    public string? PageText => Questions.Count > 1 ? $"{Page + 1}/{Questions.Count}" : null;
    public string QuestionText => Current?.Text ?? "";
    public bool MultiSelect => Current?.MultiSelect == true;
    public string ChooseAny => model.Text("question.chooseAny");
    public IReadOnlyList<OptionModel> Options =>
        Current is { } q ? q.Options.Select((o, i) => new OptionModel(this, i, o, question.IsPicked(Page, i), q.MultiSelect)).ToList() : [];
    public string OwnLabel => Current?.Options.Count == 0 ? model.Text("question.answer") : model.Text("question.other");
    public string OwnPlaceholder => model.Text("question.typeOwn");
    public bool OwnPicked => question.IsOwnPicked(Page);
    public string OwnText
    {
        get => question.Own(Page);
        set { if (Current is { } q && value != question.Own(Page)) { question.Type(value, Page, q); RefreshAnswer(); } }
    }
    public string Skip => model.Text("question.skip");
    public string Back => model.Text("card.back");
    public bool CanGoBack => Page > 0;
    public string NextText => IsLast ? model.Text("question.submit") : model.Text("question.next");
    public bool Ready => Current is { } q && question.Answer(Page, q) is not null;

    void RefreshAnswer()
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Ready)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(OwnPicked)));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Options)));
    }

    public void PickOption(int index)
    {
        if (Current is not { } q) return;
        question.Pick(index, Page, q);
        RefreshAnswer();
    }

    public void ChooseOwn()
    {
        if (Current is not { } q) return;
        question.ChooseOwn(Page, q);
        RefreshAnswer();
    }

    /// <summary>Skip: this question left open, then the next one or the answers sent.</summary>
    public string? SkipQuestion()
    {
        question.Skip(Page);
        return NextOrSend();
    }

    /// <summary>Next or Submit, once this question has an answer; the line to send after the last.</summary>
    public string? Advance() => Ready ? NextOrSend() : null;

    public void GoBack()
    {
        question.Page = Page - 1;
        Refresh();
    }

    string? NextOrSend()
    {
        if (IsLast) return ShellMessage.AnswerQuestions(Request.Id, question.Answers(Questions));
        question.Page = Page + 1;
        Refresh();
        return null;
    }

    // A plan its client answers through the HUD.
    public string PlanText => Rendered(Request.Plan ?? Request.Summary);
    public bool Noting => plan.Noting;
    public bool NotNoting => !plan.Noting;
    public string NoteText { get => plan.Note; set => plan.Note = value; }
    public string NotePlaceholder => model.Text("plan.note");
    public string KeepPlanning => model.Text("plan.keepPlanning");
    public string ApproveEdits => model.Text("plan.approveEdits");
    public string Approve => model.Text("plan.approve");
    public string Send => model.Text("plan.send");
    public void StartNote() { plan.Noting = true; Refresh(); }
    public void StopNote() { plan.Noting = false; Refresh(); }
    public string SendNote() => ShellMessage.KeepPlanning(Request.Id, plan.Note);

    // A plan its client answers in its own dialog.
    public string Elsewhere => model.Text("plan.elsewhere").Replace("{vendor}", Request.Vendor);
    public string Dismiss => model.Text("alert.dismiss");

    /// <summary>The plan's Markdown as the card draws it, the Desktop's `PermissionPlanCard.rendered` reduced to plain
    /// text: its lines as written, a heading without its marks.</summary>
    static string Rendered(string text) => string.Join("\n", text.Split('\n').Select(line =>
    {
        var marks = line.TakeWhile(c => c == '#').Count();
        if (marks == 0 || marks > 6 || line.Length <= marks || line[marks] != ' ') return line;
        return line[marks..].Trim();
    }));
}

sealed record OptionModel(CardModel Card, int Index, QuestionOption Option, bool Picked, bool Multi)
{
    /// <summary>A ring for an answer that stands alone, a box for one of several; filled once chosen.</summary>
    public string Marker => Multi ? (Picked ? "☑" : "☐") : (Picked ? "◉" : "○");
}
