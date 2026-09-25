import Foundation

/// One glanceable fact about a live page: "12:04 / 45:00", "$39 ↓", "3 unread",
/// "CI failed", "404". Deck cards show the most important one; trail chips a dot.
struct LiveChip: Equatable, Identifiable {
    enum Kind: String {
        case status, ci, errors, price, unread, media, changed
    }

    enum Tone: Equatable {
        case accent, good, bad, warning, neutral
    }

    let kind: Kind
    let text: String
    let symbol: String
    let tone: Tone
    /// 0…1, for media.
    var progress: Double?

    var id: Kind { kind }
}

/// What a page's scripts report about it, plus what WebKit tells us directly.
struct LiveState: Equatable {
    struct Media: Equatable {
        var current: Double
        var duration: Double
        var isPlaying: Bool
    }

    struct Price: Equatable {
        var amount: Double
        var currency: String
    }

    enum CI: String, Equatable {
        case passed, failed, pending
    }

    var media: Media?
    var price: Price?
    /// The page's text changed noticeably while you were looking elsewhere.
    var contentChanged = false
    var ci: CI?
    /// Main-frame HTTP status of the last navigation.
    var httpStatus: Int?

    /// Merges a `{ type: 'live', … }` message.
    mutating func merge(_ message: [String: Any]) {
        if let media = message["media"] as? [String: Any] {
            let duration = media["d"] as? Double ?? 0
            self.media = duration > 0 || media["playing"] as? Bool == true
                ? Media(current: media["t"] as? Double ?? 0, duration: duration, isPlaying: media["playing"] as? Bool ?? false)
                : nil
        } else if message["media"] is NSNull {
            media = nil
        }
        if let price = message["price"] as? [String: Any], let amount = price["amount"] as? Double, amount > 0 {
            self.price = Price(amount: amount, currency: price["currency"] as? String ?? "")
        }
        if let changed = message["changed"] as? Bool { contentChanged = changed }
        if let ci = message["ci"] as? String { self.ci = CI(rawValue: ci) }
    }
}
