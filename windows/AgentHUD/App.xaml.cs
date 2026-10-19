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
/// `--engine &lt;path&gt;`, `--show-settings`, `--show-stats`, `--snapshot &lt;folder&gt;` (the G5 smoke test: draws the HUD into PNG files and
/// quits; `--feed &lt;folder&gt;` gives it the protocol's event fixtures to draw).</summary>
public partial class App : Application
{
    readonly ShellModel model = new();
    readonly RequestPlacement placement = new();
    readonly Cards cards;
    readonly EventQueue events = new();
    DispatcherTimer? eventClock;
    string? feedFolder;
    readonly List<IslandWindow> islands = [];
    EngineConnection? engine;
    Tray? tray;
    string? snapshotFolder;
    bool quitting, demo, showSettings, showStats;
    volatile string? lastComplaint;

    public App() => cards = new Cards(model);

    public static string ShellVersion =>
        Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.0.0";

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
#pragma warning disable WPF0001 // ThemeMode: the Fluent theme, experimental in WPF's API but shipped and supported.
        // The normal windows' controls as Windows 11 draws them; the settings window then follows the appearance setting.
        ThemeMode = ThemeMode.Dark;
#pragma warning restore WPF0001
        var arguments = new List<string>();
        var enginePath = EngineConnection.DefaultEnginePath;
        for (var i = 0; i < e.Args.Length; i++)
        {
            switch (e.Args[i])
            {
                case "--demo": arguments.Add("--demo"); demo = true; break;
                case "--language" when i + 1 < e.Args.Length: arguments.AddRange(["--language", e.Args[++i]]); break;
                case "--engine" when i + 1 < e.Args.Length: enginePath = e.Args[++i]; break;
                case "--feed" when i + 1 < e.Args.Length: feedFolder = Path.GetFullPath(e.Args[++i]); break;
                case "--show-settings": showSettings = true; break;
                case "--show-stats": showStats = true; break;
                case "--snapshot" when i + 1 < e.Args.Length:
                    snapshotFolder = Path.GetFullPath(e.Args[++i]);
                    if (!arguments.Contains("--demo")) arguments.Add("--demo");
                    demo = true;
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
        model.EventArrived += OnEvent;
        eventClock = new DispatcherTimer(TimeSpan.FromMilliseconds(250), DispatcherPriority.Background, (_, _) => TickEvents(), Dispatcher);
        eventClock.Start();

        BuildIslands();
        SystemEvents.DisplaySettingsChanged += OnDisplaysChanged;
        if (snapshotFolder is null) tray = new Tray(model, OpenSettings, OpenStatistics, Quit);
        engine.Start(ShellVersion);
        TellDisplays();
        if (snapshotFolder is not null) Snapshot.Begin(this, model, islands, snapshotFolder, feedFolder, Send);
        // As the macOS app's `--show-settings`: the window once the engine has said hello (its words are the engine's).
        else if (showSettings || showStats) model.Changed += OpenSettingsOnce;
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
        FollowLaunchAtLogin();
    }

    /// <summary>New requests go to the display the pointer is on (docs/hud.md, Approvals).</summary>
    void PlaceRequests()
    {
        var monitors = islands.Select(i => i.Monitor).ToList();
        if (PointerDisplay() is not { } pointer) return;
        placement.Update((model.State?.Approvals ?? []).Select(r => r.Id), pointer,
                         monitors.Select(m => m.Device).ToList());
        cards.Sync(model.State?.Approvals ?? []);
    }

    /// <summary>The display the pointer is on (the primary one when it cannot be told).</summary>
    string? PointerDisplay()
    {
        var monitors = islands.Select(i => i.Monitor).ToList();
        if (monitors.Count == 0) return null;
        var pointer = monitors.FirstOrDefault(m => m.Primary) ?? monitors[0];
        if (Native.GetCursorPos(out var cursor))
        {
            pointer = monitors.FirstOrDefault(m => cursor.X >= m.Bounds.Left && cursor.X < m.Bounds.Right
                                                   && cursor.Y >= m.Bounds.Top && cursor.Y < m.Bounds.Bottom) ?? pointer;
        }
        return pointer.Device;
    }

    bool RequestWaits => model.State?.Approvals.Count > 0;

    /// <summary>An event from the engine: on the pointer's display when it comes up (EventQueue).</summary>
    void OnEvent(HudEvent hudEvent)
    {
        if (PointerDisplay() is not { } pointer) return;
        events.Add(hudEvent, RequestWaits, pointer, DateTimeOffset.Now);
        RefreshIslands();
    }

    void TickEvents()
    {
        if (PointerDisplay() is not { } pointer) return;
        var before = events.Current;
        events.Tick(RequestWaits, pointer, DateTimeOffset.Now);
        if (!ReferenceEquals(before, events.Current)) RefreshIslands();
    }

    /// <summary>The pointer over an island that shows the event holds it there.</summary>
    internal void HoldEvent(string display, bool inside)
    {
        if (events.Current is not null && events.Display == display) events.Hold(inside, DateTimeOffset.Now);
    }

    internal void DismissEvent()
    {
        events.Dismiss();
        RefreshIslands();
    }

    void RefreshIslands()
    {
        foreach (var island in islands)
        {
            island.View.Refresh();
            island.ApplyPlacement();
        }
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
            monitors.Add(new Native.Monitor(@"\\.\SNAPSHOT", area, area, 1.0, true, "SNAPSHOT"));
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
            var made = new IslandWindow(model, placement, cards, events, monitor, Send, RefreshIslands);
            islands.Add(made);
            made.Show();
        }
        // A request whose display went away moves to the pointer's.
        PlaceRequests();
        RefreshIslands();
        TellDisplays();
    }

    /// <summary>The engine places each display the shell draws on (1.4): told at the start and whenever they change.</summary>
    void TellDisplays()
    {
        if (engine is null || islands.Count == 0) return;
        Send(ShellMessage.Displays(islands.Select(i => (i.Monitor.Key, false))));
    }

    internal void Send(string line) => engine?.Send(line);

    void OpenSettingsOnce()
    {
        if (model.Hello is null || model.State is null) return;
        model.Changed -= OpenSettingsOnce;
        if (showSettings) Dispatcher.BeginInvoke(OpenSettings);
        if (showStats) Dispatcher.BeginInvoke(OpenStatistics);
    }

    SettingsWindow? settingsWindow;

    /// <summary>Settings: the one window, brought forward when it is open.</summary>
    internal void OpenSettings()
    {
        if (settingsWindow is { IsLoaded: true }) { settingsWindow.Activate(); return; }
        settingsWindow = new SettingsWindow(model, Send);
        settingsWindow.Closed += (_, _) => settingsWindow = null;
        settingsWindow.Show();
        settingsWindow.Activate();
    }

    bool? launchAtLogin;

    /// <summary>Launch at login follows the setting as the macOS Desktop's does: registered once if it is on and never
    /// was, then set as it changes; never in the demo or a snapshot.</summary>
    void FollowLaunchAtLogin()
    {
        if (demo || model.State is null) return;
        var wanted = model.BoolSetting("launchAtLogin", false);
        if (launchAtLogin is null) { if (wanted) LoginItem.RegisterIfNeverRegistered(); }
        else if (launchAtLogin != wanted) LoginItem.Set(wanted);
        launchAtLogin = wanted;
    }

    StatisticsWindow? statisticsWindow;

    /// <summary>Usage statistics: the one window, brought forward when it is open.</summary>
    internal void OpenStatistics()
    {
        if (statisticsWindow is { IsLoaded: true }) { statisticsWindow.Activate(); return; }
        statisticsWindow = new StatisticsWindow(model, Send);
        statisticsWindow.Closed += (_, _) => statisticsWindow = null;
        statisticsWindow.Show();
        statisticsWindow.Activate();
    }

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
