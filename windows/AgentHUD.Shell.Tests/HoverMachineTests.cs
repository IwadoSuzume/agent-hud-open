// The macOS Desktop's HoverMachineTests (Tests/AgentHUDDesktopTests/Notch/HoverMachineTests.swift), case for case, so
// the Windows island opens and closes exactly as the Mac's does.
using AgentHUD.Shell;

namespace AgentHUD.Shell.Tests;

[TestClass]
public sealed class HoverMachineTests
{
    static readonly HoverConfig Config = new(TimeSpan.FromSeconds(0.4), TimeSpan.FromSeconds(0.2));
    static readonly DateTimeOffset T0 = DateTimeOffset.FromUnixTimeSeconds(1_000);
    static readonly HoverMachine Collapsed = new(HoverState.Collapsed);
    static readonly HoverMachine Open = new(HoverState.Open);

    static DateTimeOffset At(double seconds) => T0.AddSeconds(seconds);

    [TestMethod]
    public void EnterSchedulesOpenAfterDelay()
    {
        var t = Collapsed.Reduce(new HoverEvent.PointerEntered(T0), Config);
        Assert.AreEqual(new HoverMachine(HoverState.Opening, At(0.4)), t.Machine);
        Assert.AreEqual(At(0.4), t.Deadline);
        Assert.IsFalse(t.Machine.IsOpen);
    }

    [TestMethod]
    public void TimerOpens()
    {
        var opening = Collapsed.Reduce(new HoverEvent.PointerEntered(T0), Config).Machine;
        var t = opening.Reduce(new HoverEvent.TimerFired(At(0.4)), Config);
        Assert.AreEqual(HoverState.Open, t.Machine.State);
        Assert.IsNull(t.Deadline);
        Assert.IsTrue(t.Machine.IsOpen);
    }

    [TestMethod]
    public void EarlyTimerIsIgnored()
    {
        var opening = Collapsed.Reduce(new HoverEvent.PointerEntered(T0), Config).Machine;
        var t = opening.Reduce(new HoverEvent.TimerFired(At(0.1)), Config);
        Assert.AreEqual(opening, t.Machine);
        Assert.AreEqual(At(0.4), t.Deadline, "An early callback must rearm the pending open");
    }

    [TestMethod]
    public void EarlyCollapseTimerKeepsItsDeadline()
    {
        var closing = Open.Reduce(new HoverEvent.PointerExited(T0), Config).Machine;
        var early = closing.Reduce(new HoverEvent.TimerFired(At(0.1)), Config);
        Assert.AreEqual(closing, early.Machine);
        Assert.AreEqual(At(0.2), early.Deadline);
        Assert.AreEqual(HoverState.Collapsed, early.Machine.Reduce(new HoverEvent.TimerFired(At(0.2)), Config).Machine.State);
    }

    [TestMethod]
    public void ExitWhileOpeningCancels()
    {
        var opening = Collapsed.Reduce(new HoverEvent.PointerEntered(T0), Config).Machine;
        var t = opening.Reduce(new HoverEvent.PointerExited(At(0.1)), Config);
        Assert.AreEqual(HoverState.Collapsed, t.Machine.State);
        Assert.IsNull(t.Deadline);
    }

    [TestMethod]
    public void ExitFromOpenSchedulesCollapse()
    {
        var t = Open.Reduce(new HoverEvent.PointerExited(T0), Config);
        Assert.AreEqual(new HoverMachine(HoverState.Closing, At(0.2)), t.Machine);
        Assert.IsTrue(t.Machine.IsOpen, "content stays visible while closing");
        Assert.AreEqual(HoverState.Collapsed, t.Machine.Reduce(new HoverEvent.TimerFired(At(0.2)), Config).Machine.State);
    }

    [TestMethod]
    public void ReenterWhileClosingReopensImmediately()
    {
        var closing = Open.Reduce(new HoverEvent.PointerExited(T0), Config).Machine;
        var t = closing.Reduce(new HoverEvent.PointerEntered(At(0.1)), Config);
        Assert.AreEqual(HoverState.Open, t.Machine.State);
        Assert.IsNull(t.Deadline);
    }

    [TestMethod]
    public void ForceEvents()
    {
        Assert.AreEqual(HoverState.Open, Collapsed.Reduce(new HoverEvent.ForceOpen(), Config).Machine.State);
        Assert.AreEqual(HoverState.Collapsed, Open.Reduce(new HoverEvent.ForceCollapse(), Config).Machine.State);
    }

    [TestMethod]
    public void ZeroDelayStillGoesThroughTimer()
    {
        var zero = new HoverConfig(TimeSpan.Zero, TimeSpan.Zero);
        var t = Collapsed.Reduce(new HoverEvent.PointerEntered(T0), zero);
        Assert.AreEqual(T0, t.Deadline);
        Assert.AreEqual(HoverState.Open, t.Machine.Reduce(new HoverEvent.TimerFired(T0), zero).Machine.State);
    }
}
