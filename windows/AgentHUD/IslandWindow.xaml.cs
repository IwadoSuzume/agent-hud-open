using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
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

    internal IslandWindow(ShellModel model, RequestPlacement placement, Cards cards, EventQueue events, Native.Monitor monitor,
                          Action<string> send, Action refreshAll)
    {
        InitializeComponent();
        this.model = model;
        this.placement = placement;
        this.send = send;
        this.refreshAll = refreshAll;
        Monitor = monitor;
        view = new IslandViewModel(model, placement, cards, events, monitor.Device);
        DataContext = view;
        Island.SizeChanged += (_, _) => PositionAlongSide();
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

    /// <summary>On <paramref name="monitor"/>, sized and placed in its own pixels as its placement says; WPF then lays the
    /// window out at that display's DPI (Per-Monitor-V2).</summary>
    internal void Place(Native.Monitor monitor)
    {
        Monitor = monitor;
        view.Display = monitor.Device;
        ApplyPlacement(force: true);
    }

    // Placement (1.4): where Core puts this display's HUD — the dock on an edge at a share of it — or, while it is being
    // dragged, where the pointer would drop it.
    static readonly Placement Default = new(HudMode.Logos, HudEdge.Top, 0.5, 20, 2, 0.4, true, new System.Text.Json.Nodes.JsonObject());
    (HudEdge Edge, double Offset)? dragTarget;
    (HudEdge Edge, double Offset, Native.RECT Bounds, double Scale)? applied;

    Placement Saved => model.State?.Placements.GetValueOrDefault(Monitor.Key) ?? Default;

    /// <summary>The HUD on its edge: its rest docked there, the panel opening inward, the window along the edge at the
    /// offset (the island at the notch's place for a notch placement, which a Windows display only has if chosen).</summary>
    internal void ApplyPlacement(bool force = false)
    {
        var saved = Saved;
        // The drop is shown until the engine's state carries it.
        if (dragTarget is { } target && !dragging && saved.Edge == target.Edge && Math.Abs(saved.Offset - target.Offset) < 0.001)
            dragTarget = null;
        var edge = dragTarget?.Edge ?? (saved.Mode == HudMode.Notch ? HudEdge.Top : saved.Edge);
        var offset = dragTarget?.Offset ?? (saved.Mode == HudMode.Notch ? 0.5 : saved.Offset);
        if (!force && applied is { } last && last.Edge == edge && Math.Abs(last.Offset - offset) < 0.0001
            && last.Bounds.Equals(Monitor.Bounds) && last.Scale == Monitor.Scale) return;
        applied = (edge, offset, Monitor.Bounds, Monitor.Scale);

        var horizontal = edge is HudEdge.Top or HudEdge.Bottom;
        DockPanel.SetDock(RestPart, edge switch { HudEdge.Top => Dock.Top, HudEdge.Bottom => Dock.Bottom, HudEdge.Left => Dock.Left, _ => Dock.Right });
        Island.CornerRadius = edge switch
        {
            HudEdge.Top => new CornerRadius(0, 0, 14, 14), HudEdge.Bottom => new CornerRadius(14, 14, 0, 0),
            HudEdge.Left => new CornerRadius(0, 14, 14, 0), _ => new CornerRadius(14, 0, 0, 14),
        };
        Island.HorizontalAlignment = edge switch { HudEdge.Left => HorizontalAlignment.Left, HudEdge.Right => HorizontalAlignment.Right, _ => HorizontalAlignment.Center };
        Island.VerticalAlignment = edge == HudEdge.Bottom ? VerticalAlignment.Bottom : VerticalAlignment.Top;
        var panel = new FrameworkElementFactory(typeof(StackPanel));
        panel.SetValue(StackPanel.OrientationProperty, horizontal ? Orientation.Horizontal : Orientation.Vertical);
        MarksList.ItemsPanel = new ItemsPanelTemplate(panel);

        // As tall as the display, the panel at most 80 pt short of it (docs/hud.md, Usage panel).
        Width = horizontal ? 640 : 480;
        Height = Monitor.Bounds.Height / Monitor.Scale;
        PanelScroll.MaxHeight = Math.Max(120, Height - 80);
        PositionAlongSide();
        if (handle == IntPtr.Zero) return;
        var bounds = Monitor.Bounds;
        var width = (int)Math.Round(Width * Monitor.Scale);
        var x = edge switch
        {
            HudEdge.Left => bounds.Left,
            HudEdge.Right => bounds.Right - width,
            _ => Math.Clamp(bounds.Left + (int)Math.Round(offset * bounds.Width) - width / 2, bounds.Left, bounds.Right - width),
        };
        Native.SetWindowPos(handle, Native.HWND_TOPMOST, x, bounds.Top, width, bounds.Height, Native.SWP_NOACTIVATE);
    }

    /// <summary>On a side edge, the HUD's centre at its share of the edge, kept on the display.</summary>
    void PositionAlongSide()
    {
        if (applied is not { } placed || placed.Edge is HudEdge.Top or HudEdge.Bottom || Island.ActualHeight <= 0)
        {
            Island.Margin = new Thickness(0);
            return;
        }
        var top = Math.Clamp(placed.Offset * Height - Island.ActualHeight / 2, 0, Math.Max(0, Height - Island.ActualHeight));
        Island.Margin = new Thickness(0, top, 0, 0);
    }

    // Dragging (docs/hud.md, Placement): the HUD follows the pointer to the nearest edge of its display, and the drop is
    // a patch of Core's `screens` (a notch becomes the dock); the panel stays shut while it moves.
    Native.POINT? pressedAt;
    bool dragging;

    void OnRestDown(object sender, MouseButtonEventArgs e)
    {
        if (!Native.GetCursorPos(out var at)) return;
        pressedAt = at;
        // Held from the press: the pointer leaves the drawn pixels at once, and a transparent pixel passes its moves on.
        RestPart.CaptureMouse();
    }

    void OnRestMove(object sender, MouseEventArgs e)
    {
        if (pressedAt is not { } start || e.LeftButton != MouseButtonState.Pressed || !Native.GetCursorPos(out var now)) return;
        if (!dragging)
        {
            if (Math.Abs(now.X - start.X) + Math.Abs(now.Y - start.Y) < 6 * Monitor.Scale) return;
            dragging = true;
            Feed(new HoverEvent.ForceCollapse());
        }
        var b = Monitor.Bounds;
        var x = Math.Clamp(now.X, b.Left, b.Right - 1);
        var y = Math.Clamp(now.Y, b.Top, b.Bottom - 1);
        var distances = new[] { (HudEdge.Top, y - b.Top), (HudEdge.Bottom, b.Bottom - 1 - y), (HudEdge.Left, x - b.Left), (HudEdge.Right, b.Right - 1 - x) };
        var edge = distances.MinBy(d => d.Item2).Item1;
        var offset = edge is HudEdge.Top or HudEdge.Bottom ? (x - b.Left) / (double)b.Width : (y - b.Top) / (double)b.Height;
        dragTarget = (edge, Math.Round(offset, 4));
        ApplyPlacement();
    }

    void OnRestUp(object sender, MouseButtonEventArgs e)
    {
        pressedAt = null;
        RestPart.ReleaseMouseCapture();
        if (!dragging) return;
        dragging = false;
        if (dragTarget is { } target && model.State is { } state)
            send(ShellMessage.MovePlacement(state.Settings, Monitor.Key, Saved, target.Edge, target.Offset));
        e.Handled = true;
    }

    void Track()
    {
        if (!IsVisible || Island.ActualWidth <= 0 || dragging) return;
        var now = DateTimeOffset.Now;
        // Typing holds the island open, whatever the pointer does.
        var over = typing || PointerOverIsland();
        if (over != inside)
        {
            inside = over;
            ((App)Application.Current).HoldEvent(Monitor.Device, over);
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

    /// <summary>For the snapshot: opens a request's card here, as a click on its line does.</summary>
    internal void OpenRequestForPicture(string requestId)
    {
        placement.Open(requestId, Monitor.Device);
        refreshAll();
    }

    /// <summary>For the snapshot: the island open or at rest, whatever the pointer does.</summary>
    internal void ForceOpen(bool open)
    {
        pointer.Stop();
        Feed(open ? new HoverEvent.ForceOpen() : new HoverEvent.ForceCollapse());
    }

    static CardModel? CardOf(object sender) => (sender as FrameworkElement)?.Tag as CardModel;

    /// <summary>Sends the user's answer; the keyboard, if a field had it, goes back to the app in front.</summary>
    void Decide(string? line)
    {
        if (line is null) return;
        EndTyping(giveBack: true);
        send(line);
    }

    void Answer(object sender, ShellMessage.Decision decision)
    {
        if (CardOf(sender) is { } card) Decide(ShellMessage.Answer(card.Request.Id, decision));
    }

    /// <summary>The news card's button: a reply is put away; other news opens the statistics and goes.</summary>
    void OnEventAction(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not EventItem item) return;
        if (!item.IsReply) ((App)Application.Current).OpenStatistics();
        ((App)Application.Current).DismissEvent();
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
    /// <summary>A plan answered in its own client: putting the card away answers nothing.</summary>
    void OnLeave(object sender, RoutedEventArgs e) => Answer(sender, ShellMessage.Decision.Leave);

    // A question.
    void OnPickOption(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is OptionModel option) option.Card.PickOption(option.Index);
    }

    void OnChooseOwn(object sender, MouseButtonEventArgs e) => CardOf(sender)?.ChooseOwn();
    void OnSkip(object sender, RoutedEventArgs e) => Decide(CardOf(sender)?.SkipQuestion());
    void OnBack(object sender, RoutedEventArgs e) => CardOf(sender)?.GoBack();
    void OnNext(object sender, RoutedEventArgs e) => Decide(CardOf(sender)?.Advance());

    void OnOwnKey(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { e.Handled = true; Decide(CardOf(sender)?.Advance()); }
        else if (e.Key == Key.Escape) { e.Handled = true; EndTyping(giveBack: true); }
    }

    // A plan.
    void OnApprove(object sender, RoutedEventArgs e) =>
        Decide(CardOf(sender) is { } card ? ShellMessage.ApprovePlan(card.Request.Id, acceptEdits: false) : null);
    void OnApproveEdits(object sender, RoutedEventArgs e) =>
        Decide(CardOf(sender) is { } card ? ShellMessage.ApprovePlan(card.Request.Id, acceptEdits: true) : null);
    void OnKeepPlanning(object sender, RoutedEventArgs e) => CardOf(sender)?.StartNote();
    void OnStopNote(object sender, RoutedEventArgs e)
    {
        EndTyping(giveBack: true);
        CardOf(sender)?.StopNote();
    }
    void OnSendNote(object sender, RoutedEventArgs e) => Decide(CardOf(sender)?.SendNote());

    void OnNoteKey(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { e.Handled = true; Decide(CardOf(sender)?.SendNote()); }
        else if (e.Key == Key.Escape) { e.Handled = true; EndTyping(giveBack: true); }
    }

    // Typing (docs/hud.md, Approvals): a field is the only thing on the island that takes the keyboard, and only once
    // clicked; a card that arrives never catches keys typed elsewhere. The keyboard goes back to the app that had it
    // when the answer is sent or Escape is pressed; a click in another window leaves it where the user sent it. The
    // island stays open while it is typed into.
    bool typing;
    IntPtr keysBefore;

    void OnFieldClicked(object sender, MouseButtonEventArgs e)
    {
        if (sender is not TextBox field) return;
        if (!typing)
        {
            keysBefore = Native.GetForegroundWindow();
            typing = true;
            Native.SetExtendedStyle(handle, Native.WS_EX_NOACTIVATE, on: false);
            Activate();
            Feed(new HoverEvent.ForceOpen());
        }
        field.Focus();
        if (field.Tag is CardModel card && field.Name == "OwnField") card.ChooseOwn();
    }

    void EndTyping(bool giveBack)
    {
        if (!typing) return;
        typing = false;
        Keyboard.ClearFocus();
        Native.SetExtendedStyle(handle, Native.WS_EX_NOACTIVATE, on: true);
        if (giveBack && keysBefore != IntPtr.Zero && keysBefore != handle && Native.IsWindow(keysBefore))
            Native.SetForegroundWindow(keysBefore);
        keysBefore = IntPtr.Zero;
    }

    protected override void OnDeactivated(EventArgs e)
    {
        base.OnDeactivated(e);
        EndTyping(giveBack: false);
    }

    protected override void OnClosed(EventArgs e)
    {
        pointer.Stop();
        base.OnClosed(e);
    }
}
