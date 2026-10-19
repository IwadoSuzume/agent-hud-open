// The appearance setting as the windows draw it (Appearance).
using AgentHUD.Shell;

namespace AgentHUD.Shell.Tests;

[TestClass]
public sealed class AppearanceTests
{
    [TestMethod]
    public void LightAndDarkAreThemselvesAndSystemFollowsWindows()
    {
        Assert.IsFalse(Appearance.IsDark("light", systemUsesLight: false));
        Assert.IsTrue(Appearance.IsDark("dark", systemUsesLight: true));
        Assert.IsTrue(Appearance.IsDark("system", systemUsesLight: false));
        Assert.IsFalse(Appearance.IsDark("system", systemUsesLight: true));
        Assert.IsFalse(Appearance.IsDark(null, systemUsesLight: true), "before the first state the window follows Windows");
    }
}
