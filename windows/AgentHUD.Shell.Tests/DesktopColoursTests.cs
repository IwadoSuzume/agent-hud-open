// The shell's copies of the Desktop's colours, held to the Desktop's own sources as the engine's words are.
using System.Globalization;
using System.Text.RegularExpressions;
using AgentHUD.Shell;

namespace AgentHUD.Shell.Tests;

[TestClass]
public sealed class DesktopColoursTests
{
    static string Source(string relative)
    {
        for (var folder = new DirectoryInfo(AppContext.BaseDirectory); folder is not null; folder = folder.Parent)
        {
            var file = Path.Combine(folder.FullName, relative);
            if (File.Exists(file)) return File.ReadAllText(file);
        }
        throw new FileNotFoundException(relative);
    }

    static uint[] Hexes(string text) =>
        Regex.Matches(text, @"RGBA\(hex: 0x([0-9a-fA-F]{6})\)").Select(m => uint.Parse(m.Groups[1].Value, NumberStyles.HexNumber)).ToArray();

    [TestMethod]
    public void ThePaletteIsAgentPalettes()
    {
        var source = Source(Path.Combine("Sources", "AgentHUDDesktop", "Theme", "AgentPalette.swift"));
        var light = source.IndexOf("lightColors", StringComparison.Ordinal);
        CollectionAssert.AreEqual(Hexes(source[..light]), DesktopColours.Palette);
        CollectionAssert.AreEqual(Hexes(source[light..]), DesktopColours.LightPalette);
        Assert.AreEqual(DesktopColours.Palette[1], DesktopColours.PaletteColour(7, light: false), "the index wraps");
        Assert.AreEqual(DesktopColours.LightPalette[5], DesktopColours.PaletteColour(-1, light: true));
    }

    [TestMethod]
    public void TheLevelsAreStatusPalettes()
    {
        var source = Source(Path.Combine("Sources", "AgentHUDDesktop", "Theme", "StatusPalette.swift"));
        uint Named(string name) => uint.Parse(Regex.Match(source, "static let " + name + @" = RGBA\(hex: 0x([0-9a-fA-F]{6})\)").Groups[1].Value, NumberStyles.HexNumber);
        Assert.AreEqual(DesktopColours.Ok, Named("ok"));
        Assert.AreEqual(DesktopColours.Warning, Named("warning"));
        Assert.AreEqual(DesktopColours.Critical, Named("critical"));
        Assert.AreEqual(DesktopColours.Idle, Named("idle"));
    }

    [TestMethod]
    public void TheAccentsAreIslandAlerts()
    {
        var source = Source(Path.Combine("Sources", "AgentHUDDesktop", "Notch", "Alerts", "IslandAlert.swift"));
        uint Accent(string name) => uint.Parse(Regex.Match(source, name + @" = RGBA\(hex: 0x([0-9a-fA-F]{6})\)").Groups[1].Value, NumberStyles.HexNumber);
        Assert.AreEqual(DesktopColours.TurnAccent, Accent("turnAccent"));
        Assert.AreEqual(DesktopColours.CalmAccent, Accent("calmAccent"));
        Assert.AreEqual(DesktopColours.WarningAccent, Accent("warningAccent"));
    }
}
