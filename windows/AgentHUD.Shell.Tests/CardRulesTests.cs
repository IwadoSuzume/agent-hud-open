// Which card a request gets and what it shows (CardRules, the Desktop's PermissionOpenRow), over the demo's requests.
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD.Shell.Tests;

[TestClass]
public sealed class CardRulesTests
{
    static State Demo()
    {
        for (var folder = new DirectoryInfo(AppContext.BaseDirectory); folder is not null; folder = folder.Parent)
        {
            var file = Path.Combine(folder.FullName, "windows", "protocol", "fixtures", "engine-state.demo.json");
            if (File.Exists(file)) return (State)EngineMessage.Parse(File.ReadAllText(file).TrimEnd('\n'));
        }
        throw new FileNotFoundException("engine-state.demo.json");
    }

    static Approval Request(string id) => Demo().Approvals.Single(r => r.Id == id);

    [TestMethod]
    public void AnEditShowsTheLinesItWouldChangeNotItsPath()
    {
        var edit = Request("demo-edit");
        Assert.AreEqual(CardKind.Plain, CardRules.Kind(edit));
        var diff = CardRules.Diff(edit);
        Assert.IsTrue(diff.Any(l => !l.Added) && diff.Any(l => l.Added), "both sides of the change");
        Assert.AreEqual("−", diff.First().Sign);
        StringAssert.Contains(diff.Last().Text, "?? '?'");
        Assert.IsNull(CardRules.Detail(edit), "the path gives way to the lines, as on the Desktop");
    }

    [TestMethod]
    public void BlankLinesOfAChangeAreKept()
    {
        var edit = Request("demo-edit") with { Removed = "a\n\nb", Added = null };
        CollectionAssert.AreEqual(new[] { "a", "", "b" }, CardRules.Diff(edit).Select(l => l.Text).ToArray());
    }

    [TestMethod]
    public void ACommandShowsItsDetailAndEachKindItsCard()
    {
        var tests = Request("demo-tests");
        Assert.AreEqual(CardKind.Plain, CardRules.Kind(tests));
        Assert.AreEqual("swift test --filter SyncRecordTests", CardRules.Detail(tests));
        Assert.AreEqual(CardKind.Question, CardRules.Kind(Request("demo-question")));
        Assert.AreEqual(CardKind.Plan, CardRules.Kind(Request("demo-plan")));
        Assert.AreEqual(CardKind.PlanElsewhere, CardRules.Kind(Request("demo-plan") with { AnswersPlan = false }));
        Assert.AreEqual(CardKind.Question, CardRules.Kind(Request("demo-question") with { Questions = [] }),
                        "a question routes as a question whatever it holds, never to Allow and Deny");
    }
}
