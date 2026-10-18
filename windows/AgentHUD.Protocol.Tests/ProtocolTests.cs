// The protocol's C# side against the fixtures the Swift side checks too (windows/protocol/fixtures, PROTOCOL.md):
// every engine message the Swift engine wrote is read into its type; every shell message is written byte for byte as
// its fixture; the lines a reader must refuse are refused.
using System.Text;
using System.Text.Json.Nodes;
using AgentHUD.Protocol;

namespace AgentHUD.Protocol.Tests;

[TestClass]
public sealed class ProtocolTests
{
    static readonly string Fixtures = FindFixtures();

    static string FindFixtures()
    {
        for (var folder = new DirectoryInfo(AppContext.BaseDirectory); folder != null; folder = folder.Parent)
        {
            var candidate = Path.Combine(folder.FullName, "windows", "protocol", "fixtures");
            if (Directory.Exists(candidate)) return candidate;
            candidate = Path.Combine(folder.FullName, "protocol", "fixtures");
            if (Directory.Exists(candidate)) return candidate;
        }
        throw new DirectoryNotFoundException("windows/protocol/fixtures");
    }

    /// <summary>The fixture's one line, without its LF.</summary>
    static string Line(string name)
    {
        var bytes = File.ReadAllBytes(Path.Combine(Fixtures, name));
        Assert.IsFalse(bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF, $"{name}: no BOM");
        var text = new UTF8Encoding(false, true).GetString(bytes);
        Assert.EndsWith("\n", text, $"{name}: ends with LF");
        text = text[..^1];
        Assert.IsFalse(text.Contains('\n') || text.Contains('\r'), $"{name}: one line");
        return text;
    }

    [TestMethod]
    public void TheEnginesHelloIsRead()
    {
        var hello = (EngineHello)EngineMessage.Parse(Line("engine-hello.json"));
        Assert.AreEqual(1, hello.Minor, "the engine speaks 1.1");
        Assert.IsTrue(hello.Demo);
        Assert.AreEqual("en", hello.Language);
        Assert.AreEqual("Quit", hello.Strings["menu.quit"]);
        Assert.AreEqual("Always allow", hello.Strings["approval.always"]);
    }

    [TestMethod]
    public void TheEnginesStateIsReadWhole()
    {
        var state = (State)EngineMessage.Parse(Line("engine-state.demo.json"));
        Assert.IsFalse(state.Paused);
        Assert.IsNull(state.Error);
        Assert.IsNotEmpty(state.Panel.Agents);
        Assert.IsNotEmpty(state.Panel.Sessions);
        Assert.IsNotEmpty(state.Approvals);
        Assert.AreEqual(DateTimeOffset.FromUnixTimeMilliseconds(1_792_000_000_000), state.Panel.Now);
        // The engine's words and judgements arrive as they are: the shell shows them, it does not work them out.
        Assert.IsTrue(state.Panel.Agents.All(a => a.MissingQuotaLabel.Length > 0));
        Assert.IsTrue(state.Panel.Sessions.All(s => s.PhaseText.Length > 0 && s.TokensText.Length > 0));
        Assert.IsTrue(state.Panel.Agents.Where(a => a.ResetAt != null).All(a => a.ResetText != null));
        Assert.AreEqual("system", state.Settings["language"]?.GetValue<string>());
    }

    [TestMethod]
    public void TheOtherEngineMessagesAreRead()
    {
        Assert.AreEqual(@"C:\Program Files\Agent HUD\agenthud-engine.exe", ((LockHeld)EngineMessage.Parse(Line("engine-lock-held.json"))).Holder);
        Assert.AreEqual("unknown type nap", ((EngineError)EngineMessage.Parse(Line("engine-error.json"))).Message);
        var completion = (CompletionEvent)EngineMessage.Parse(Line("engine-event-completion.json"));
        Assert.AreEqual("claude:demo-session", completion.SessionId);
        Assert.AreEqual(DateTimeOffset.FromUnixTimeMilliseconds(1_792_000_000_000), completion.CompletedAt);
    }

    [TestMethod]
    public void EveryEngineFixtureIsRead()
    {
        var names = Directory.GetFiles(Fixtures, "engine-*.json").Select(Path.GetFileName).ToList();
        Assert.IsGreaterThanOrEqualTo(5, names.Count);
        foreach (var name in names) Assert.IsNotNull(EngineMessage.Parse(Line(name!)), name);
    }

    /// <summary>A later minor version adds fields; a 1.0 reader ignores them.</summary>
    [TestMethod]
    public void FieldsOfALaterMinorVersionAreIgnored()
    {
        var hello = JsonNode.Parse(Line("engine-hello.json"))!.AsObject();
        hello["minor"] = 3;
        hello["somethingNew"] = new JsonObject { ["x"] = 1 };
        Assert.AreEqual(3, ((EngineHello)EngineMessage.Parse(hello.ToJsonString())).Minor);
    }

    /// <summary>1.1 added the resting marks, the rows' labels and the marks of rows, sessions and requests; a 1.0
    /// engine's state, without them, is still read, its rows labelled by their model as given.</summary>
    [TestMethod]
    public void AStateWithoutTheFieldsOf11IsRead()
    {
        var state = JsonNode.Parse(Line("engine-state.demo.json"))!.AsObject();
        var panel = state["panel"]!.AsObject();
        panel.Remove("marks");
        foreach (var row in panel["agents"]!.AsArray()) { row!.AsObject().Remove("modelText"); row.AsObject().Remove("shortModelText"); row.AsObject().Remove("mark"); }
        foreach (var session in panel["sessions"]!.AsArray()) { session!.AsObject().Remove("vendor"); session.AsObject().Remove("mark"); }
        foreach (var request in state["approvals"]!.AsArray()) request!.AsObject().Remove("mark");
        var read = (State)EngineMessage.Parse(state.ToJsonString());
        Assert.IsEmpty(read.Panel.Marks);
        Assert.IsTrue(read.Panel.Agents.All(a => a.ModelText == a.Model && a.Mark == a.Vendor));
        Assert.IsTrue(read.Panel.Sessions.All(s => s.Vendor is null && s.Mark is null));
        Assert.IsTrue(read.Approvals.All(r => r.Mark == r.Vendor));
        var current = (State)EngineMessage.Parse(Line("engine-state.demo.json"));
        Assert.AreEqual("Current session", current.Panel.Agents[0].ModelText);
        Assert.IsTrue(current.Panel.Marks.Any(m => m.Vendor == "Codex" && m.Key == "ChatGPT"), "Codex is drawn with ChatGPT's mark");
    }

    [TestMethod]
    public void LinesTheShellMustRefuseAreRefused()
    {
        foreach (var line in new[]
        {
            "refresh please", "[1]", """{"v":2,"type":"state"}""", """{"type":"hello"}""", """{"v":"1","type":"hello"}""",
            """{"v":1,"type":"nap"}""", """{"v":1}""", """{"v":1,"type":"lock-held"}""", """{"v":1,"type":"error","message":7}""",
        })
            Assert.ThrowsExactly<ProtocolRejectedException>(() => EngineMessage.Parse(line), line);
        var state = JsonNode.Parse(Line("engine-state.demo.json"))!.AsObject();
        state["panel"]!["glow"]![0]!["level"] = "orange";
        Assert.ThrowsExactly<ProtocolRejectedException>(() => EngineMessage.Parse(state.ToJsonString()), "an unknown level");
        // A number out of range or a key given twice is refused like the rest, not thrown as .NET's own error.
        var hello = Line("engine-hello.json");
        StringAssert.Contains(hello, "\"minor\":1");
        Assert.ThrowsExactly<ProtocolRejectedException>(() => EngineMessage.Parse(hello.Replace("\"minor\":1", "\"minor\":99999999999")));
        Assert.ThrowsExactly<ProtocolRejectedException>(() => EngineMessage.Parse(hello.Replace("\"demo\":true", "\"demo\":true,\"demo\":false")));
    }

    /// <summary>The shared lines a reader must refuse whichever side it is on: those wrong in their envelope (the
    /// rest are shell commands the engine refuses for their fields).</summary>
    [TestMethod]
    public void TheSharedEnvelopeFaultsAreRefusedHereToo()
    {
        var envelope = new[] { "not-json.json", "array.json", "version-2.json", "version-missing.json", "version-text.json",
                               "type-missing.json", "type-unknown.json" };
        foreach (var name in envelope)
            Assert.ThrowsExactly<ProtocolRejectedException>(() => EngineMessage.Parse(Line(Path.Combine("invalid", name))), name);
    }

    [TestMethod]
    public void TheEventsAreRead()
    {
        var alert = (QuotaAlertEvent)EngineMessage.Parse(Line("engine-event-quota-alert.json"));
        Assert.AreEqual("exhaustion", alert.Alert);
        Assert.AreEqual(5_400, alert.TimeToExhaust);
        Assert.IsNotNull(alert.TimeToExhaustText);
        var credits = (ResetCreditsEvent)EngineMessage.Parse(Line("engine-event-reset-credits.json"));
        Assert.AreEqual(2, credits.Added);
        Assert.AreEqual("Codex", credits.Provider);
        Assert.AreEqual("Personal", credits.AccountLabel);
    }

    [TestMethod]
    public void QuestionsAndPlansAreRead()
    {
        var state = (State)EngineMessage.Parse(Line("engine-state.demo.json"));
        var question = state.Approvals.Single(a => a.Id == "demo-question");
        Assert.IsTrue(question.IsQuestion);
        Assert.HasCount(2, question.Questions);
        Assert.AreEqual("SQLite", question.Questions[0].Options[0].Label);
        var plan = state.Approvals.Single(a => a.Id == "demo-plan");
        Assert.IsTrue(plan.IsPlan);
        Assert.IsNotNull(plan.Plan);
        Assert.IsTrue(state.Panel.Sessions.Any(s => s.Phase == SessionPhase.WaitingForApproval && s.PhaseText == "Needs approval"));
    }

    /// <summary>The same report eight days on, Claude's live status off: Core's labels for a passed reset and those sessions.</summary>
    [TestMethod]
    public void TheLaterStateCarriesCoresLabels()
    {
        var state = (State)EngineMessage.Parse(Line("engine-state.later.json"));
        Assert.IsTrue(state.Panel.Agents.Any(a => a.ResetText == "Pending update"));
        Assert.IsTrue(state.Panel.Sessions.Any(s => s.PhaseText == "Live status off"));
    }

    [TestMethod]
    public void TheShellsMessagesAreItsFixturesByteForByte()
    {
        var written = new Dictionary<string, string>
        {
            ["shell-hello.json"] = ShellMessage.Hello("0.1.0"),
            ["shell-refresh.json"] = ShellMessage.Refresh(),
            ["shell-quit.json"] = ShellMessage.Quit(),
            ["shell-answer-allow.json"] = ShellMessage.Answer("demo-tests", ShellMessage.Decision.Allow),
            ["shell-answer-deny.json"] = ShellMessage.Answer("demo-tests", ShellMessage.Decision.Deny),
            ["shell-answer-always.json"] = ShellMessage.Answer("demo-tests", ShellMessage.Decision.AllowAlways),
            ["shell-answer-leave.json"] = ShellMessage.Answer("demo-tests", ShellMessage.Decision.Leave),
            ["shell-answer-question.json"] = ShellMessage.AnswerQuestions("demo-question", new Dictionary<string, (IReadOnlyList<string>, string?)>
            {
                ["Which database?"] = (["SQLite"], null),
                ["Anything else?"] = ([], "Keep the 用量 ledger"),
            }),
            ["shell-answer-plan.json"] = ShellMessage.ApprovePlan("demo-plan", acceptEdits: true),
            ["shell-answer-keep-planning.json"] = ShellMessage.KeepPlanning("demo-plan", "Split step 2"),
            ["shell-update-settings.json"] = ShellMessage.UpdateSettings(new JsonObject { ["language"] = "zh-Hans", ["approvalWaitMinutes"] = 5 }),
        };
        var present = Directory.GetFiles(Fixtures, "shell-*.json").Select(Path.GetFileName).ToHashSet();
        CollectionAssert.AreEquivalent(written.Keys.ToList(), present.ToList(), "every shell fixture is written here");
        foreach (var (name, line) in written)
        {
            Assert.EndsWith("\n", line, name);
            Assert.AreEqual(Line(name), line[..^1], name);
        }
    }
}
