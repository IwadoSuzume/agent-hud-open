// The macOS Desktop's question-draft tests (Tests/AgentHUDDesktopTests/Notch/Alerts/PermissionAlertTests.swift), case for
// case; a question's key is the answer key the engine sends (`PermissionQuestion.answerKey`).
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD.Shell.Tests;

[TestClass]
public sealed class DraftTests
{
    static Question Q(string key, IEnumerable<string> options, bool multiSelect = false) =>
        new(key, key, null, multiSelect, options.Select(o => new QuestionOption(o, null)).ToList());

    static string Show((IReadOnlyList<string> Selected, string? Custom)? answer) =>
        answer is { } a ? $"[{string.Join("|", a.Selected)}]{a.Custom}" : "none";

    static string Show(Dictionary<string, (IReadOnlyList<string> Selected, string? Custom)> answers) =>
        string.Join("; ", answers.OrderBy(a => a.Key, StringComparer.Ordinal).Select(a => $"{a.Key}={Show(a.Value)}"));

    [TestMethod]
    public void AQuestionIsAnsweredWithWhatWasChosenAndSkippedQuestionsAreLeftOut()
    {
        var one = Q("Push now?", ["Push", "Wait"]);
        var many = Q("Which pages?", ["Channels", "Documents"], multiSelect: true);
        var draft = new QuestionDraft();
        Assert.AreEqual("", Show(draft.Answers([one, many])));

        draft.Pick(1, 0, one);
        draft.Pick(0, 0, one);
        Assert.AreEqual("[Push]", Show(draft.Answer(0, one)), "a single answer replaces the one before it");
        draft.Type("Push tomorrow", 0, one);
        Assert.AreEqual("[]Push tomorrow", Show(draft.Answer(0, one)), "writing one's own answer sets the offered ones aside");
        draft.Type("  ", 0, one);
        Assert.AreEqual("none", Show(draft.Answer(0, one)), "blank words are no answer");
        draft.Pick(1, 0, one);
        draft.ChooseOwn(0, one);
        Assert.AreEqual("none", Show(draft.Answer(0, one)), "going into the field sets the offered answer aside");
        draft.Pick(1, 0, one);

        draft.Pick(1, 1, many);
        draft.Pick(0, 1, many);
        draft.Type("Settings", 1, many);
        Assert.AreEqual("Push now?=[Wait]; Which pages?=[Channels|Documents]Settings", Show(draft.Answers([one, many])),
                        "several answers keep the order they were offered in, the user's own words last");
        draft.Pick(0, 1, many);
        Assert.AreEqual("[Documents]Settings", Show(draft.Answer(1, many)), "picking again takes it back");
        draft.Skip(1);
        Assert.AreEqual("Push now?=[Wait]", Show(draft.Answers([one, many])), "a skipped question is left out");
    }

    [TestMethod]
    public void QuestionAnswersKeepIdentityChoicesAndCustomWordsSeparate()
    {
        var one = Q("one", ["CSV, JSON"]);
        var two = Q("two", ["A"], multiSelect: true);
        var draft = new QuestionDraft();
        draft.Pick(0, 0, one);
        draft.Pick(0, 1, two);
        draft.Type("A, but later", 1, two);
        Assert.AreEqual("one=[CSV, JSON]; two=[A]A, but later", Show(draft.Answers([one, two])));
    }

    [TestMethod]
    public void FreeTextQuestionCanBeAnsweredAndSkippedWithoutLosingItsDraft()
    {
        var question = Q("readiness", []);
        var draft = new QuestionDraft();
        Assert.AreEqual("none", Show(draft.Answer(0, question)));

        draft.Type("  \n  ", 0, question);
        Assert.AreEqual("none", Show(draft.Answer(0, question)), "whitespace leaves Submit disabled");
        Assert.AreEqual("", Show(draft.Answers([question])));

        draft.Type("  已就绪  ", 0, question);
        Assert.AreEqual("[]已就绪", Show(draft.Answer(0, question)));
        Assert.AreEqual("readiness=[]已就绪", Show(draft.Answers([question])));
        Assert.AreEqual("  已就绪  ", draft.Own(0), "the field keeps the user's original text");

        draft.Skip(0);
        Assert.AreEqual("", Show(draft.Answers([question])), "Skip sends no answer for this question");
        Assert.AreEqual("  已就绪  ", draft.Own(0), "Skip preserves the draft for a return to this question");
        draft.ChooseOwn(0, question);
        Assert.AreEqual("[]已就绪", Show(draft.Answer(0, question)));
    }

    [TestMethod]
    public void DraftsLiveAsLongAsTheirRequestsWait()
    {
        var drafts = new Drafts();
        drafts.Question("a").Page = 2;
        drafts.Plan("b").Note = "Split step 2";
        Assert.AreEqual(2, drafts.Question("a").Page, "the same draft each time the card is drawn");
        drafts.Keep(["b"]);
        Assert.AreEqual(0, drafts.Question("a").Page, "a request that left takes its draft with it");
        Assert.AreEqual("Split step 2", drafts.Plan("b").Note);
    }
}
