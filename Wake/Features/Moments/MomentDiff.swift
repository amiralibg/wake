import CryptoKit
import Foundation

/// Compares a page's text now with its text when the moment was saved.
enum MomentDiff {
    /// Visible text is capped so a huge page doesn't bloat the store.
    static let maxTextLength = 40_000

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(normalized(text).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// A short description of what changed, or `nil` when the difference is just
    /// noise (a clock, a counter, a rotated ad line).
    static func summary(old: String, new: String) -> String? {
        let before = normalized(old)
        let after = normalized(new)
        guard before != after else { return nil }

        let oldPrices = prices(in: before)
        let newPrices = prices(in: after)
        if !oldPrices.isEmpty, !newPrices.isEmpty, oldPrices.first != newPrices.first,
           let was = oldPrices.first.flatMap(amount), let now = newPrices.first.flatMap(amount) {
            if now < was { return "price ↓ \(newPrices[0])" }
            if now > was { return "price ↑ \(newPrices[0])" }
        }

        let oldLines = Set(before.split(separator: "\n").map(String.init))
        let newLines = Set(after.split(separator: "\n").map(String.init))
        let added = newLines.subtracting(oldLines)
        let removed = oldLines.subtracting(newLines)
        let changedCharacters = (added.map(\.count) + removed.map(\.count)).reduce(0, +)
        // Below this, it's a timestamp or a view counter, not a change worth telling.
        guard changedCharacters >= 80 else { return nil }
        if removed.isEmpty || added.count >= removed.count * 2 { return "new content" }
        if added.isEmpty { return "content removed" }
        return "text changed"
    }

    static func prices(in text: String) -> [String] {
        // A literal per call: Regex isn't Sendable, so it can't be a shared static.
        let pattern = #/(?:[$€£¥₹]\s?\d[\d,]*(?:\.\d{1,2})?|\d[\d,]*(?:\.\d{1,2})?\s?(?:USD|EUR|GBP|€|\$))/#
        return text.matches(of: pattern).map { String($0.output) }
    }

    private static func amount(_ price: String) -> Double? {
        let digits = price.filter { $0.isNumber || $0 == "." }
        return Double(digits)
    }
}
