// `--snapshot <folder>` (TASK.md G5): with the engine's demo data, draws the island at rest and open (requests
// included) off the screen's pixels into PNG files, writes their sizes to snapshot.txt, and quits with 0; with 1 when
// no state came within 30 s or a picture came out empty.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD;

static class Snapshot
{
    public static void Begin(App app, ShellModel model, List<IslandWindow> islands, string folder, string? feed, Action<string> send)
    {
        var askedForStatistics = false;
        var started = DateTime.UtcNow;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        timer.Tick += (_, _) =>
        {
            var ready = model.State is { } state && state.Approvals.Count > 0 && model.Hello is not null;
            if (!ready)
            {
                if (DateTime.UtcNow - started > TimeSpan.FromSeconds(30)) { timer.Stop(); Finish(app, 1, "no demo state within 30 s"); }
                return;
            }
            // The statistics window's figures come on request: asked once, and drawn when they have come.
            if (!askedForStatistics) { askedForStatistics = true; send(ShellMessage.Statistics()); }
            if (model.Statistics is null && DateTime.UtcNow - started < TimeSpan.FromSeconds(30)) return;
            timer.Stop();
            try { Finish(app, Draw(islands.First(), folder, Feed(feed)), null); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException
                                                or ArgumentException)
            {
                Finish(app, 1, error.Message);
            }
        };
        timer.Start();
    }

    /// <summary>The events of `--feed` (the protocol's `engine-event-*.json` fixtures, written by the engine), read as the
    /// engine's lines are, by kind.</summary>
    static Dictionary<string, HudEvent> Feed(string? folder)
    {
        var read = new Dictionary<string, HudEvent>();
        if (folder is null) return read;
        foreach (var file in Directory.GetFiles(folder, "engine-event-*.json"))
        {
            if (EngineMessage.Parse(File.ReadAllText(file).TrimEnd((char)10)) is not HudEvent hudEvent) continue;
            // An event the engine sent no words for cannot be drawn, and must not pass as an empty card.
            if (hudEvent.Copy is null) throw new InvalidOperationException($"{Path.GetFileName(file)} carries no copy (protocol 1.2)");
            read[hudEvent switch { QuotaAlertEvent => "quota", ResetCreditsEvent => "credits", _ => "reply" }] = hudEvent;
        }
        return read;
    }

    static int Draw(IslandWindow island, string folder, Dictionary<string, HudEvent> feed)
    {
        Directory.CreateDirectory(folder);
        var report = new StringBuilder();
        var status = 0;
        var pictures = new List<(string Name, bool Resting, bool Usage, string? Request, HudEvent? Event, bool Open)>
        {
            ("island-rest", true, false, null, null, false), ("island-open", false, false, null, null, true),
            ("island-usage", false, true, null, null, true),
            ("card-question", false, false, "demo-question", null, true), ("card-plan", false, false, "demo-plan", null, true),
        };
        foreach (var (kind, hudEvent) in feed)
        {
            pictures.Add(($"event-{kind}-line", false, false, null, hudEvent, false));
            pictures.Add(($"event-{kind}-card", false, false, null, hudEvent, true));
        }
        foreach (var (name, resting, usage, request, hudEvent, open) in pictures)
        {
            island.View.Resting = resting;
            island.View.UsageOnly = usage;
            island.View.PictureEvent = hudEvent;
            if (request is not null)
            {
                // The card asked for, or no picture: a request the demo does not hold must not pass as another's card.
                if (island.View.Waits(request) == false) { report.AppendLine($"{name} no request {request}"); status = 1; continue; }
                island.OpenRequestForPicture(request);
            }
            island.ForceOpen(open);
            island.UpdateLayout();
            // Let the bindings and a render pass catch up before the picture is taken.
            island.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
            island.UpdateLayout();
            var element = island.Island;
            var root = (FrameworkElement)island.Content;
            if (element.ActualWidth < 1 || element.ActualHeight < 1) { report.AppendLine($"{name} 0x0"); status = 1; continue; }
            // The window's whole content drawn at 2x, as a Retina snapshot is on macOS, then cut to the island's own
            // bounds in it: what the window shows, pixel for pixel.
            var whole = new RenderTargetBitmap((int)Math.Ceiling(root.ActualWidth * 2), (int)Math.Ceiling(root.ActualHeight * 2),
                                               192, 192, PixelFormats.Pbgra32);
            whole.Render(root);
            var bounds = element.TransformToAncestor(root).TransformBounds(new Rect(element.RenderSize));
            var cut = new Int32Rect((int)Math.Floor(bounds.X * 2), (int)Math.Floor(bounds.Y * 2),
                                    Math.Min((int)Math.Ceiling(bounds.Width * 2), whole.PixelWidth - (int)Math.Floor(bounds.X * 2)),
                                    Math.Min((int)Math.Ceiling(bounds.Height * 2), whole.PixelHeight - (int)Math.Floor(bounds.Y * 2)));
            BitmapSource bitmap = new CroppedBitmap(whole, cut);
            if (IsBlank(bitmap)) { report.AppendLine($"{name} blank"); status = 1; }
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (var file = File.Create(Path.Combine(folder, name + ".png"))) encoder.Save(file);
            report.AppendLine($"{name} {bitmap.PixelWidth}x{bitmap.PixelHeight}");
        }
        status |= DrawWindow(new SettingsWindow(island.View.Model, _ => { }), "settings", folder, report);
        status |= island.View.Model.Statistics is null ? Missing("statistics", report)
                : DrawWindow(new StatisticsWindow(island.View.Model, _ => { }), "statistics", folder, report);
        File.WriteAllText(Path.Combine(folder, "snapshot.txt"), report.ToString());
        return status;
    }

    static int Missing(string name, StringBuilder report)
    {
        report.AppendLine($"{name} missing");
        return 1;
    }

    /// <summary>A normal window (settings, statistics), its content on a solid ground (the backdrop is the desktop's,
    /// which a picture has none of), off the screen's pixels at 2x.</summary>
    static int DrawWindow(Window settings, string name, string folder, StringBuilder report)
    {
        settings.Left = -20000;
        settings.Top = -20000;
        settings.ShowActivated = false;
        try
        {
            settings.Show();
            settings.UpdateLayout();
            settings.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);
            var content = (FrameworkElement)settings.Content;
            if (content.ActualWidth < 1 || content.ActualHeight < 1) { report.AppendLine($"{name} 0x0"); return 1; }
            // The content and its margins: it is drawn where it stands in the window.
            var size = new Size(content.ActualWidth + content.Margin.Left + content.Margin.Right,
                                content.ActualHeight + content.Margin.Top + content.Margin.Bottom);
            var bitmap = new RenderTargetBitmap((int)Math.Ceiling(size.Width * 2), (int)Math.Ceiling(size.Height * 2),
                                                192, 192, PixelFormats.Pbgra32);
            var ground = new DrawingVisual();
            using (var context = ground.RenderOpen())
                context.DrawRectangle(new SolidColorBrush(Color.FromRgb(0x20, 0x20, 0x20)), null, new Rect(size));
            bitmap.Render(ground);
            bitmap.Render(content);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (var file = File.Create(Path.Combine(folder, name + ".png"))) encoder.Save(file);
            report.AppendLine($"{name} {bitmap.PixelWidth}x{bitmap.PixelHeight}");
            return IsBlank(bitmap) ? 1 : 0;
        }
        finally { settings.Close(); }
    }

    /// <summary>True when every pixel is the same (nothing was drawn).</summary>
    static bool IsBlank(BitmapSource bitmap)
    {
        var stride = bitmap.PixelWidth * 4;
        var pixels = new byte[stride * bitmap.PixelHeight];
        bitmap.CopyPixels(pixels, stride, 0);
        var first = BitConverter.ToInt32(pixels, 0);
        for (var i = 4; i < pixels.Length; i += 4) if (BitConverter.ToInt32(pixels, i) != first) return false;
        return true;
    }

    static void Finish(App app, int status, string? why)
    {
        if (why is not null) Console.Error.WriteLine($"AgentHUD --snapshot: {why}");
        app.Quit(status);
    }
}
