import Foundation
import Observation

@MainActor
@Observable
final class PaletteModel {
    /// Where a chosen page opens.
    enum Target { case newColumn, currentColumn }

    var target: Target = .newColumn
    /// In the Deck the cards already show what's recent, so the list waits for typing.
    var showsRecentsWhenEmpty = true
    var query = "" {
        didSet { if query != oldValue { refresh() } }
    }
    var selection = 0
    private(set) var results: [SearchResult] = []
    private(set) var suggestions: [String] = []
    private(set) var isSearching = false

    /// Supplied by the browser; recents live there because pages report them.
    @ObservationIgnored var recents: () -> [RecentPage] = { [] }
    @ObservationIgnored private let service = SearchService()
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var sections: [PaletteSection] {
        let query = trimmedQuery
        let matchingRecents = recents()
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query) }
            .prefix(query.isEmpty ? 8 : 3)
            .map(PaletteItem.recent)

        if query.isEmpty {
            guard showsRecentsWhenEmpty, !matchingRecents.isEmpty else { return [] }
            return [PaletteSection(title: "Recent", items: matchingRecents)]
        }

        var sections: [PaletteSection] = []
        if let url = URLInput.url(from: query) {
            sections.append(PaletteSection(title: nil, items: [.open(url)]))
        }
        if !matchingRecents.isEmpty {
            sections.append(PaletteSection(title: "Recent", items: matchingRecents))
        }
        if !results.isEmpty {
            sections.append(PaletteSection(title: "Top results", items: results.map(PaletteItem.result)))
        }
        if !suggestions.isEmpty {
            sections.append(PaletteSection(title: "Refine", items: suggestions.prefix(4).map(PaletteItem.suggestion)))
        }
        if results.isEmpty, !isSearching, URLInput.url(from: query) == nil {
            sections.append(PaletteSection(title: nil, items: [.searchOnWeb(query)]))
        }
        return sections
    }

    var items: [PaletteItem] { sections.flatMap(\.items) }

    var selectedItem: PaletteItem? {
        let items = items
        return items.indices.contains(selection) ? items[selection] : items.first
    }

    func moveSelection(by delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    func reset() {
        searchTask?.cancel()
        query = ""
        results = []
        suggestions = []
        selection = 0
        isSearching = false
    }

    private func refresh() {
        searchTask?.cancel()
        selection = 0
        let query = trimmedQuery
        guard !query.isEmpty, URLInput.url(from: query) == nil else {
            results = []
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [service] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            async let suggestions = service.suggestions(for: query)
            async let results = service.results(for: query)
            let fetched = ((try? await suggestions) ?? [], (try? await results) ?? [])
            guard !Task.isCancelled else { return }
            self.suggestions = fetched.0
            self.results = fetched.1
            self.isSearching = false
        }
    }
}
