import Foundation

struct RecentPage: Identifiable, Hashable {
    let url: URL
    var title: String
    var visitedAt: Date

    var id: URL { url }
}

/// A column that's open somewhere: in this thread, another thread or another window.
struct OpenPage: Hashable {
    let threadID: UUID
    /// The live column; nil for a thread whose pages aren't loaded right now.
    let pageID: BrowserPage.ID?
    /// Its place in a saved thread, for when the thread comes back.
    let columnIndex: Int
    let url: URL
    let title: String
    /// Set when the page is in another thread.
    let threadTitle: String?
}

enum PaletteItem: Identifiable, Hashable {
    case open(URL)
    case result(SearchResult)
    case suggestion(String)
    case recent(RecentPage)
    case openPage(OpenPage)
    case searchOnWeb(String)

    var id: String {
        switch self {
        case .open(let url): "open:\(url)"
        case .result(let result): "result:\(result.url)"
        case .suggestion(let text): "suggest:\(text)"
        case .recent(let page): "recent:\(page.url)"
        case .openPage(let page): "page:\(page.threadID):\(page.columnIndex):\(page.url)"
        case .searchOnWeb(let query): "web:\(query)"
        }
    }
}

struct PaletteSection: Identifiable {
    let title: String?
    let items: [PaletteItem]

    var id: String { title ?? items.first?.id ?? "" }
}
