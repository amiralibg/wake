import Foundation
import SwiftData

/// Something you searched for, with the engine's results page to go back to.
@Model
final class SearchRecord {
    var query: String
    /// The engine's name ("Google", "DuckDuckGo"…).
    var engine: String
    var url: URL
    var searchedAt: Date
    /// The browser this was imported from; nil for Wake's own.
    var source: String?

    init(query: String, engine: String, url: URL, searchedAt: Date = .now, source: String? = nil) {
        self.query = query
        self.engine = engine
        self.url = url
        self.searchedAt = searchedAt
        self.source = source
    }
}
