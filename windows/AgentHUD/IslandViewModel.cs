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
    bool isOpen, resting;

    public IslandViewModel(ShellModel model, RequestPlacement placement, Cards cards, string display)
    {
        this.model = model;
        this.placement = placement;
        this.cards = cards;
        Display = display;
    }

    public string Display { get; set; }

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
    public bool HoldsRequest => Waiting.Any(r => placement.DisplayOf(r.Id) == Display);

    public bool ShowsPanel => !Resting && (IsOpen || HoldsRequest);

    /// <summary>Requests wait somewhere: the panel is the event panel, not the usage panel.</summary>
    public bool ShowsEvents => ShowsPanel && Waiting.Count > 0 && !UsageOnly;

    public bool ShowsUsage => ShowsPanel && (Waiting.Count == 0 || UsageOnly);

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
