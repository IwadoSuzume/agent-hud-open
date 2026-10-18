// One card model per waiting request, kept while it waits and given the engine's newer copy of it with each state, so
// the islands keep their controls (and a half-typed answer) across states; gone with its request, its draft too.
using System.Collections.Generic;
using System.Linq;
using AgentHUD.Protocol;
using AgentHUD.Shell;

namespace AgentHUD;

sealed class Cards(ShellModel model)
{
    readonly Drafts drafts = new();
    readonly Dictionary<string, CardModel> cards = [];

    public void Sync(IReadOnlyList<Approval> waiting)
    {
        var ids = waiting.Select(r => r.Id).ToHashSet();
        foreach (var gone in cards.Keys.Where(id => !ids.Contains(id)).ToList()) cards.Remove(gone);
        drafts.Keep(ids);
        foreach (var request in waiting)
        {
            if (cards.TryGetValue(request.Id, out var card)) { if (!Equals(card.Request, request)) card.Update(request); }
            else cards[request.Id] = new CardModel(request, model, drafts);
        }
    }

    public CardModel? Card(string id) => cards.GetValueOrDefault(id);
}
