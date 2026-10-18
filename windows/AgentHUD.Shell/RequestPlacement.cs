// Which display each waiting request is on (docs/hud.md, Approvals): the one the pointer was on when it arrived; one
// whose display went away moves to the pointer's; opening a request's line on another display moves it there. The
// queue itself, every request waiting on any display, is the engine's list, oldest first.
namespace AgentHUD.Shell;

public sealed class RequestPlacement
{
    readonly Dictionary<string, string> displays = [];

    /// <summary>Takes the engine's waiting requests: new ones go to <paramref name="pointerDisplay"/>, settled ones are
    /// forgotten, and those on a display not in <paramref name="present"/> move to the pointer's.</summary>
    public void Update(IEnumerable<string> waiting, string pointerDisplay, IReadOnlyCollection<string> present)
    {
        var ids = waiting.ToHashSet();
        foreach (var gone in displays.Keys.Where(id => !ids.Contains(id)).ToList()) displays.Remove(gone);
        foreach (var id in ids)
        {
            if (!displays.TryGetValue(id, out var display) || !present.Contains(display)) displays[id] = pointerDisplay;
        }
    }

    /// <summary>The display <paramref name="requestId"/> is on, or null for one not waiting.</summary>
    public string? DisplayOf(string requestId) => displays.TryGetValue(requestId, out var display) ? display : null;

    /// <summary>Opening a request's line on <paramref name="display"/> opens it, closing the one before, and brings the
    /// request there.</summary>
    public void Open(string requestId, string display)
    {
        if (!displays.ContainsKey(requestId)) return;
        displays[requestId] = display;
        chosen = requestId;
    }

    string? chosen;

    /// <summary>The request the answers act on: the one opened last while it waits, else the one that has waited
    /// longest (<paramref name="waitingOldestFirst"/>, the engine's order), so an answer hands over to it.</summary>
    public string? OpenRequest(IReadOnlyList<string> waitingOldestFirst) =>
        chosen is { } id && waitingOldestFirst.Contains(id) ? id : waitingOldestFirst.FirstOrDefault();
}
