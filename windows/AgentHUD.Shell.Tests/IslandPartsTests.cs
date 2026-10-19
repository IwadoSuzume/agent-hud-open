// Which pieces the island shows (IslandParts, the Desktop's ScreenHUD): a waiting request never opens the panel by
// itself (M7 review round 1).
using AgentHUD.Shell;

namespace AgentHUD.Shell.Tests;

[TestClass]
public sealed class IslandPartsTests
{
    [TestMethod]
    public void AWaitingRequestHoldsItsLineAndOpensNothing()
    {
        var parts = IslandParts.At(open: false, resting: false, holdsRequest: true, hasEvent: false);
        Assert.IsFalse(parts.Panel, "no answers are offered unasked");
        Assert.IsTrue(parts.RequestLine);
        Assert.IsTrue(parts.Marks, "the marks stay beside the line");
    }

    [TestMethod]
    public void HoveringOpensThePanelInPlaceOfTheLine()
    {
        var parts = IslandParts.At(open: true, resting: false, holdsRequest: true, hasEvent: false);
        Assert.IsTrue(parts.Panel);
        Assert.IsFalse(parts.RequestLine);
        Assert.IsFalse(parts.EventLine);
        Assert.IsTrue(parts.Marks, "a dock keeps its marks over its open panel");
    }

    [TestMethod]
    public void ARequestsLineComesBeforeNews()
    {
        var parts = IslandParts.At(open: false, resting: false, holdsRequest: true, hasEvent: true);
        Assert.IsTrue(parts.RequestLine);
        Assert.IsFalse(parts.EventLine);
    }

    [TestMethod]
    public void NewsAloneTakesTheMarksPlace()
    {
        var parts = IslandParts.At(open: false, resting: false, holdsRequest: false, hasEvent: true);
        Assert.IsTrue(parts.EventLine);
        Assert.IsFalse(parts.Marks);
        Assert.IsFalse(parts.Panel);
    }

    [TestMethod]
    public void AtRestOnlyTheMarksShow()
    {
        Assert.AreEqual(new IslandParts(false, false, false, true), IslandParts.At(open: true, resting: true, holdsRequest: true, hasEvent: false));
        Assert.AreEqual(new IslandParts(false, false, false, true), IslandParts.At(open: false, resting: false, holdsRequest: false, hasEvent: false));
    }
}
