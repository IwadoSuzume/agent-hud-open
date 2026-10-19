// What the shell last heard from the engine (PROTOCOL.md): the last hello (its words), the last state (a reader keeps
// the last one only) and the events not yet presented. It keeps no model of its own and decides nothing; every value
// shown is the engine's. Used on one thread, the UI's.
using AgentHUD.Protocol;

namespace AgentHUD.Shell;

public sealed class ShellModel
{
    readonly Queue<HudEvent> events = new();

    public EngineHello? Hello { get; private set; }
    public State? State { get; private set; }
    /// <summary>The copy that holds the instance lock, when the engine found one running (it then exits with 3).</summary>
    public LockHeld? LockHeld { get; private set; }
    /// <summary>The engine's last answer to a `statistics` request (1.3).</summary>
    public Statistics? Statistics { get; private set; }

    /// <summary>Raised when the statistics come.</summary>
    public event Action? StatisticsChanged;

    /// <summary>The engine's last answer to a `sources` request (1.5).</summary>
    public Sources? Sources { get; private set; }

    public event Action? SourcesChanged;

    /// <summary>The last error the engine reported about a line of the shell's.</summary>
    public string? LastError { get; private set; }

    /// <summary>Raised after a hello, a state or a lock-held changed what is shown.</summary>
    public event Action? Changed;
    /// <summary>Raised when an event arrives (a quota alert, reset credits, a finished turn).</summary>
    public event Action<HudEvent>? EventArrived;

    public void Apply(object message)
    {
        switch (message)
        {
            case EngineHello hello: Hello = hello; Changed?.Invoke(); break;
            case State state: State = state; Changed?.Invoke(); break;
            case LockHeld held: LockHeld = held; Changed?.Invoke(); break;
            case EngineError error: LastError = error.Message; break;
            case Statistics statistics: Statistics = statistics; StatisticsChanged?.Invoke(); break;
            case Sources sources: Sources = sources; SourcesChanged?.Invoke(); break;
            case HudEvent hudEvent:
                events.Enqueue(hudEvent);
                EventArrived?.Invoke(hudEvent);
                break;
        }
    }

    /// <summary>The engine's word for <paramref name="key"/> (ShellStrings, in the resolved language); the key itself
    /// before the first hello or for a key a newer shell knows and this engine does not.</summary>
    public string Text(string key) => Hello?.Strings.TryGetValue(key, out var text) == true ? text : key;

    /// <summary>The events in the order they came, each taken once.</summary>
    public bool TryTakeEvent(out HudEvent? next)
    {
        next = events.Count > 0 ? events.Dequeue() : null;
        return next is not null;
    }

    /// <summary>The setting <paramref name="name"/> as Core encodes it, or <paramref name="fallback"/>.</summary>
    public int IntSetting(string name, int fallback) =>
        State?.Settings[name] is System.Text.Json.Nodes.JsonValue value && value.TryGetValue(out int number) ? number : fallback;

    public string? StringSetting(string name) =>
        State?.Settings[name] is System.Text.Json.Nodes.JsonValue value && value.TryGetValue(out string? text) ? text : null;

    public bool BoolSetting(string name, bool fallback) =>
        State?.Settings[name] is System.Text.Json.Nodes.JsonValue value && value.TryGetValue(out bool flag) ? flag : fallback;

    /// <summary>The hover delays the user set (Core's `hoverDelayMs`, `collapseDelayMs`, from the state); null before the
    /// first state, when the island draws nothing to hover.</summary>
    public HoverConfig? Hover =>
        State?.Settings["hoverDelayMs"] is System.Text.Json.Nodes.JsonValue hover && hover.TryGetValue(out int open)
        && State.Settings["collapseDelayMs"] is System.Text.Json.Nodes.JsonValue collapse && collapse.TryGetValue(out int close)
            ? new HoverConfig(TimeSpan.FromMilliseconds(open), TimeSpan.FromMilliseconds(close))
            : null;
}
