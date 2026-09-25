import Foundation

struct SearchResult: Identifiable, Hashable, Sendable {
    let url: URL
    let title: String
    let snippet: String

    var id: URL { url }
    var host: String {
        let host = url.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Suggestions and real results, so search lives in the palette rather than a results page.
///
/// Limitation: there is no free, keyless web-search API. Suggestions come from
/// DuckDuckGo's public autocomplete endpoint. Results need a Brave Search API key
/// (free tier available), stored in the Keychain via Settings → Search. Without a key
/// the palette offers "Open results on DuckDuckGo" instead. We deliberately don't scrape
/// DuckDuckGo's HTML results: it answers non-browser clients with a bot check.
struct SearchService: Sendable {
    var session: URLSession = .shared

    func suggestions(for query: String) async throws -> [String] {
        var components = URLComponents(string: "https://duckduckgo.com/ac/")!
        components.queryItems = [.init(name: "q", value: query), .init(name: "type", value: "list")]
        let (data, _) = try await session.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [Any]
        let suggestions = json?.dropFirst().first as? [String] ?? []
        return suggestions.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
    }

    func results(for query: String) async throws -> [SearchResult] {
        guard let key = SearchKeyStore.braveAPIKey else { return [] }
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [.init(name: "q", value: query), .init(name: "count", value: "8")]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(BraveResponse.self, from: data).searchResults
    }

    static func resultsPageURL(for query: String) -> URL {
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [.init(name: "q", value: query)]
        return components.url!
    }
}

private struct BraveResponse: Decodable {
    struct Web: Decodable { let results: [Item] }
    struct Item: Decodable {
        let title: String
        let url: URL
        let description: String?
    }

    let web: Web?

    var searchResults: [SearchResult] {
        (web?.results ?? []).map {
            SearchResult(url: $0.url, title: $0.title.strippingTags, snippet: ($0.description ?? "").strippingTags)
        }
    }
}

private extension String {
    /// Brave wraps matched terms in <strong>; the palette renders plain text.
    var strippingTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}
