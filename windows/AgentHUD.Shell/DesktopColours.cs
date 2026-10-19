// Colours the shell draws as the macOS Desktop draws them, presentation the Desktop keeps and Core does not: the models'
// palette (Sources/AgentHUDDesktop/Theme/AgentPalette.swift, by Core's palette index), the levels' colours on the dark HUD
// (Theme/StatusPalette.swift) and the island's alert accents (Notch/Alerts/IslandAlert.swift). DesktopColoursTests holds each to those sources.
namespace AgentHUD.Shell;

public static class DesktopColours
{
    /// <summary>AgentPalette.colors, for the dark HUD.</summary>
    public static readonly uint[] Palette = [0xc084fc, 0x60a5fa, 0x2dd4bf, 0xfb923c, 0xf472b6, 0xa3e635];

    /// <summary>AgentPalette.lightColors, for a light surface.</summary>
    public static readonly uint[] LightPalette = [0x9333ea, 0x2563eb, 0x0d9488, 0xea580c, 0xdb2777, 0x4d7c0f];

    /// <summary>StatusPalette's levels on the dark HUD (ok, warning, critical) and the grey of no level.</summary>
    public const uint Ok = 0x3ddc84, Warning = 0xffd23f, Critical = 0xff453a, Idle = 0x9a9aa0;

    /// <summary>IslandAlert's accents: a reply, other news, a warning.</summary>
    public const uint TurnAccent = 0x82aaff, CalmAccent = 0x6cd8ac, WarningAccent = 0xe9a16d;

    /// <summary>The palette's colour at <paramref name="index"/>, wrapping as AgentPalette.color(index:light:) does.</summary>
    public static uint PaletteColour(int index, bool light)
    {
        var table = light ? LightPalette : Palette;
        return table[((index % table.Length) + table.Length) % table.Length];
    }
}
