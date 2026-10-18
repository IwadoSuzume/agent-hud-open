// The island's news, as the macOS Desktop's IslandAlertQueue keeps it (Sources/AgentHUDDesktop/Notch/Alerts/
// IslandAlert.swift): one event on the island at a time, the rest waiting in arrival order; an event expires
// `VisibleFor` after it appears or after the pointer last leaves the island, never while the pointer is over it; and
// while a request waits, quota news and reset credits are dropped while replies wait. Each event is shown on the display
// the pointer is on when it comes up (docs/hud.md, Hovering and events). Pure: the caller ticks it.
using AgentHUD.Protocol;

namespace AgentHUD.Shell;

public sealed class EventQueue
{
    public static readonly TimeSpan VisibleFor = TimeSpan.FromSeconds(4);

    readonly List<HudEvent> pending = [];
    bool held;

    /// <summary>The event on the island, and the display it is on.</summary>
    public HudEvent? Current { get; private set; }
    public string? Display { get; private set; }
    /// <summary>When the current event goes, unless the pointer holds it; null while held or with none.</summary>
    public DateTimeOffset? ExpiresAt { get; private set; }

    public IReadOnlyList<HudEvent> Pending => pending;

    /// <summary>Takes an event the engine sent. One without words (an older engine's) is not shown; quota news and
    /// reset credits that arrive while a request waits are dropped, and replies wait for the requests.</summary>
    public void Add(HudEvent hudEvent, bool requestWaits, string pointerDisplay, DateTimeOffset now)
    {
        if (hudEvent.Copy is null) return;
        if (requestWaits && hudEvent is not CompletionEvent) return;
        pending.Add(hudEvent);
        Advance(requestWaits, pointerDisplay, now);
    }

    /// <summary>The pointer over the island holds the current event until it leaves.</summary>
    public void Hold(bool inside, DateTimeOffset now)
    {
        held = inside;
        if (Current is null) return;
        ExpiresAt = inside ? null : now + VisibleFor;
    }

    /// <summary>The time passes: the current event goes when it is due, and the next comes up on the pointer's display
    /// unless a request holds the island.</summary>
    public void Tick(bool requestWaits, string pointerDisplay, DateTimeOffset now)
    {
        if (Current is not null && ExpiresAt is { } due && now >= due) Dismiss();
        Advance(requestWaits, pointerDisplay, now);
    }

    /// <summary>The user put the current event away (Dismiss, or opening what it points to).</summary>
    public void Dismiss()
    {
        Current = null;
        Display = null;
        ExpiresAt = null;
    }

    void Advance(bool requestWaits, string pointerDisplay, DateTimeOffset now)
    {
        if (Current is not null || requestWaits || pending.Count == 0) return;
        Current = pending[0];
        pending.RemoveAt(0);
        Display = pointerDisplay;
        ExpiresAt = held ? null : now + VisibleFor;
    }
}
