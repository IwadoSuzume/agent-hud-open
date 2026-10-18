using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Threading;
using AgentHUD.Protocol;
using AgentHUD.Shell;
using Microsoft.Win32;

namespace AgentHUD;

/// <summary>The shell: starts the engine (`agenthud-engine --serve`), keeps one island per display, a tray icon, and
/// sends the user's choices back. Options: `--demo` (the engine's example data), `--language en|zh-Hans`,
/// `--engine &lt;path&gt;`, `--snapshot &lt;folder&gt;` (the G5 smoke test: draws the HUD into PNG files and quits).</summary>
public partial class App : Application
{
    readonly ShellModel model = new();
    readonly RequestPlacement placement = new();
    readonly List<IslandWindow> islands = [];
    EngineConnection? engine;
    Tray? tray;
    string? snapshotFolder;
    bool quitting;
    volatile string? lastComplaint;

    public static string ShellVersion =>
        Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.0.0";

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var arguments = new List<string>();
        var enginePath = EngineConnection.DefaultEnginePath;
        for (var i = 0; i < e.Args.Length; i++)
        {
            switch (e.Args[i])
            {
                case "--demo": arguments.Add("--demo"); break;
                case "--language" when i + 1 < e.Args.Length: arguments.AddRange(["--language", e.Args[++i]]); break;
                case "--engine" when i + 1 < e.Args.Length: enginePath = e.Args[++i]; break;
                case "--snapshot" when i + 1 < e.Args.Length:
                    snapshotFolder = Path.GetFullPath(e.Args[++i]);
                    if (!arguments.Contains("--demo")) arguments.Add("--demo");
                    break;
                default:
                    Console.Error.WriteLine($"AgentHUD: unknown option {e.Args[i]}");
                    Shutdown(2);
                    return;
            }
        }

        try { engine = EngineConnection.Launch(enginePath, arguments); }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            MessageBox.Show($"Agent HUD could not start its engine ({enginePath}): {error.Message}", "Agent HUD",
                            MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
            return;
        }
        engine.Received += message => Dispatcher.BeginInvoke(() => model.Apply(message));
        engine.Rejected += why => Dispatcher.BeginInvoke(() => Log($"engine line refused: {why}"));
        engine.Ended += status => Dispatcher.BeginInvoke(() => EngineEnded(status));
        engine.Complained += line =>
        {
            lastComplaint = line;
            Log($"engine: {line}");
        };
        model.Changed += OnModelChanged;

        BuildIslands();
        SystemEvents.DisplaySettingsChanged += OnDisplaysChanged;
        if (snapshotFolder is null) tray = new Tray(model, OpenSettings, OpenStatistics, Quit);
        engine.Start(ShellVersion);
        if (snapshotFolder is not null) Snapshot.Begin(this, model, islands, snapshotFolder);
    }

    void OnModelChanged()
    {
        if (model.LockHeld is { } held && !quitting)
        {
            quitting = true;
            if (snapshotFolder is null)
            {
                MessageBox.Show(held.Holder is { } holder ? $"Agent HUD is already running ({holder})." : "Agent HUD is already running.",
                                "Agent HUD", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            Shutdown(3);
            return;
        }
        PlaceRequests();
        tray?.Refresh();
        RefreshIslands();
    }

    /// <summary>New requests go to the display the pointer is on (docs/hud.md, Approvals).</summary>
    void PlaceRequests()
    {
        var monitors = islands.Select(i => i.Monitor).ToList();
        if (monitors.Count == 0) return;
        var pointer = monitors.FirstOrDefault(m => m.Primary) ?? monitors[0];
        if (Native.GetCursorPos(out var cursor))
        {
            pointer = monitors.FirstOrDefault(m => cursor.X >= m.Bounds.Left && cursor.X < m.Bounds.Right
                                                   && cursor.Y >= m.Bounds.Top && cursor.Y < m.Bounds.Bottom) ?? pointer;
        }
        placement.Update((model.State?.Approvals ?? []).Select(r => r.Id), pointer.Device,
                         monitors.Select(m => m.Device).ToList());
    }

    void RefreshIslands()
    {
        foreach (var island in islands) island.View.Refresh();
    }

    void OnDisplaysChanged(object? sender, EventArgs e) => Dispatcher.BeginInvoke(BuildIslands, DispatcherPriority.Background);

    /// <summary>One island per display, made again when displays come, go or change (hot-plug, DPI, arrangement).</summary>
    void BuildIslands()
    {
        var monitors = Native.Monitors();
        // A snapshot on a machine that reports no display (a service session) draws on a stand-in 1920 x 1080 one.
        if (monitors.Count == 0 && snapshotFolder is not null)
        {
            var area = new Native.RECT { Left = 0, Top = 0, Right = 1920, Bottom = 1080 };
            monitors.Add(new Native.Monitor(@"\\.\SNAPSHOT", area, area, 1.0, true));
        }
        foreach (var island in islands.Where(i => monitors.All(m => m.Device != i.Monitor.Device)).ToList())
        {
            island.Close();
            islands.Remove(island);
        }
        foreach (var monitor in monitors)
        {
            if (islands.FirstOrDefault(i => i.Monitor.Device == monitor.Device) is { } existing)
            {
                existing.Place(monitor);
                continue;
            }
            var made = new IslandWindow(model, placement, monitor, Send, RefreshIslands);
            islands.Add(made);
            made.Show();
        }
        // A request whose display went away moves to the pointer's.
        PlaceRequests();
        RefreshIslands();
    }

    internal void Send(string line) => engine?.Send(line);

    void OpenSettings() => Log("Settings window: M7 step 3");

    void OpenStatistics() => Log("Statistics window: M7 step 4");

    internal void Quit() => Quit(0);

    /// <summary>Asks the engine to quit (it lets waiting approvals go back to their clients), then ends with
    /// <paramref name="status"/>.</summary>
    internal void Quit(int status)
    {
        if (quitting) return;
        quitting = true;
        engine?.Quit(TimeSpan.FromSeconds(3));
        Shutdown(status);
    }

    void EngineEnded(int? status)
    {
        if (quitting) return;
        quitting = true;
        Log($"engine ended ({status?.ToString() ?? "unknown status"})");
        // The engine owns the lock, the hooks and the approvals: without it there is nothing to show.
        if (status == 3) { Shutdown(3); return; }
        var why = lastComplaint is { } complaint ? Environment.NewLine + complaint : "";
        if (snapshotFolder is null)
            MessageBox.Show($"Agent HUD's engine stopped (status {status?.ToString() ?? "unknown"}).{why}", "Agent HUD",
                            MessageBoxButton.OK, MessageBoxImage.Warning);
        else
            Console.Error.WriteLine($"AgentHUD: the engine stopped (status {status?.ToString() ?? "unknown"}).{why}");
        Shutdown(1);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        SystemEvents.DisplaySettingsChanged -= OnDisplaysChanged;
        tray?.Dispose();
        foreach (var island in islands) island.Close();
        if (!quitting) engine?.Quit(TimeSpan.FromSeconds(3));
        engine?.Dispose();
        base.OnExit(e);
    }

    internal static void Log(string line)
    {
        try { System.Diagnostics.Debug.WriteLine($"[AgentHUD] {line}"); }
        catch (InvalidOperationException) { }
    }
}
