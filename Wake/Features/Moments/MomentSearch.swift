import Foundation

/// Plain-words search over moments: every word you type is looked for in the
/// title, your note, the highlighted text, the site and the page's saved text.
/// Words in what you wrote yourself count most.
enum MomentSearch {
    static func tokens(_ query: String) -> [String] {
        query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 || $0.first?.isNumber == true }
    }

    /// 0 when nothing matches. Moments missing some words still score, lower.
    static func score(_ moment: MomentRecord, tokens: [String]) -> Int {
        guard !tokens.isEmpty else { return 0 }
        let fields: [(String, Int)] = [
            (moment.title.lowercased(), 4),
            ((moment.note ?? "").lowercased(), 5),
            ((moment.selectedText ?? "").lowercased(), 4),
            (moment.host.lowercased(), 3),
            (moment.url.absoluteString.lowercased(), 1),
            (moment.contentText.lowercased(), 1),
        ]
        var score = 0
        var matched = 0
        for token in tokens {
            let best = fields.reduce(0) { best, field in field.0.contains(token) ? max(best, field.1) : best }
            if best > 0 { matched += 1 }
            score += best
        }
        guard matched > 0 else { return 0 }
        // All words found beats a few strong ones.
        return score + (matched == tokens.count ? 10 : 0)
    }
}
