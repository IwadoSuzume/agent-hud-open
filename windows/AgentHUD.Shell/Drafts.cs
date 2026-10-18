// What the user has given so far on a question or a plan card, as the macOS Desktop keeps it
// (Sources/AgentHUDDesktop/Notch/Alerts/PermissionQuestionViews.swift QuestionDraft, PermissionPlanViews.swift
// PlanDraft): apart from the card, which is drawn again as the pointer comes and goes, and gone when its request leaves.
using AgentHUD.Protocol;

namespace AgentHUD.Shell;

/// <summary>What the user has chosen so far on a question card, one entry per question.</summary>
public sealed class QuestionDraft
{
    /// <summary>The question on screen.</summary>
    public int Page { get; set; }
    readonly Dictionary<int, HashSet<int>> picks = [];
    readonly Dictionary<int, string> own = [];
    readonly HashSet<int> ownPicked = [];

    public bool IsPicked(int index, int option) => picks.TryGetValue(index, out var chosen) && chosen.Contains(option);
    public bool IsOwnPicked(int index) => ownPicked.Contains(index);
    public string Own(int index) => own.TryGetValue(index, out var text) ? text : "";

    /// <summary>Picks an offered answer. A question with one answer takes this one instead of whatever it had; one with
    /// several adds or removes it.</summary>
    public void Pick(int option, int index, Question question)
    {
        if (question.MultiSelect)
        {
            var chosen = picks.TryGetValue(index, out var set) ? set : picks[index] = [];
            if (!chosen.Remove(option)) chosen.Add(option);
        }
        else
        {
            picks[index] = [option];
            ownPicked.Remove(index);
        }
    }

    /// <summary>Going into the field is choosing to answer in one's own words; with a single answer that sets the
    /// offered ones aside.</summary>
    public void ChooseOwn(int index, Question question)
    {
        ownPicked.Add(index);
        if (!question.MultiSelect) picks[index] = [];
    }

    public void Type(string text, int index, Question question)
    {
        own[index] = text;
        ChooseOwn(index, question);
    }

    /// <summary>Leaves a question without an answer. What was typed stays, in case the user comes back to it.</summary>
    public void Skip(int index)
    {
        picks[index] = [];
        ownPicked.Remove(index);
    }

    /// <summary>The answer as the client files it: an offered label, several in the order they were offered, the
    /// user's own words — or nothing yet.</summary>
    public (IReadOnlyList<string> Selected, string? Custom)? Answer(int index, Question question)
    {
        var selected = question.Options.Select((option, i) => (option, i)).Where(o => IsPicked(index, o.i))
                                       .Select(o => o.option.Label).ToList();
        string? custom = null;
        if (ownPicked.Contains(index) && own.TryGetValue(index, out var text) && text.Trim() is { Length: > 0 } trimmed)
            custom = trimmed;
        return selected.Count == 0 && custom is null ? null : (selected, custom);
    }

    /// <summary>The answers given, each filed under its question. A question skipped is simply not among them, and the
    /// client reads that as the user leaving it open.</summary>
    public Dictionary<string, (IReadOnlyList<string> Selected, string? Custom)> Answers(IReadOnlyList<Question> questions)
    {
        var answers = new Dictionary<string, (IReadOnlyList<string>, string?)>();
        for (var index = 0; index < questions.Count; index++)
            if (Answer(index, questions[index]) is { } answer) answers[questions[index].Key] = answer;
        return answers;
    }
}

/// <summary>Whether the user is writing what a plan should change, and what they wrote so far.</summary>
public sealed class PlanDraft
{
    public bool Noting { get; set; }
    public string Note { get; set; } = "";
}

/// <summary>The drafts of the requests still waiting, by request id.</summary>
public sealed class Drafts
{
    readonly Dictionary<string, QuestionDraft> questions = [];
    readonly Dictionary<string, PlanDraft> plans = [];

    public QuestionDraft Question(string requestId) =>
        questions.TryGetValue(requestId, out var draft) ? draft : questions[requestId] = new QuestionDraft();

    public PlanDraft Plan(string requestId) =>
        plans.TryGetValue(requestId, out var draft) ? draft : plans[requestId] = new PlanDraft();

    /// <summary>Keeps the drafts of the requests still waiting and forgets the rest.</summary>
    public void Keep(IReadOnlyCollection<string> waiting)
    {
        foreach (var gone in questions.Keys.Where(id => !waiting.Contains(id)).ToList()) questions.Remove(gone);
        foreach (var gone in plans.Keys.Where(id => !waiting.Contains(id)).ToList()) plans.Remove(gone);
    }
}
