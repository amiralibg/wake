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
    /// Every column open anywhere except the one in focus, nearest first.
    @ObservationIgnored var openPages: () -> [OpenPage] = { [] }
    @ObservationIgnored private let service = SearchService()
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// `>` first lists only commands and settings, like a code editor's palette.
    static let commandPrefix = ">"

    /// Whether a command can run in the palette's window, for leaving out ones that can't.
    @ObservationIgnored var isAvailable: (WakeCommand) -> Bool = { _ in true }

    var isCommandMode: Bool { trimmedQuery.hasPrefix(Self.commandPrefix) }

    private func commandSections(for query: String, commandLimit: Int, settingLimit: Int) -> [PaletteSection] {
        let commands = SettingsSearch.commands(for: query, limit: commandLimit + 4)
            .filter { $0.isInPalette && isAvailable($0) }
            .prefix(commandLimit)
        // Shortcut entries would repeat the commands above.
        let settings = SettingsSearch.results(for: query, in: SettingsEntry.all.filter { $0.section != .shortcuts || $0.id == "columnMode" }, limit: settingLimit)
        var sections: [PaletteSection] = []
        if !commands.isEmpty { sections.append(PaletteSection(title: "Commands", items: commands.map(PaletteItem.command))) }
        if !settings.isEmpty { sections.append(PaletteSection(title: "Settings", items: settings.map(PaletteItem.setting))) }
        return sections
    }

    var sections: [PaletteSection] {
        let query = trimmedQuery
        if isCommandMode {
            let rest = String(query.dropFirst(Self.commandPrefix.count)).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                let all = WakeCommand.allCases.filter { $0.isInPalette && isAvailable($0) }
                return [PaletteSection(title: "Commands", items: all.map(PaletteItem.command))]
            }
            return commandSections(for: rest, commandLimit: 12, settingLimit: 6)
        }
        let matchingPages = query.isEmpty ? [] : openPages().filter { Self.matches(query, title: $0.title, url: $0.url) }
        let openURLs = Set(matchingPages.map(\.url))
        let matchingRecents = recents()
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query) }
            // Already listed as open: going back to it beats opening it twice.
            .filter { !openURLs.contains($0.url) }
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
        }
        // Words that match an open page go to it on ↩; the web search is one row down.
        if !matchingPages.isEmpty {
            sections.append(PaletteSection(title: "Open pages", items: matchingPages.prefix(6).map(PaletteItem.openPage)))
        }
        if address == nil, results.isEmpty {
            // ↩ on typed words searches, as in every browser's address bar.
            sections.append(PaletteSection(title: nil, items: [.searchOnWeb(query)]))
        }
        // Typed words that name a command ("reload", "zen") list it below the search,
        // so ↩ still searches; ↓ reaches it. Not for addresses.
        if address == nil, query.count >= 2 {
            sections += commandSections(for: query, commandLimit: 3, settingLimit: 2)
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

    /// Every word has to appear in the title or the address.
    private static func matches(_ query: String, title: String, url: URL) -> Bool {
        let address = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            title.localizedCaseInsensitiveContains($0) || address.localizedCaseInsensitiveContains($0)
        }
    }

    private func refresh() {
        searchTask?.cancel()
        selection = 0
        let query = trimmedQuery
        let settings = BrowsingSettings.shared
        guard !query.isEmpty, !query.hasPrefix(Self.commandPrefix), URLInput.url(from: query) == nil,
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
