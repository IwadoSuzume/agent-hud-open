// A full-screen app keeps its display to itself (TASK.md M7: the HUD does not cover it, optional): the window in front
// covers the whole display. The HUD on that display steps aside, unless a request of the user waits there, which is
// never hidden (docs/hud.md: nothing silences a request).
namespace AgentHUD.Shell;

public readonly record struct ScreenRect(int Left, int Top, int Right, int Bottom);

public static class FullScreen
{
    /// <summary>The window in front covers the display: its rectangle reaches every edge of the display's.</summary>
    public static bool Covers(ScreenRect window, ScreenRect display) =>
        window.Left <= display.Left && window.Top <= display.Top && window.Right >= display.Right && window.Bottom >= display.Bottom;

    /// <summary>A full-screen app: a window with no caption that covers the display. A maximised window keeps its caption,
    /// and covers a display whose taskbar hides itself without being full screen.</summary>
    public static bool IsFullScreen(ScreenRect window, bool hasCaption, ScreenRect display) => !hasCaption && Covers(window, display);

    /// <summary>Whether a display's HUD stays shown: always while a request waits on it, else unless a full-screen app
    /// (not the desktop, not the HUD itself) is in front of it.</summary>
    public static bool ShowsHud(bool frontCoversDisplay, bool frontIsDesktopOrHud, bool requestWaitsHere) =>
        requestWaitsHere || !frontCoversDisplay || frontIsDesktopOrHud;
}
