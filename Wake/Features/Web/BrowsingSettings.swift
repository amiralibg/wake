import Foundation
import Observation

/// How browsing behaves: where links open, what comes back at launch, where searches go.
/// Shared, because the trail reads it deep inside page callbacks.
@MainActor
@Observable
final class BrowsingSettings {
    static let shared = BrowsingSettings()

    /// On: a clicked link opens as a new column (the trail). Off: it replaces the page.
    var linksOpenInNewColumn: Bool { didSet { defaults.set(linksOpenInNewColumn, forKey: "browsing.linksInNewColumn") } }
    /// On: a new window resumes your most recent thread. Off: it starts empty.
    var restoresLastThread: Bool { didSet { defaults.set(restoresLastThread, forKey: "browsing.restoreThread") } }
    /// On: the app capsule stays out of the way and slides in at the left edge,
    /// like it does in Zen. Off: it keeps a slim strip beside the pages.
    var capsuleHidesAtEdge: Bool { didSet { defaults.set(capsuleHidesAtEdge, forKey: "browsing.capsuleHides") } }

    /// Where typed searches go.
    var searchEngine: SearchEngine { didSet { defaults.set(searchEngine.rawValue, forKey: "search.engine") } }
    /// The results URL for `.custom`, with `%s` for the query.
    var customSearchTemplate: String { didSet { defaults.set(customSearchTemplate, forKey: "search.customTemplate") } }
    /// Ask the engine for suggestions while you type in ⌘K. Off, nothing leaves Wake until ↩.
    var showsSearchSuggestions: Bool { didSet { defaults.set(showsSearchSuggestions, forKey: "search.suggestions") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        linksOpenInNewColumn = defaults.object(forKey: "browsing.linksInNewColumn") as? Bool ?? true
        restoresLastThread = defaults.object(forKey: "browsing.restoreThread") as? Bool ?? true
        capsuleHidesAtEdge = defaults.bool(forKey: "browsing.capsuleHides")
        searchEngine = SearchEngine(rawValue: defaults.string(forKey: "search.engine") ?? "") ?? .duckDuckGo
        customSearchTemplate = defaults.string(forKey: "search.customTemplate") ?? ""
        showsSearchSuggestions = defaults.object(forKey: "search.suggestions") as? Bool ?? true
    }

    /// The engine actually used: a custom engine without a valid template falls back to DuckDuckGo.
    var effectiveEngine: SearchEngine {
        searchEngine == .custom && !SearchEngine.isValidTemplate(customSearchTemplate) ? .duckDuckGo : searchEngine
    }

    var searchTemplate: String {
        effectiveEngine == .custom ? customSearchTemplate.trimmingCharacters(in: .whitespaces) : effectiveEngine.template
    }

    /// Shown in ⌘K: "Search Google for …".
    var searchName: String {
        guard effectiveEngine == .custom else { return effectiveEngine.name }
        let host = URL(string: searchTemplate)?.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var searchHost: String { SearchEngine.url(from: searchTemplate, query: "")?.host() ?? "" }

    func searchURL(for query: String) -> URL {
        SearchEngine.url(from: searchTemplate, query: query)
            ?? SearchEngine.url(from: SearchEngine.duckDuckGo.template, query: query)!
    }
}
