// The island's hover, as the macOS Desktop's HoverMachine (Sources/AgentHUDDesktop/Notch/HoverMachine.swift): open
// after the hover delay, collapse after the collapse delay. Pure; the caller keeps one timer for the returned deadline
// and feeds TimerFired back in.
namespace AgentHUD.Shell;

public enum HoverState { Collapsed, Opening, Open, Closing }

public abstract record HoverEvent
{
    public sealed record PointerEntered(DateTimeOffset At) : HoverEvent;
    public sealed record PointerExited(DateTimeOffset At) : HoverEvent;
    public sealed record TimerFired(DateTimeOffset At) : HoverEvent;
    public sealed record ForceOpen : HoverEvent;
    public sealed record ForceCollapse : HoverEvent;
}

public readonly record struct HoverConfig(TimeSpan HoverDelay, TimeSpan CollapseDelay);

/// <summary>The new machine and, when not null, the time the caller must fire <see cref="HoverEvent.TimerFired"/> at,
/// replacing any earlier timer.</summary>
public readonly record struct HoverTransition(HoverMachine Machine, DateTimeOffset? Deadline);

public readonly record struct HoverMachine(HoverState State, DateTimeOffset? Deadline = null)
{
    /// <summary>True while the panel is shown: open, or about to close.</summary>
    public bool IsOpen => State is HoverState.Open or HoverState.Closing;

    public HoverTransition Reduce(HoverEvent input, HoverConfig config) => (State, input) switch
    {
        (HoverState.Collapsed, HoverEvent.PointerEntered e) => Wait(HoverState.Opening, e.At + config.HoverDelay),
        (HoverState.Opening, HoverEvent.PointerExited) => Settle(HoverState.Collapsed),
        (HoverState.Opening, HoverEvent.TimerFired t) when t.At >= Deadline => Settle(HoverState.Open),
        (HoverState.Open, HoverEvent.PointerExited e) => Wait(HoverState.Closing, e.At + config.CollapseDelay),
        (HoverState.Closing, HoverEvent.PointerEntered) => Settle(HoverState.Open),
        (HoverState.Closing, HoverEvent.TimerFired t) when t.At >= Deadline => Settle(HoverState.Collapsed),
        // A timer that fires early keeps the deadline, or the hover would be left waiting with no timer to finish it.
        (HoverState.Opening or HoverState.Closing, HoverEvent.TimerFired) => new(this, Deadline),
        (_, HoverEvent.ForceOpen) => Settle(HoverState.Open),
        (_, HoverEvent.ForceCollapse) => Settle(HoverState.Collapsed),
        _ => new(this, null),
    };

    static HoverTransition Wait(HoverState state, DateTimeOffset deadline) => new(new HoverMachine(state, deadline), deadline);

    static HoverTransition Settle(HoverState state) => new(new HoverMachine(state), null);
}
