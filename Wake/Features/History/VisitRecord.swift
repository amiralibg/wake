import Foundation
import SwiftData

/// One entry per URL, bumped on each visit. Feeds "Recent" in the palette and History.
@Model
final class VisitRecord {
    @Attribute(.unique) var url: URL
    var title: String
    var visitedAt: Date
    var visitCount: Int
    /// The browser this was imported from ("Chrome", "Firefox"…); nil for Wake's own.
    var source: String?
    /// The address lowercased, without its scheme: what History's search matches.
    /// A predicate can't look inside a `URL`, so without this the store couldn't
    /// search addresses itself. Empty for visits recorded before it existed, until
    /// `HistoryStore` fills them in. (Not optional: SwiftData can't turn `?? ""`
    /// inside a predicate into SQL, and the default lets older stores migrate.)
    var address: String = ""

    init(url: URL, title: String, visitedAt: Date = .now, visitCount: Int = 1, source: String? = nil) {
        self.url = url
        self.address = Self.address(of: url)
        self.title = title
        self.visitedAt = visitedAt
        self.visitCount = visitCount
        self.source = source
    }

    static func address(of url: URL) -> String {
        let string = url.absoluteString.lowercased()
        guard let scheme = url.scheme, string.hasPrefix(scheme.lowercased() + "://") else { return string }
        return String(string.dropFirst(scheme.count + 3))
    }
}
