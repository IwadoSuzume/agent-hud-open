// Which pieces one display's island shows, as the macOS Desktop's ScreenHUD picks them (Sources/AgentHUDDesktop/Notch/
// ScreenHUD.swift, docs/hud.md): the panel only while the hover machine has it open (`showsAlertDetails = machine.isOpen
// && …`), never because a request waits; at rest a request waiting here holds its compact line (PermissionAlertCompactView)
// beside the marks, and news its line in the marks' place, a request's line first.
namespace AgentHUD.Shell;

public readonly record struct IslandParts(bool Panel, bool RequestLine, bool EventLine, bool Marks)
{
    /// <param name="open">The hover machine has the island open.</param>
    /// <param name="resting">The island is drawn at rest whatever waits (the snapshot's picture of it).</param>
    /// <param name="holdsRequest">A request waits on this display.</param>
    /// <param name="hasEvent">News is on this display.</param>
    public static IslandParts At(bool open, bool resting, bool holdsRequest, bool hasEvent)
    {
        var panel = open && !resting;
        var requestLine = holdsRequest && !panel && !resting;
        var eventLine = hasEvent && !panel && !requestLine;
        return new IslandParts(panel, requestLine, eventLine, Marks: !eventLine);
    }
}
