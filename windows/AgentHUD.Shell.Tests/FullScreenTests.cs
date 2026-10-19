using AgentHUD.Shell;

namespace AgentHUD.Shell.Tests;

[TestClass]
public sealed class FullScreenTests
{
    static readonly ScreenRect Display = new(0, 0, 2560, 1440);

    [TestMethod]
    public void AWindowCoversADisplayOnlyWhenItReachesEveryEdge()
    {
        Assert.IsTrue(FullScreen.Covers(new ScreenRect(0, 0, 2560, 1440), Display));
        Assert.IsTrue(FullScreen.Covers(new ScreenRect(-8, -8, 2568, 1448), Display), "a maximised-style overhang still covers");
        Assert.IsFalse(FullScreen.Covers(new ScreenRect(0, 0, 2560, 1392), Display), "a window above the taskbar does not");
        Assert.IsFalse(FullScreen.Covers(new ScreenRect(2560, 0, 5120, 1440), Display), "another display's window does not");
    }

    [TestMethod]
    public void TheHudStepsAsideForAFullScreenAppButNeverHidesARequest()
    {
        Assert.IsFalse(FullScreen.ShowsHud(frontCoversDisplay: true, frontIsDesktopOrHud: false, requestWaitsHere: false));
        Assert.IsTrue(FullScreen.ShowsHud(frontCoversDisplay: true, frontIsDesktopOrHud: false, requestWaitsHere: true));
        Assert.IsTrue(FullScreen.ShowsHud(frontCoversDisplay: true, frontIsDesktopOrHud: true, requestWaitsHere: false),
                      "the desktop covers the display too, and is no app");
        Assert.IsTrue(FullScreen.ShowsHud(frontCoversDisplay: false, frontIsDesktopOrHud: false, requestWaitsHere: false));
    }
}
