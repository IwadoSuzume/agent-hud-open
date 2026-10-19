// The shell's side of the engine-shell protocol, version 1.0 (docs/windows-port/PROTOCOL.md). The engine computes
// every value shown; this reads its messages and writes the shell's, and decides nothing else.
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace AgentHUD.Protocol;

/// <summary>A line the shell does not take: not a JSON object, another major version, an unknown type, a malformed
/// field. It is logged and ignored (D-022).</summary>
public sealed class ProtocolRejectedException(string message) : Exception(message);

public static class ProtocolVersion
{
    public const int Major = 1;
    public const int Minor = 5;
    /// <summary>The longest line either side takes.</summary>
    public const int LineLimit = 16 * 1024 * 1024;
}

public enum StatusLevel { Ok, Warning, Critical }

public enum SessionPhase { Running, WaitingForApproval, Idle, Unverified }

public sealed record EngineHello(int Minor, string EngineVersion, bool Demo, string Language,
                                 IReadOnlyDictionary<string, string> Strings);

public sealed record LockHeld(string? Holder);

public sealed record EngineError(string Message);

public sealed record GlowSegment(string Vendor, StatusLevel Level);

/// <summary>One mark of the resting HUD (1.1, Core's logo queue): vendors that share artwork share its key.</summary>
public sealed record QueueMark(string Key, string Vendor, bool IsWorking, bool Waiting);

public sealed record AgentRow(string Id, string Vendor, string Model, string? ShortModel, StatusLevel? Level,
                              double? UsedPct, double? RemainingPct, double? WeeklyRemainingPct, DateTimeOffset? ResetAt,
                              string? ResetText, string MissingQuotaLabel, int PaletteIndex, bool IsCurrentAccount,
                              string? ForecastHint, string ModelText, string ShortModelText, string Mark);

public sealed record Session(string Id, string AgentId, string Task, string? Project, SessionPhase Phase, string PhaseText,
                             DateTimeOffset StartedAt, DateTimeOffset LastEventAt, string? Message, bool LiveStatus,
                             long TokensIn, long TokensOut, long CacheReadTokens, string TokensText, string? Vendor,
                             string? Mark);

public sealed record QuestionOption(string Label, string? Description);

public sealed record Question(string Key, string Text, string? Header, bool MultiSelect, IReadOnlyList<QuestionOption> Options);

public sealed record Approval(string Id, string Source, string Vendor, string SessionId, string? ToolName, string Summary,
                              string? Detail, string? Project, string? Path, string? Removed, string? Added,
                              DateTimeOffset At, bool IsQuestion, IReadOnlyList<Question> Questions, bool IsPlan,
                              string? Plan, bool AnswersPlan, string? AlwaysAllowRule, string Mark);

public sealed record Panel(DateTimeOffset Now, double? MaxUsedPct, IReadOnlyList<GlowSegment> Glow,
                           IReadOnlyList<AgentRow> Agents, IReadOnlyList<Session> Sessions, IReadOnlyList<QueueMark> Marks);

public enum HudMode { Notch, Logos, Simple }

public enum HudEdge { Top, Right, Bottom, Left }

/// <summary>Where one display's HUD is (1.4), as Core placed it: its mode, the edge it is parked on, its centre along
/// that edge as a share of the edge, and its marks' size and distance from the edge in points. <see cref="Encoded"/> is
/// Core's own encoding, from which the shell makes a patch when the HUD is dragged.</summary>
public sealed record Placement(HudMode Mode, HudEdge Edge, double Offset, double LogoSize, double LogoEdgeDistance,
                               double GapScale, bool ShowsLogos, JsonObject Encoded);

/// <summary>The whole of what the HUD shows. <see cref="Settings"/> is Core's own encoding, kept as JSON: the shell
/// edits it by sending patches, and Core validates them. <see cref="Placements"/> (1.4) by display key; empty from an
/// older engine.</summary>
public sealed record State(DateTimeOffset? GeneratedAt, bool Paused, string? Error, JsonObject Settings, Panel Panel,
                           IReadOnlyList<Approval> Approvals, IReadOnlyDictionary<string, Placement> Placements);

/// <summary>One figure of an event's card: its value and its label, both the engine's words.</summary>
public sealed record Metric(string Value, string Label);

/// <summary>An event card's words (1.2), the Desktop's own copy made by the engine: the short line beside the mark
/// (`CompactTitle`; a reply's status), the sentence (`Title`; a reply's task), the badge, the figures, and whether the
/// card is a warning. Null from a 1.1 engine, whose events the shell cannot word and does not show.</summary>
public sealed record EventCopy(string VendorName, string? AgentName, string? DisplayName, string CompactTitle, string Title,
                               string? Badge, bool Warning, double? UsedPct, IReadOnlyList<Metric> Metrics, string? OtherLimits);

public abstract record HudEvent(string Id, EventCopy? Copy, string? Mark);
public sealed record QuotaAlertEvent(string Id, string Alert, string AgentId, string Vendor, string Model, bool Preview,
                                     long? TimeToExhaust, string? TimeToExhaustText,
                                     IReadOnlyList<string> AlsoExhausted, EventCopy? Copy, string? Mark) : HudEvent(Id, Copy, Mark);
public sealed record ResetCreditsEvent(string Id, int Added, bool Preview, string Provider, string? AccountLabel,
                                       EventCopy? Copy) : HudEvent(Id, Copy, null);
public sealed record CompletionEvent(string Id, string SessionId, string Vendor, string Task, string Model,
                                     DateTimeOffset? StartedAt, DateTimeOffset CompletedAt, EventCopy? Copy,
                                     string? Mark) : HudEvent(Id, Copy, Mark);

/// <summary>One model's part of a period (1.3): its name, mark, tokens as Core writes them, share of the period's whole
/// (for the bar) and Core's palette index.</summary>
public sealed record StatisticsModel(string Id, string Name, string DisplayName, string Vendor, string Mark, string Tokens,
                                     double Share, int PaletteIndex);

/// <summary>Today, the last seven or the last thirty days (1.3): the total, cost and cache share as Core writes them,
/// every model that spent tokens, how many of them the card names, and the rest counted together.</summary>
public sealed record StatisticsPeriod(string Period, string Label, string Total, string? Cost, string? CacheHits,
                                      IReadOnlyList<StatisticsModel> Models, int Listed, string? RestText, string? RestTokens);

/// <summary>The statistics window's Recent usage card (1.3), the engine's answer to a `statistics` request.</summary>
public sealed record Statistics(DateTimeOffset? GeneratedAt, string Title, string Dimensions, IReadOnlyList<StatisticsPeriod> Periods);

/// <summary>One client the build looks for (1.5): its name, mark, the engine's status words and detail, whether this
/// build reads it at all, and whether it was found.</summary>
public sealed record SourceItem(string Id, string Name, string Mark, string Detail, string Status, bool Supported, bool Detected);

/// <summary>The clients the build looks for (1.5), the engine's answer to a `sources` request.</summary>
public sealed record Sources(string Title, IReadOnlyList<SourceItem> Items);

/// <summary>Reads one line from the engine.</summary>
public static class EngineMessage
{
    /// <summary>The message on <paramref name="line"/>: <see cref="EngineHello"/>, <see cref="LockHeld"/>,
    /// <see cref="State"/>, <see cref="HudEvent"/> or <see cref="EngineError"/>. Fields it does not know are
    /// ignored (a later minor version); anything else wrong throws <see cref="ProtocolRejectedException"/>.</summary>
    public static object Parse(string line)
    {
        try { return ParseLine(line); }
        // A number out of range, a key given twice (System.Text.Json raises these when the field is read): a line the
        // shell does not take, like any other malformed one.
        catch (Exception error) when (error is OverflowException or ArgumentException or InvalidOperationException or FormatException)
        {
            throw Rejected($"malformed line: {error.Message}");
        }
    }

    static object ParseLine(string line)
    {
        if (Encoding.UTF8.GetByteCount(line) > ProtocolVersion.LineLimit) throw Rejected("line over the limit");
        if (line.Contains('\n') || line.Contains('\r')) throw Rejected("more than one line");
        JsonObject message;
        try { message = JsonNode.Parse(line) as JsonObject ?? throw Rejected("not a JSON object"); }
        catch (JsonException) { throw Rejected("not JSON"); }
        if (message["v"] is not JsonValue v || v.GetValueKind() != JsonValueKind.Number || !v.TryGetValue(out int major)
            || major != ProtocolVersion.Major)
            throw Rejected($"not protocol version {ProtocolVersion.Major}");
        return Text(message, "type") switch
        {
            "hello" => new EngineHello(Int(message, "minor"), Text(Obj(message, "engine"), "version"), Bool(message, "demo"),
                                       Text(message, "language"),
                                       Obj(message, "strings").ToDictionary(p => p.Key, p => AsText(p.Value, p.Key))),
            "lock-held" => new LockHeld(OptText(message, "holder")),
            "error" => new EngineError(Text(message, "message")),
            "state" => ParseState(message),
            "event" => ParseEvent(Obj(message, "event")),
            "statistics" => ParseStatistics(message),
            "sources" => new Sources(Text(message, "title"), Arr(message, "sources").Select(s => new SourceItem(
                Text(s, "id"), Text(s, "name"), Text(s, "mark"), Text(s, "detail"), Text(s, "status"), Bool(s, "supported"),
                Bool(s, "detected"))).ToList()),
            var type => throw Rejected($"unknown type {type}"),
        };
    }

    static State ParseState(JsonObject message)
    {
        var panel = Obj(message, "panel");
        return new State(OptTime(message, "generatedAt"), Bool(message, "paused"), OptText(message, "error"),
            (JsonObject)Obj(message, "settings").DeepClone(),
            new Panel(Time(panel, "now"), OptNumber(panel, "maxUsedPct"),
                      Arr(panel, "glow").Select(g => new GlowSegment(Text(g, "vendor"), Level(Text(g, "level")))).ToList(),
                      Arr(panel, "agents").Select(ParseAgent).ToList(),
                      Arr(panel, "sessions").Select(ParseSession).ToList(),
                      Has(panel, "marks")
                          ? Arr(panel, "marks").Select(m => new QueueMark(Text(m, "key"), Text(m, "vendor"), Bool(m, "isWorking"),
                                                                          Bool(m, "waiting"))).ToList()
                          : []),
            Arr(message, "approvals").Select(ParseApproval).ToList(),
            Has(message, "placements")
                ? Obj(message, "placements").ToDictionary(p => p.Key, p => ParsePlacement(p.Value as JsonObject ?? throw Rejected($"placement {p.Key}")))
                : new Dictionary<string, Placement>());
    }

    static Placement ParsePlacement(JsonObject p) => new(
        Text(p, "mode") switch { "notch" => HudMode.Notch, "logos" => HudMode.Logos, "simple" => HudMode.Simple, var m => throw Rejected($"unknown mode {m}") },
        Text(p, "edge") switch { "top" => HudEdge.Top, "right" => HudEdge.Right, "bottom" => HudEdge.Bottom, "left" => HudEdge.Left,
                                 var e => throw Rejected($"unknown edge {e}") },
        Number(p, "offset"), Number(p, "logoSize"), Number(p, "logoEdgeDistance"), Number(p, "gapScale"),
        Bool(p, "showsLogos"), (JsonObject)p.DeepClone());

    static Statistics ParseStatistics(JsonObject message) => new(
        OptTime(message, "generatedAt"), Text(message, "title"), Text(message, "dimensions"),
        Arr(message, "periods").Select(p => new StatisticsPeriod(
            Text(p, "period"), Text(p, "label"), Text(p, "total"), OptText(p, "cost"), OptText(p, "cacheHits"),
            Arr(p, "models").Select(m => new StatisticsModel(Text(m, "id"), Text(m, "name"), Text(m, "displayName"),
                Text(m, "vendor"), Text(m, "mark"), Text(m, "tokens"), OptNumber(m, "share") ?? 0, Int(m, "paletteIndex"))).ToList(),
            Int(p, "listed"),
            Field(p, "rest") is JsonObject rest ? Text(rest, "text") : null,
            Field(p, "rest") is JsonObject restTokens ? Text(restTokens, "tokens") : null)).ToList());

    static AgentRow ParseAgent(JsonObject a) => new(
        Text(a, "id"), Text(a, "vendor"), Text(a, "model"), OptText(a, "shortModel"),
        OptText(a, "level") is { } level ? Level(level) : null,
        OptNumber(a, "usedPct"), OptNumber(a, "remainingPct"), OptNumber(a, "weeklyRemainingPct"), OptTime(a, "resetAt"),
        OptText(a, "resetText"), Text(a, "missingQuotaLabel"), Int(a, "paletteIndex"), Bool(a, "isCurrentAccount"),
        OptText(a, "forecastHint"),
        // 1.1; a 1.0 engine's row is labelled by its model as given, drawn with its vendor's mark.
        Has(a, "modelText") ? Text(a, "modelText") : Text(a, "model"),
        Has(a, "shortModelText") ? Text(a, "shortModelText") : OptText(a, "shortModel") ?? Text(a, "model"),
        Has(a, "mark") ? Text(a, "mark") : Text(a, "vendor"));

    static Session ParseSession(JsonObject s) => new(
        Text(s, "id"), Text(s, "agentId"), Text(s, "task"), OptText(s, "project"),
        Text(s, "phase") switch
        {
            "running" => SessionPhase.Running, "waitingForApproval" => SessionPhase.WaitingForApproval,
            "idle" => SessionPhase.Idle, "unverified" => SessionPhase.Unverified,
            var other => throw Rejected($"unknown phase {other}"),
        },
        Text(s, "phaseText"), Time(s, "startedAt"), Time(s, "lastEventAt"), OptText(s, "message"), Bool(s, "liveStatus"),
        Long(s, "tokensIn"), Long(s, "tokensOut"), Long(s, "cacheReadTokens"), Text(s, "tokensText"),
        Has(s, "vendor") ? OptText(s, "vendor") : null, Has(s, "mark") ? OptText(s, "mark") : null);

    static Approval ParseApproval(JsonObject r) => new(
        Text(r, "id"), Text(r, "source"), Text(r, "vendor"), Text(r, "sessionID"), OptText(r, "toolName"), Text(r, "summary"),
        OptText(r, "detail"), OptText(r, "project"), OptText(r, "path"), OptText(r, "removed"), OptText(r, "added"),
        Time(r, "at"), Bool(r, "isQuestion"),
        Arr(r, "questions").Select(q => new Question(Text(q, "key"), Text(q, "question"), OptText(q, "header"),
            Bool(q, "multiSelect"),
            Arr(q, "options").Select(o => new QuestionOption(Text(o, "label"), OptText(o, "description"))).ToList())).ToList(),
        Bool(r, "isPlan"), OptText(r, "plan"), Bool(r, "answersPlan"), OptText(r, "alwaysAllowRule"),
        Has(r, "mark") ? Text(r, "mark") : Text(r, "vendor"));

    static HudEvent ParseEvent(JsonObject e) => Text(e, "kind") switch
    {
        "quotaAlert" => new QuotaAlertEvent(Text(e, "id"), Text(e, "alert"), Text(e, "agentId"), Text(e, "vendor"),
            Text(e, "model"), Bool(e, "preview"), OptLong(e, "timeToExhaust"), OptText(e, "timeToExhaustText"),
            Texts(e, "alsoExhausted"), Copy(e), Has(e, "mark") ? Text(e, "mark") : null),
        "resetCredits" => new ResetCreditsEvent(Text(e, "id"), Int(e, "added"), Bool(e, "preview"), Text(e, "provider"),
            OptText(e, "accountLabel"), Copy(e)),
        "completion" => new CompletionEvent(Text(e, "id"), Text(e, "sessionID"), Text(e, "vendor"), Text(e, "task"),
            Text(e, "model"), OptTime(e, "startedAt"), Time(e, "completedAt"), Copy(e), Has(e, "mark") ? Text(e, "mark") : null),
        var kind => throw Rejected($"unknown event {kind}"),
    };

    /// <summary>An event's words (1.2): a quota alert's and reset credits' as they are, a reply's status and task in
    /// the places of the short line and the sentence.</summary>
    static EventCopy? Copy(JsonObject e)
    {
        if (!Has(e, "copy")) return null;
        var c = Obj(e, "copy");
        var metrics = Has(c, "metrics") ? Arr(c, "metrics").Select(m => new Metric(Text(m, "value"), Text(m, "label"))).ToList() : [];
        return Has(c, "status")
            ? new EventCopy(Text(c, "vendorName"), null, null, Text(c, "status"), Text(c, "title"), null, Bool(c, "warning"), null, metrics, null)
            : new EventCopy(Text(c, "vendorName"), Has(c, "agentName") ? Text(c, "agentName") : null,
                            Has(c, "displayName") ? Text(c, "displayName") : null, Text(c, "compactTitle"), Text(c, "title"),
                            OptText(c, "badge"), Bool(c, "warning"), Has(c, "usedPct") ? OptNumber(c, "usedPct") : null, metrics,
                            Has(c, "otherLimits") ? OptText(c, "otherLimits") : null);
    }

    static StatusLevel Level(string text) => text switch
    {
        "ok" => StatusLevel.Ok, "warning" => StatusLevel.Warning, "critical" => StatusLevel.Critical,
        _ => throw Rejected($"unknown level {text}"),
    };

    // Field readers: a missing field or one of another kind rejects the line.
    /// <summary>A field a later minor version added is there (an older engine leaves it out).</summary>
    static bool Has(JsonNode? node, string name) => node is JsonObject o && o.ContainsKey(name);

    static ProtocolRejectedException Rejected(string why) => new(why);

    static JsonNode? Field(JsonNode? node, string name) =>
        node is JsonObject o ? (o.TryGetPropertyValue(name, out var v) ? v : throw Rejected($"no {name}"))
                             : throw Rejected($"{name}: not in an object");

    static JsonValue Value(JsonNode? node, string name, JsonValueKind kind) =>
        Field(node, name) is JsonValue v && v.GetValueKind() == kind ? v : throw Rejected($"{name} is not {kind}");

    static string Text(JsonNode? node, string name) => Value(node, name, JsonValueKind.String).GetValue<string>();

    static string? OptText(JsonNode? node, string name) => Field(node, name) is null ? null : Text(node, name);

    static bool Bool(JsonNode? node, string name) =>
        Field(node, name) is JsonValue v && v.GetValueKind() is JsonValueKind.True or JsonValueKind.False
            ? v.GetValue<bool>() : throw Rejected($"{name} is not a boolean");

    static long Long(JsonNode? node, string name) =>
        Value(node, name, JsonValueKind.Number).TryGetValue(out long l) ? l : throw Rejected($"{name} is not an integer");

    static long? OptLong(JsonNode? node, string name) => Field(node, name) is null ? null : Long(node, name);

    static int Int(JsonNode? node, string name) => checked((int)Long(node, name));

    static double Number(JsonNode? node, string name) => Value(node, name, JsonValueKind.Number).GetValue<double>();

    static double? OptNumber(JsonNode? node, string name) =>
        Field(node, name) is null ? null : Value(node, name, JsonValueKind.Number).GetValue<double>();

    static DateTimeOffset Time(JsonNode? node, string name) => DateTimeOffset.FromUnixTimeMilliseconds(Long(node, name));

    static DateTimeOffset? OptTime(JsonNode? node, string name) => Field(node, name) is null ? null : Time(node, name);

    static JsonObject Obj(JsonNode? node, string name) => Field(node, name) as JsonObject ?? throw Rejected($"{name} is not an object");

    static string AsText(JsonNode? value, string what) =>
        value is JsonValue v && v.GetValueKind() == JsonValueKind.String ? v.GetValue<string>() : throw Rejected($"{what} is not text");

    static List<string> Texts(JsonNode? node, string name) =>
        (Field(node, name) as JsonArray ?? throw Rejected($"{name} is not an array"))
            .Select(item => item is JsonValue v && v.GetValueKind() == JsonValueKind.String ? v.GetValue<string>()
                                                                                         : throw Rejected($"{name} holds a non-text"))
            .ToList();

    static IEnumerable<JsonObject> Arr(JsonNode? node, string name) =>
        (Field(node, name) as JsonArray ?? throw Rejected($"{name} is not an array"))
            .Select(item => item as JsonObject ?? throw Rejected($"{name} holds a non-object"));
}

/// <summary>The shell's messages, one line each, written as the engine reads them: keys in ordinal order, no spaces,
/// text in UTF-8 as it is (only what JSON requires escaped), ended by LF.</summary>
public static class ShellMessage
{
    public static string Hello(string shellVersion) =>
        Line(new() { ["minor"] = ProtocolVersion.Minor, ["shell"] = new JsonObject { ["version"] = shellVersion }, ["type"] = "hello" });

    public static string Refresh() => Line(new() { ["type"] = "refresh" });

    /// <summary>1.4: the displays the shell draws on, by their stable keys; each state then places them.</summary>
    public static string Displays(IEnumerable<(string Key, bool HasNotch)> displays) =>
        Line(new() { ["type"] = "displays", ["displays"] = new JsonArray(displays.Select(d =>
            (JsonNode?)new JsonObject { ["hasNotch"] = d.HasNotch, ["key"] = d.Key }).ToArray()) });

    /// <summary>1.4: a display's HUD moved to <paramref name="edge"/> at <paramref name="offset"/> along it, as a patch
    /// of Core's `screens`: every other display's placement as it is, this one's in its own encoding with the mode, edge
    /// and offset changed (a notch dragged becomes the dock, docs/hud.md). Core validates it.</summary>
    public static string MovePlacement(JsonObject settings, string key, Placement current, HudEdge edge, double offset)
    {
        var screens = settings["screens"] is JsonObject saved ? (JsonObject)saved.DeepClone() : new JsonObject();
        var moved = (JsonObject)current.Encoded.DeepClone();
        if (current.Mode == HudMode.Notch) moved["mode"] = "logos";
        moved["edge"] = edge.ToString().ToLowerInvariant();
        moved["offset"] = Math.Clamp(offset, 0, 1);
        screens[key] = moved;
        return UpdateSettings(new JsonObject { ["screens"] = screens });
    }

    /// <summary>1.5: the settings window asks which clients the build looks for; the engine answers with `sources`.</summary>
    public static string Sources() => Line(new() { ["type"] = "sources" });

    /// <summary>1.3: the statistics window asks for its figures; the engine answers with `statistics`.</summary>
    public static string Statistics() => Line(new() { ["type"] = "statistics" });

    public static string Quit() => Line(new() { ["type"] = "quit" });

    /// <summary>The user chose allow, deny, Always allow (the rule is the request's own, which only the engine
    /// holds) or to leave the request to the client.</summary>
    public static string Answer(string requestId, Decision decision) =>
        Line(new() { ["type"] = "answer", ["id"] = requestId, ["decision"] = decision switch
        {
            Decision.Allow => "allow", Decision.Deny => "deny", Decision.AllowAlways => "allowAlways", Decision.Leave => "leave",
            _ => throw new ArgumentOutOfRangeException(nameof(decision)),
        } });

    /// <summary>The answers to a question, by each question's key: the options chosen and any text of the user's.</summary>
    public static string AnswerQuestions(string requestId, IReadOnlyDictionary<string, (IReadOnlyList<string> Selected, string? Custom)> answers)
    {
        var given = new JsonObject();
        foreach (var (key, answer) in answers)
            given[key] = new JsonObject { ["custom"] = answer.Custom, ["selected"] = new JsonArray(answer.Selected.Select(s => (JsonNode?)s).ToArray()) };
        return Line(new() { ["type"] = "answer", ["id"] = requestId, ["decision"] = "answer", ["answers"] = given });
    }

    public static string ApprovePlan(string requestId, bool acceptEdits) =>
        Line(new() { ["type"] = "answer", ["id"] = requestId, ["decision"] = "approvePlan", ["acceptEdits"] = acceptEdits });

    public static string KeepPlanning(string requestId, string? note) =>
        Line(new() { ["type"] = "answer", ["id"] = requestId, ["decision"] = "keepPlanning", ["note"] = note });

    /// <summary>Settings fields to change, by their names in Core's encoding; Core decodes and validates them.</summary>
    public static string UpdateSettings(JsonObject patch) =>
        Line(new() { ["type"] = "update-settings", ["patch"] = patch.DeepClone() });

    public enum Decision { Allow, Deny, AllowAlways, Leave }

    static readonly JsonSerializerOptions Options = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    static string Line(JsonObject message)
    {
        message["v"] = ProtocolVersion.Major;
        return Sorted(message)!.ToJsonString(Options) + "\n";
    }

    /// <summary>A copy with every object's keys in ordinal order, as the engine writes its own.</summary>
    static JsonNode? Sorted(JsonNode? node) => node switch
    {
        JsonObject o => new JsonObject(o.OrderBy(p => p.Key, StringComparer.Ordinal)
                                        .Select(p => KeyValuePair.Create(p.Key, Sorted(p.Value)))),
        JsonArray a => new JsonArray(a.Select(Sorted).ToArray()),
        null => null,
        _ => node.DeepClone(),
    };
}
