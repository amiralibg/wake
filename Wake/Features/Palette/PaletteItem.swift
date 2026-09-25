import Foundation

struct RecentPage: Identifiable, Hashable {
    let url: URL
    var title: String
    var visitedAt: Date

    var id: URL { url }
}

enum PaletteItem: Identifiable, Hashable {
    case open(URL)
    case result(SearchResult)
    case suggestion(String)
    case recent(RecentPage)
    case searchOnWeb(String)

    var id: String {
        switch self {
        case .open(let url): "open:\(url)"
        case .result(let result): "result:\(result.url)"
        case .suggestion(let text): "suggest:\(text)"
        case .recent(let page): "recent:\(page.url)"
        case .searchOnWeb(let query): "web:\(query)"
        }
    }
}

struct PaletteSection: Identifiable {
    let title: String?
    let items: [PaletteItem]

    var id: String { title ?? items.first?.id ?? "" }
}
