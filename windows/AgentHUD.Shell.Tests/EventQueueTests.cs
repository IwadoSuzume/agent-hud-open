// The island's news (EventQueue, the Desktop's IslandAlertQueue rules for events that are not requests).
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD.Shell.Tests;

[TestClass]
public sealed class EventQueueTests
{
    static readonly DateTimeOffset T0 = DateTimeOffset.FromUnixTimeSeconds(1_000);
    static readonly EventCopy Words = new("Claude", "Current session", "Claude · Current session", "Empty", "This window is empty.",
                                          "running low", true, 100, [], null);

    static QuotaAlertEvent Alert(string id, EventCopy? copy = null) =>
        new(id, "exhaustion", "a", "Claude", "window.session", false, null, null, [], copy ?? Words, "Claude");

    static CompletionEvent Reply(string id) =>
        new(id, "s1", "Claude", "Task", "m", null, T0, new EventCopy("Claude", null, null, "New reply", "Task", null, false, null, [], null), "Claude");

    [TestMethod]
    public void OneEventAtATimeTheRestInArrivalOrderEachForFourSeconds()
    {
        var queue = new EventQueue();
        queue.Add(Alert("a"), false, "one", T0);
        queue.Add(Alert("b"), false, "two", T0.AddSeconds(1));
        Assert.AreEqual("a", queue.Current?.Id);
        Assert.AreEqual("one", queue.Display, "on the pointer's display when it came up");
        Assert.AreEqual(T0 + EventQueue.VisibleFor, queue.ExpiresAt);
        queue.Tick(false, "two", T0.AddSeconds(3.9));
        Assert.AreEqual("a", queue.Current?.Id, "not yet due");
        queue.Tick(false, "two", T0.AddSeconds(4));
        Assert.AreEqual("b", queue.Current?.Id);
        Assert.AreEqual("two", queue.Display);
        queue.Tick(false, "two", T0.AddSeconds(8));
        Assert.IsNull(queue.Current);
    }

    [TestMethod]
    public void ThePointerHoldsTheEventAndItsTimeStartsAgainWhenThePointerLeaves()
    {
        var queue = new EventQueue();
        queue.Add(Alert("a"), false, "one", T0);
        queue.Hold(true, T0.AddSeconds(1));
        Assert.IsNull(queue.ExpiresAt);
        queue.Tick(false, "one", T0.AddSeconds(60));
        Assert.AreEqual("a", queue.Current?.Id, "never while the pointer is over it");
        queue.Hold(false, T0.AddSeconds(61));
        Assert.AreEqual(T0.AddSeconds(65), queue.ExpiresAt);
        queue.Tick(false, "one", T0.AddSeconds(65));
        Assert.IsNull(queue.Current);
    }

    [TestMethod]
    public void WhileARequestWaitsQuotaNewsIsDroppedAndRepliesWait()
    {
        var queue = new EventQueue();
        queue.Add(Alert("news"), true, "one", T0);
        queue.Add(Reply("reply"), true, "one", T0);
        Assert.IsNull(queue.Current, "a request holds the island");
        Assert.HasCount(1, queue.Pending);
        Assert.AreEqual("reply", queue.Pending[0].Id);
        queue.Tick(true, "one", T0.AddSeconds(10));
        Assert.IsNull(queue.Current);
        queue.Tick(false, "two", T0.AddSeconds(11));
        Assert.AreEqual("reply", queue.Current?.Id, "the reply comes up once the requests are settled");
        Assert.AreEqual("two", queue.Display);
    }

    [TestMethod]
    public void AnEventWithoutWordsIsNotShownAndADismissedOneGoesAtOnce()
    {
        var queue = new EventQueue();
        queue.Add(new QuotaAlertEvent("old", "reset", "a", "Claude", "m", false, null, null, [], null, null), false, "one", T0);
        Assert.IsNull(queue.Current, "a 1.1 engine's event: the shell cannot word it");
        queue.Add(Alert("a"), false, "one", T0);
        queue.Add(Alert("b"), false, "one", T0);
        queue.Dismiss();
        Assert.IsNull(queue.Current);
        queue.Tick(false, "one", T0.AddSeconds(0.1));
        Assert.AreEqual("b", queue.Current?.Id);
    }
}
