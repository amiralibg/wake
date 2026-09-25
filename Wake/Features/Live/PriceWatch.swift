import Foundation

/// Remembers the first price seen on each product page, so a later visit (or a
/// live update) can say whether it went down or up.
@MainActor
final class PriceWatch {
    static let shared = PriceWatch()

    private let key = "live.prices"
    private let limit = 300
    private var prices: [String: [String: Double]]

    private init() {
        prices = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
    }

    func firstPrice(for url: URL) -> Double? {
        prices[Self.key(for: url)]?["first"]
    }

    /// Records a sighting; the first one sticks.
    func observe(_ amount: Double, at url: URL) {
        let key = Self.key(for: url)
        guard prices[key] == nil else { return }
        if prices.count >= limit, let oldest = prices.min(by: { ($0.value["seen"] ?? 0) < ($1.value["seen"] ?? 0) })?.key {
            prices[oldest] = nil
        }
        prices[key] = ["first": amount, "seen": Date.now.timeIntervalSince1970]
        UserDefaults.standard.set(prices, forKey: self.key)
    }

    /// Host and path: query strings are mostly tracking, and the product is the path.
    private static func key(for url: URL) -> String {
        (url.host() ?? "") + url.path()
    }

    /// "$39.99", "€1,299"; a bare number when the page didn't say which currency.
    static func format(_ price: LiveState.Price) -> String {
        guard price.currency.count == 3 else { return price.amount.formatted(.number.precision(.fractionLength(0...2))) }
        return price.amount.formatted(.currency(code: price.currency).precision(.fractionLength(0...2)))
    }
}
