// Where requests are shown, what the shell keeps of the engine's lines, and the engine connection, over the protocol's
// shared fixtures (windows/protocol/fixtures).
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD.Shell.Tests;

[TestClass]
public sealed class ShellTests
{
    static readonly string Fixtures = FindFixtures();

    static string FindFixtures()
    {
        for (var folder = new DirectoryInfo(AppContext.BaseDirectory); folder is not null; folder = folder.Parent)
        {
            var candidate = Path.Combine(folder.FullName, "windows", "protocol", "fixtures");
            if (Directory.Exists(candidate)) return candidate;
            candidate = Path.Combine(folder.FullName, "protocol", "fixtures");
            if (Directory.Exists(candidate)) return candidate;
        }
        throw new DirectoryNotFoundException("windows/protocol/fixtures");
    }

    static string Line(string name) => File.ReadAllText(Path.Combine(Fixtures, name)).TrimEnd('\n');

    // MARK: Requests and displays (docs/hud.md, Approvals)

    [TestMethod]
    public void ARequestStaysOnTheDisplayThePointerWasOnWhenItArrived()
    {
        var placement = new RequestPlacement();
        string[] displays = [@"\\.\DISPLAY1", @"\\.\DISPLAY2"];
        placement.Update(["a"], displays[0], displays);
        placement.Update(["a", "b"], displays[1], displays);
        Assert.AreEqual(displays[0], placement.DisplayOf("a"), "the pointer moving does not move a waiting request");
        Assert.AreEqual(displays[1], placement.DisplayOf("b"));
        placement.Update(["b"], displays[0], displays);
        Assert.IsNull(placement.DisplayOf("a"), "a settled request is forgotten");
    }

    [TestMethod]
    public void ARequestWhoseDisplayWentAwayMovesToThePointers()
    {
        var placement = new RequestPlacement();
        placement.Update(["a"], "two", ["one", "two"]);
        placement.Update(["a"], "one", ["one"]);
        Assert.AreEqual("one", placement.DisplayOf("a"));
    }

    [TestMethod]
    public void TheOldestRequestIsOpenUntilAnotherIsOpenedAndAnAnswerHandsOverToTheOldest()
    {
        var placement = new RequestPlacement();
        placement.Update(["old", "new", "newest"], "one", ["one", "two"]);
        Assert.AreEqual("old", placement.OpenRequest(["old", "new", "newest"]));
        placement.Open("newest", "two");
        Assert.AreEqual("newest", placement.OpenRequest(["old", "new", "newest"]));
        Assert.AreEqual("two", placement.DisplayOf("newest"), "opening a line brings the request to that display");
        Assert.AreEqual("old", placement.OpenRequest(["old", "new"]), "answered: whichever waited longest");
        Assert.IsNull(placement.OpenRequest([]));
        placement.Open("gone", "one");
        Assert.IsNull(placement.DisplayOf("gone"), "a request not waiting cannot be opened");
    }

    // MARK: What the shell keeps

    [TestMethod]
    public void TheModelKeepsTheLastHelloAndStateAndTheEventsInOrder()
    {
        var model = new ShellModel();
        var changes = 0;
        model.Changed += () => changes++;
        Assert.AreEqual("menu.quit", model.Text("menu.quit"), "before hello, the key itself");
        Assert.IsNull(model.Hover, "no hover before the first state: the island draws nothing then");
        model.Apply(EngineMessage.Parse(Line("engine-hello.json")));
        model.Apply(EngineMessage.Parse(Line("engine-state.demo.json")));
        model.Apply(EngineMessage.Parse(Line("engine-event-completion.json")));
        model.Apply(EngineMessage.Parse(Line("engine-event-quota-alert.json")));
        Assert.AreEqual(2, changes);
        Assert.AreEqual("Quit", model.Text("menu.quit"));
        Assert.AreEqual("unknown.key", model.Text("unknown.key"));
        Assert.IsNotNull(model.State);
        Assert.IsTrue(model.TryTakeEvent(out var first));
        Assert.IsInstanceOfType<CompletionEvent>(first);
        Assert.IsTrue(model.TryTakeEvent(out var second));
        Assert.IsInstanceOfType<QuotaAlertEvent>(second);
        Assert.IsFalse(model.TryTakeEvent(out _));
        model.Apply(EngineMessage.Parse(Line("engine-lock-held.json")));
        Assert.IsNotNull(model.LockHeld);
    }

    [TestMethod]
    public void TheHoverDelaysAreTheUsersSettings()
    {
        var model = new ShellModel();
        var state = Line("engine-state.demo.json")
            .Replace("\"hoverDelayMs\":400", "\"hoverDelayMs\":650").Replace("\"collapseDelayMs\":200", "\"collapseDelayMs\":90");
        model.Apply(EngineMessage.Parse(state));
        Assert.AreEqual(new HoverConfig(TimeSpan.FromMilliseconds(650), TimeSpan.FromMilliseconds(90)), model.Hover);
    }

    // MARK: The connection

    [TestMethod]
    public void TheConnectionSaysHelloPassesMessagesOnInOrderSkipsWhatItCannotTakeAndEndsOnce()
    {
        var lines = string.Join("\n", Line("engine-hello.json"), "not a message", Line("engine-state.demo.json"),
                                Line("engine-event-completion.json")) + "\n";
        var written = new StringWriter();
        using var connection = new EngineConnection(written, new StringReader(lines));
        var received = new List<object>();
        var rejected = new List<string>();
        var ended = new ManualResetEventSlim();
        var endings = 0;
        connection.Received += received.Add;
        connection.Rejected += rejected.Add;
        connection.Ended += status => { Interlocked.Increment(ref endings); ended.Set(); };
        connection.Start("9.9.9");
        Assert.IsTrue(ended.Wait(TimeSpan.FromSeconds(10)));
        Assert.AreEqual(ShellMessage.Hello("9.9.9"), written.ToString(), "hello is the shell's first line");
        CollectionAssert.AreEqual(new[] { typeof(EngineHello), typeof(State), typeof(CompletionEvent) },
                                  received.Select(m => m.GetType()).ToArray());
        Assert.HasCount(1, rejected);
        Assert.AreEqual(1, endings);
        connection.Send(ShellMessage.Refresh());
        connection.Quit(TimeSpan.Zero);
        StringAssert.EndsWith(written.ToString(), ShellMessage.Quit());
    }

    [TestMethod]
    public void AGoneEngineTakesNothingAndNothingThrows()
    {
        var input = new StringWriter();
        input.Dispose();
        using var connection = new EngineConnection(input, new StringReader(""));
        connection.Send(ShellMessage.Refresh());
        connection.Quit(TimeSpan.Zero);
    }
}
