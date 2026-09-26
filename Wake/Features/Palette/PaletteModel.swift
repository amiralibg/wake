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
        let address = URLInput.url(from: query)
        if let address {
            sections.append(PaletteSection(title: nil, items: [.open(address)]))
        } else if results.isEmpty {
            // ↩ on typed words searches, as in every browser's address bar.
            sections.append(PaletteSection(title: nil, items: [.searchOnWeb(query)]))
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
        if address != nil || !results.isEmpty {
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
        let settings = BrowsingSettings.shared
        guard !query.isEmpty, URLInput.url(from: query) == nil,
              settings.showsSearchSuggestions || SearchKeyStore.hasBraveAPIKey else {
            results = []
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        let engine = settings.effectiveEngine
        let wantsSuggestions = settings.showsSearchSuggestions
        let key = SearchKeyStore.braveAPIKey
        searchTask = Task { [service] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            async let suggestions = wantsSuggestions ? service.suggestions(for: query, from: engine) : []
            async let results = service.results(for: query, key: key)
            let fetched = ((try? await suggestions) ?? [], (try? await results) ?? [])
            guard !Task.isCancelled else { return }
            self.suggestions = fetched.0
            self.results = fetched.1
            self.isSearching = false
        }
    }
}
