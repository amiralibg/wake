import Foundation

/// Recognises a search engine's results page and pulls out what was searched for.
/// Matching the results URL (rather than hooking ⌘K) also catches searches typed
/// into the engine's own search box, and works on history imported from other browsers.
enum SearchQuery {
    struct Match: Equatable, Sendable {
        let engine: String
        let query: String
    }

    private struct Pattern: Sendable {
        let engine: String
        let host: String
        let path: String
        let parameter: String
    }

    /// Every built-in engine, plus a few other common ones.
    private static let builtIn: [Pattern] = SearchEngine.allCases.compactMap { pattern(engine: $0.name, template: $0.template) } + [
        Pattern(engine: "DuckDuckGo", host: "html.duckduckgo.com", path: "/html", parameter: "q"),
        Pattern(engine: "YouTube", host: "youtube.com", path: "/results", parameter: "search_query"),
        Pattern(engine: "GitHub", host: "github.com", path: "/search", parameter: "q"),
        Pattern(engine: "Wikipedia", host: "wikipedia.org", path: "/w/index.php", parameter: "search"),
        Pattern(engine: "Amazon", host: "amazon.com", path: "/s", parameter: "k"),
        Pattern(engine: "Baidu", host: "baidu.com", path: "/s", parameter: "wd"),
        Pattern(engine: "Yandex", host: "yandex.com", path: "/search", parameter: "text"),
    ]

    static func match(_ url: URL, customTemplate: String? = nil) -> Match? {
        // Percent-encoded items, decoded by hand: results pages encode spaces as "+",
        // which URLComponents' decoded items leave as literal pluses.
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(), let encoded = components.percentEncodedQueryItems, !encoded.isEmpty
        else { return nil }
        let items = encoded.map {
            URLQueryItem(name: $0.name, value: $0.value.map { $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? $0 })
        }
        let path = components.path.isEmpty ? "/" : components.path
        var patterns = builtIn
        if let customTemplate, let custom = pattern(engine: "Custom", template: customTemplate) { patterns.insert(custom, at: 0) }
        for pattern in patterns where hostMatches(host, pattern.host) && path == pattern.path {
            guard let value = items.first(where: { $0.name == pattern.parameter })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
            else { continue }
            return Match(engine: pattern.engine, query: value)
        }
        return nil
    }

    private static func pattern(engine: String, template: String) -> Pattern? {
        guard let components = URLComponents(string: template.replacingOccurrences(of: "%s", with: "__wake__")),
              let host = components.host?.lowercased(),
              let parameter = components.queryItems?.first(where: { $0.value == "__wake__" })?.name
        else { return nil }
        return Pattern(engine: engine, host: host, path: components.path.isEmpty ? "/" : components.path, parameter: parameter)
    }

    /// "www.google.com" also matches google.de, google.co.uk and friends; other hosts
    /// match themselves and their subdomains (en.wikipedia.org).
    private static func hostMatches(_ host: String, _ pattern: String) -> Bool {
        let bare = pattern.hasPrefix("www.") ? String(pattern.dropFirst(4)) : pattern
        if bare == "google.com" {
            let parts = host.split(separator: ".")
            return parts.contains("google") && (parts.first == "google" || parts.first == "www")
        }
        return host == bare || host.hasSuffix("." + bare)
    }
}
