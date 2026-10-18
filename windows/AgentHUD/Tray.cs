// The notification-area icon (TASK.md §3: the menu bar item's stand-in) and its menu, in the engine's words
// (ShellStrings `menu.*`).
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using AgentHUD.Shell;

namespace AgentHUD;

sealed class Tray : IDisposable
{
    readonly ShellModel model;
    readonly NotifyIcon icon;
    readonly IntPtr iconHandle;
    readonly ToolStripMenuItem settings, statistics, quit;

    public Tray(ShellModel model, Action openSettings, Action openStatistics, Action quitApp)
    {
        this.model = model;
        settings = new ToolStripMenuItem("", null, (_, _) => openSettings());
        statistics = new ToolStripMenuItem("", null, (_, _) => openStatistics());
        quit = new ToolStripMenuItem("", null, (_, _) => quitApp());
        var menu = new ContextMenuStrip();
        menu.Items.AddRange([statistics, settings, new ToolStripSeparator(), quit]);
        using var picture = Draw();
        iconHandle = picture.GetHicon();
        icon = new NotifyIcon { Icon = Icon.FromHandle(iconHandle), Text = "Agent HUD", ContextMenuStrip = menu, Visible = true };
        Refresh();
    }

    public void Refresh()
    {
        settings.Text = model.Text("menu.settings");
        statistics.Text = model.Text("menu.statistics");
        quit.Text = model.Text("menu.quit");
    }

    /// <summary>A small island on a dark tile: the HUD's own shape, drawn here rather than shipped as a file.</summary>
    static Bitmap Draw()
    {
        var bitmap = new Bitmap(32, 32);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Color.Transparent);
        using var tile = Rounded(new RectangleF(1, 1, 30, 30), 7);
        using var ground = new SolidBrush(Color.FromArgb(255, 24, 24, 27));
        g.FillPath(ground, tile);
        using var island = Rounded(new RectangleF(6, 9, 20, 9), 4.5f);
        g.FillPath(Brushes.White, island);
        using var glow = new SolidBrush(Color.FromArgb(255, 48, 209, 88));
        g.FillEllipse(glow, 13.5f, 21, 5, 5);
        return bitmap;
    }

    static GraphicsPath Rounded(RectangleF r, float radius)
    {
        var path = new GraphicsPath();
        var d = radius * 2;
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    [DllImport("user32.dll")]
    static extern bool DestroyIcon(IntPtr icon);

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
        DestroyIcon(iconHandle);
    }
}
