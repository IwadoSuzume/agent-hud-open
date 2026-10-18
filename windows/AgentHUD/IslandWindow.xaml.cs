using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Threading;
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD;

/// <summary>One display's island: a tool window (no taskbar button, no Alt+Tab), topmost, that never takes the focus
/// (`WS_EX_NOACTIVATE`, `MA_NOACTIVATE`), placed at the top centre of its display in physical pixels. The pointer is
/// followed by polling, as the macOS hover is a timer over the cursor too, and fed to <see cref="HoverMachine"/>.</summary>
public partial class IslandWindow : Window
{
    readonly IslandViewModel view;
    readonly ShellModel model;
    readonly Action<string> send;
    readonly DispatcherTimer pointer;
    HoverMachine hover = new(HoverState.Collapsed);
    DateTimeOffset? deadline;
    bool inside;
    IntPtr handle;

    internal Native.Monitor Monitor { get; private set; }

    readonly RequestPlacement placement;
    readonly Action refreshAll;

    internal IslandWindow(ShellModel model, RequestPlacement placement, Native.Monitor monitor, Action<string> send, Action refreshAll)
    {
        InitializeComponent();
        this.model = model;
        this.placement = placement;
        this.send = send;
        this.refreshAll = refreshAll;
        Monitor = monitor;
        view = new IslandViewModel(model, placement, monitor.Device);
        DataContext = view;
        pointer = new DispatcherTimer(TimeSpan.FromMilliseconds(40), DispatcherPriority.Input, (_, _) => Track(), Dispatcher);
    }

    internal IslandViewModel View => view;

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        handle = new WindowInteropHelper(this).Handle;
        Native.AddExtendedStyle(handle, Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
        HwndSource.FromHwnd(handle)?.AddHook(Hook);
        Place(Monitor);
        pointer.Start();
    }

    static IntPtr Hook(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        // A click on the island acts without bringing Agent HUD to the front: the app in use keeps the keys.
        if (message == Native.WM_MOUSEACTIVATE)
        {
            handled = true;
            return new IntPtr(Native.MA_NOACTIVATE);
        }
        return IntPtr.Zero;
    }

    /// <summary>At the top centre of <paramref name="monitor"/>, sized in its own pixels; WPF then lays the window out
    /// at that display's DPI (Per-Monitor-V2).</summary>
    internal void Place(Native.Monitor monitor)
    {
        Monitor = monitor;
        view.Display = monitor.Device;
        // As tall as the display, the panel at most 80 pt short of it (docs/hud.md, Usage panel).
        Height = monitor.Bounds.Height / monitor.Scale;
        PanelScroll.MaxHeight = Math.Max(120, Height - 80);
        if (handle == IntPtr.Zero) return;
        var width = (int)Math.Round(Width * monitor.Scale);
        var height = monitor.Bounds.Height;
        var x = monitor.Bounds.Left + (monitor.Bounds.Width - width) / 2;
        Native.SetWindowPos(handle, Native.HWND_TOPMOST, x, monitor.Bounds.Top, width, height, Native.SWP_NOACTIVATE);
    }

    void Track()
    {
        if (!IsVisible || Island.ActualWidth <= 0) return;
        var now = DateTimeOffset.Now;
        var over = PointerOverIsland();
        if (over != inside)
        {
            inside = over;
            Feed(over ? new HoverEvent.PointerEntered(now) : new HoverEvent.PointerExited(now));
        }
        if (deadline is { } due && now >= due) Feed(new HoverEvent.TimerFired(now));
    }

    void Feed(HoverEvent input)
    {
        var next = hover.Reduce(input, model.Hover);
        hover = next.Machine;
        deadline = next.Deadline;
        view.IsOpen = hover.IsOpen;
    }

    bool PointerOverIsland()
    {
        if (!Native.GetCursorPos(out var cursor)) return false;
        var topLeft = Island.PointToScreen(new Point(0, 0));
        var bottomRight = Island.PointToScreen(new Point(Island.ActualWidth, Island.ActualHeight));
        return cursor.X >= topLeft.X && cursor.X < bottomRight.X && cursor.Y >= topLeft.Y && cursor.Y < bottomRight.Y;
    }

    /// <summary>For the snapshot: the island open or at rest, whatever the pointer does.</summary>
    internal void ForceOpen(bool open)
    {
        pointer.Stop();
        Feed(open ? new HoverEvent.ForceOpen() : new HoverEvent.ForceCollapse());
    }

    void Answer(object sender, ShellMessage.Decision decision)
    {
        if ((sender as Button)?.Tag is ApprovalItem item) send(ShellMessage.Answer(item.Request.Id, decision));
    }

    /// <summary>A queued request's line: it opens here, closing the one before, and moves to this display.</summary>
    void OnOpenRequest(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not ApprovalItem item) return;
        placement.Open(item.Request.Id, Monitor.Device);
        refreshAll();
    }

    void OnDeny(object sender, RoutedEventArgs e) => Answer(sender, ShellMessage.Decision.Deny);
    void OnAllow(object sender, RoutedEventArgs e) => Answer(sender, ShellMessage.Decision.Allow);
    void OnAlways(object sender, RoutedEventArgs e) => Answer(sender, ShellMessage.Decision.AllowAlways);

    protected override void OnClosed(EventArgs e)
    {
        pointer.Stop();
        base.OnClosed(e);
    }
}
