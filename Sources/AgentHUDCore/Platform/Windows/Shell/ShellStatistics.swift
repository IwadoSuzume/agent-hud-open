#if os(Windows)
import AgentHUDSupport
import Foundation

/// The statistics window's first card on Windows (protocol 1.3, `statistics`): Today, the last seven days and the last
/// thirty, as the macOS Desktop's `UsagePeriodsCard` (Stats/Tokens/UsagePeriodsCard.swift) makes them from the store —
/// the selected kinds' tokens, their cost at API list prices, the cache's share of the prompts, and the models that
/// spent the most, the rest counted together. Every figure and word is made here by Core's rules and formatting, each
/// `L10n.text` call written as the Desktop writes it (`ShellProtocolTests` finds them in its sources); the shell draws.
enum ShellStatistics {
    /// Models named in each period; the rest are counted together.
    static let listed = 3

    @MainActor
    static func message(store: UsageStore) -> JSONValue {
        .object([
            "v": .integer(ShellProtocol.major), "type": .string("statistics"),
            "generatedAt": store.report.map { .integer(RecordCoding.milliseconds($0.generatedAt)) } ?? .null,
            "title": .string(L10n.text("近期用量", "Recent usage")),
            "dimensions": .string(store.tokenDimensions.label),
            "periods": .array(UsagePeriods.Period.allCases.map { column($0, store: store) }),
        ])
    }

    @MainActor
    private static func column(_ period: UsagePeriods.Period, store: UsageStore) -> JSONValue {
        let tokens = store.periodTokens(period), dimensions = store.tokenDimensions
        let counts = tokens.mapValues(dimensions.count), total = counts.values.reduce(0, +)
        let ranked = store.consumers.filter { (counts[$0.id] ?? 0) > 0 }.sorted { counts[$0.id]! > counts[$1.id]! }
        let cost = store.periodListCost(period)
        let hits = tokens.values.reduce(TokenKinds(), +).cacheHitRate
        let rest = ranked.dropFirst(Self.listed)
        return .object([
            "period": .string(period.rawValue), "label": .string(period.label),
            "total": .string(total > 0 ? TokenFormat.short(total) : "—"),
            "cost": cost.map { .string($0.text) } ?? .null,
            "cacheHits": hits.map { .string(L10n.text("缓存命中 ", "Cache hits ") + TokenFormat.percent($0 * 100)) } ?? .null,
            // Every model of the period with its share, for the bar; the first `listed` are named below it.
            "models": .array(ranked.map { consumer in
                .object(["id": .string(consumer.id), "name": .string(consumer.name), "displayName": .string(consumer.displayName),
                         "vendor": .string(consumer.vendor), "mark": .string(VendorMark.key(consumer.vendor)),
                         "tokens": .string(TokenFormat.short(counts[consumer.id]!)),
                         "share": .number(Double(counts[consumer.id]!) / Double(max(total, 1))),
                         "paletteIndex": .integer(Int64(store.consumerPaletteIndex(consumer.id)))])
            }),
            "listed": .integer(Int64(min(Self.listed, ranked.count))),
            "rest": rest.isEmpty ? .null : .object([
                "text": .string(L10n.text("其余 \(rest.count) 个", "\(rest.count) more")),
                "tokens": .string(TokenFormat.short(rest.reduce(0) { $0 + counts[$1.id]! })),
            ]),
        ])
    }
}
#endif
