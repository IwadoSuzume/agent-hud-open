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
using AgentHUD.Shell;

namespace AgentHUD;

static class Snapshot
{
    public static void Begin(App app, ShellModel model, List<IslandWindow> islands, string folder)
    {
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
            timer.Stop();
            try { Finish(app, Draw(islands.First(), folder), null); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException
                                                or ArgumentException)
            {
                Finish(app, 1, error.Message);
            }
        };
        timer.Start();
    }

    static int Draw(IslandWindow island, string folder)
    {
        Directory.CreateDirectory(folder);
        var report = new StringBuilder();
        var status = 0;
        foreach (var (name, resting, usage) in new[] { ("island-rest", true, false), ("island-open", false, false), ("island-usage", false, true) })
        {
            island.View.Resting = resting;
            island.View.UsageOnly = usage;
            island.ForceOpen(!resting);
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
        File.WriteAllText(Path.Combine(folder, "snapshot.txt"), report.ToString());
        return status;
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
