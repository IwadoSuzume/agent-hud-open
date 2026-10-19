// What one display's island binds to: the engine's last state, arranged for the island's pieces. Every figure and text
// is the engine's (PROTOCOL.md "state"); this only picks which of them each piece shows, by the macOS Desktop's rules
// for the island (docs/hud.md): a request holds the island of its display until it is settled; hovering opens the
// queue, the open request whole and the rest a line each, or the usage panel when nothing waits.
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows.Media;
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD;

sealed class IslandViewModel : INotifyPropertyChanged
{
    readonly ShellModel model;
    readonly RequestPlacement placement;
    readonly Cards cards;
    readonly EventQueue events;
    bool isOpen, resting;

    public IslandViewModel(ShellModel model, RequestPlacement placement, Cards cards, EventQueue events, string display)
    {
        this.model = model;
        this.placement = placement;
        this.cards = cards;
        this.events = events;
        Display = display;
    }

    /// <summary>The news on this display's island (EventQueue): its short line at rest, its card when hovered.</summary>
    public EventItem? Event => PictureEvent is { } picture ? Item(picture)
        : events.Current is { Copy: not null } current && events.Display == Display && !Resting ? Item(current)
        : null;

    EventItem Item(HudEvent hudEvent) =>
        new(hudEvent, hudEvent.Copy!, Artwork.Mark(hudEvent.Mark ?? hudEvent.Copy!.VendorName), Initial(hudEvent.Copy!.VendorName), model);

    HudEvent? pictureEvent;

    /// <summary>The snapshot's picture of an event's line or card, with the demo's requests set aside.</summary>
    public HudEvent? PictureEvent
    {
        get => pictureEvent;
        set { pictureEvent = value; Refresh(); }
    }

    /// <summary>The pieces shown (IslandParts, the Desktop's ScreenHUD): the panel only while hovered open; at rest a
    /// request's line beside the marks, else news's line in their place.</summary>
    IslandParts Parts => IslandParts.At(IsOpen, Resting, HoldsRequest, Event is not null);

    public bool ShowsEventLine => Parts.EventLine;
    /// <summary>A dock keeps its marks over its open panel and beside a waiting request's line, the waiting mark wearing
    /// its sign (docs/hud.md); the news line takes their place at rest.</summary>
    public bool ShowsMarks => Parts.Marks;

    /// <summary>At rest, a request waiting on this display holds its line (the Desktop's PermissionAlertCompactView): the
    /// open request's mark, project or vendor and kind, and how many wait. Hovering opens the queue, as on macOS; a
    /// request never opens the panel by itself.</summary>
    public bool ShowsRequestLine => Parts.RequestLine;

    public RequestLineItem? RequestLine =>
        placement.OpenRequest(Waiting.Select(r => r.Id).ToList()) is { } id && Waiting.FirstOrDefault(r => r.Id == id) is { } request
            ? new RequestLineItem(request, Artwork.Mark(request.Mark), Initial(request.Vendor),
                                  request.IsQuestion ? model.Text("approval.questionShort")
                                  : request.IsPlan ? model.Text("approval.planShort") : model.Text("approval.waitingShort"),
                                  Waiting.Count > 1 ? "×" + Waiting.Count : null)
            : null;
    public bool ShowsEventCard => Event is not null && ShowsPanel && (Waiting.Count == 0 || PictureEvent is not null) && !UsageOnly;

    public string Display { get; set; }

    public ShellModel Model => model;

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>Everything again: a new state, a request opened on any display.</summary>
    public void Refresh() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));

    public bool IsOpen
    {
        get => isOpen;
        set { if (isOpen != value) { isOpen = value; Refresh(); } }
    }

    /// <summary>The snapshot's picture of the island at rest, requests or not.</summary>
    public bool Resting
    {
        get => resting;
        set { if (resting != value) { resting = value; Refresh(); } }
    }

    Panel? Panel => model.State?.Panel;
    IReadOnlyList<Approval> Waiting => model.State?.Approvals ?? [];

    public bool Waits(string requestId) => Waiting.Any(r => r.Id == requestId);

    /// <summary>A request of this display's waits: the island stays open for it.</summary>
    public bool HoldsRequest => PictureEvent is null && Waiting.Any(r => placement.DisplayOf(r.Id) == Display);

    public bool ShowsPanel => Parts.Panel;

    /// <summary>Requests wait somewhere: the panel is the event panel, not the usage panel.</summary>
    public bool ShowsEvents => ShowsPanel && Waiting.Count > 0 && !UsageOnly && PictureEvent is null;

    public bool ShowsUsage => ShowsPanel && ((Waiting.Count == 0 && Event is null) || UsageOnly);

    bool usageOnly;

    /// <summary>The snapshot's picture of the usage panel, with the demo's requests waiting.</summary>
    public bool UsageOnly
    {
        get => usageOnly;
        set { if (usageOnly != value) { usageOnly = value; Refresh(); } }
    }

    /// <summary>The resting HUD's marks, Core's logo queue in its order (`panel.marks`).</summary>
    public IReadOnlyList<MarkItem> Marks =>
        (Panel?.Marks ?? []).Select(m => new MarkItem(m, Artwork.Mark(m.Key), Initial(m.Vendor))).ToList();

    public IReadOnlyList<AgentItem> Agents =>
        (Panel?.Agents ?? []).Select(a => new AgentItem(a, Artwork.Mark(a.Mark), Initial(a.Vendor))).ToList();

    public IReadOnlyList<SessionItem> Sessions =>
        (Panel?.Sessions ?? []).Select(s => new SessionItem(s, s.Mark is { } mark ? Artwork.Mark(mark) : null,
                                                            Initial(s.Vendor ?? "?"))).ToList();

    /// <summary>The request the answers act on, whole: its card, the same object for as long as it waits.</summary>
    public CardModel? OpenCard =>
        placement.OpenRequest(Waiting.Select(r => r.Id).ToList()) is { } id ? cards.Card(id) : null;

    /// <summary>Every other request waiting, on any display, a line each, oldest first.</summary>
    public IReadOnlyList<ApprovalItem> QueuedRequests
    {
        get
        {
            var open = placement.OpenRequest(Waiting.Select(r => r.Id).ToList());
            return Waiting.Where(r => r.Id != open).Select(Item).ToList();
        }
    }

    ApprovalItem Item(Approval request) => new(request, Artwork.Mark(request.Mark), Initial(request.Vendor));

    public string? Error => model.State?.Error;

    static string Initial(string vendor) => vendor.Length > 0 ? vendor[..1].ToUpperInvariant() : "?";
}

/// <summary>A resting mark; its status colour is the glow's, as on macOS, and a waiting request wears a sign.</summary>
sealed record MarkItem(QueueMark Mark, ImageSource? Image, string Initial);

sealed record SessionItem(Session Session, ImageSource? Image, string Initial);

sealed record AgentItem(AgentRow Row, ImageSource? Image, string Initial)
{
    /// <summary>The share of the window used, 0–1, for the bar; the figure itself is the engine's.</summary>
    public double UsedFraction => Row.UsedPct is { } used ? System.Math.Clamp(used / 100.0, 0, 1) : 0;
    public string? ResetText => Row.ResetText;
}

/// <summary>One line of the queue: enough to decide whether to open it.</summary>
sealed record ApprovalItem(Approval Request, ImageSource? Image, string Initial);

/// <summary>The news on an island: the engine's words for it (`EventCopy`), its mark, and its accent, the Desktop's
/// IslandAlert accents (DesktopColours): a reply's, a warning's, or other news's.</summary>
sealed record EventItem(HudEvent Event, EventCopy Copy, ImageSource? Image, string Initial, ShellModel Model)
{
    static readonly SolidColorBrush Turn = LevelBrush.Frozen(DesktopColours.TurnAccent);
    static readonly SolidColorBrush Warning = LevelBrush.Frozen(DesktopColours.WarningAccent);
    static readonly SolidColorBrush Calm = LevelBrush.Frozen(DesktopColours.CalmAccent);

    public bool IsReply => Event is CompletionEvent;
    public bool IsNews => !IsReply;
    public Brush Accent => IsReply ? Turn : Copy.Warning ? Warning : Calm;
    public double UsedFraction => Copy.UsedPct is { } used ? System.Math.Clamp(used / 100.0, 0, 1) : 0;
    public bool HasUsage => Copy.UsedPct is not null;
    /// <summary>A reply is put away; other news opens the statistics (the Desktop's "View usage statistics").</summary>
    public string Action => IsReply ? Model.Text("reply.dismiss") : Model.Text("alert.viewStatistics");
}

/// <summary>A waiting request's line at rest: its mark, its project (else its vendor), its kind and the count waiting.</summary>
sealed record RequestLineItem(Approval Request, ImageSource? Image, string Initial, string Status, string? Count)
{
    public string Title => Request.Project ?? Request.Vendor;
}
