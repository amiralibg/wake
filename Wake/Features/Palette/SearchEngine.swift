import Foundation

/// Where a search goes when you press ↩ on typed text, and where ⌘K's suggestions
/// come from. DuckDuckGo is the default because it doesn't profile searches.
enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
    case duckDuckGo, google, brave, bing, ecosia, startpage, kagi, perplexity, yahoo, custom

    var id: Self { self }

    var name: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .brave: "Brave Search"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        case .startpage: "Startpage"
        case .kagi: "Kagi"
        case .perplexity: "Perplexity"
        case .yahoo: "Yahoo"
        case .custom: "Custom"
        }
    }

    /// A line under the name in the picker.
    var tagline: String {
        switch self {
        case .duckDuckGo: "Private, no tracking"
        case .google: "The biggest index"
        case .brave: "Independent index"
        case .bing: "Microsoft"
        case .ecosia: "Plants trees"
        case .startpage: "Google results, privately"
        case .kagi: "Paid, ad-free"
        case .perplexity: "Answers with sources"
        case .yahoo: "Powered by Bing"
        case .custom: "Your own URL"
        }
    }

    /// The results page, with `%s` standing for the query.
    var template: String {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/?q=%s"
        case .google: "https://www.google.com/search?q=%s"
        case .brave: "https://search.brave.com/search?q=%s"
        case .bing: "https://www.bing.com/search?q=%s"
        case .ecosia: "https://www.ecosia.org/search?q=%s"
        case .startpage: "https://www.startpage.com/do/search?q=%s"
        case .kagi: "https://kagi.com/search?q=%s"
        case .perplexity: "https://www.perplexity.ai/search?q=%s"
        case .yahoo: "https://search.yahoo.com/search?p=%s"
        case .custom: ""
        }
    }

    /// An OpenSearch suggestions endpoint (`["query", ["suggestion", …]]`).
    /// Engines without a public one (Startpage, Kagi, Perplexity) and custom engines
    /// borrow DuckDuckGo's, which doesn't log who asked.
    var suggestionsTemplate: String {
        switch self {
        case .google: "https://suggestqueries.google.com/complete/search?client=firefox&ie=utf-8&oe=utf-8&q=%s"
        case .brave: "https://search.brave.com/api/suggest?q=%s"
        case .bing, .yahoo: "https://api.bing.com/osjson.aspx?query=%s"
        case .ecosia: "https://ac.ecosia.org/autocomplete?type=list&q=%s"
        case .duckDuckGo, .startpage, .kagi, .perplexity, .custom: "https://duckduckgo.com/ac/?type=list&q=%s"
        }
    }

    /// For the picker. Brave's search host serves no /favicon.ico (and AsyncImage
    /// can't draw SVG), so it borrows brave.com's.
    var iconURL: URL? {
        switch self {
        case .brave: URL(string: "https://brave.com/favicon.ico")
        case .custom: nil
        default: URL(string: template).flatMap { $0.host() }.flatMap { URL(string: "https://\($0)/favicon.ico") }
        }
    }

    static func url(from template: String, query: String) -> URL? {
        guard template.contains("%s") else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }

    /// A custom template is usable when it's an http(s) URL with a `%s` placeholder.
    static func isValidTemplate(_ template: String) -> Bool {
        guard let url = url(from: template.trimmingCharacters(in: .whitespaces), query: "wake"),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil
        else { return false }
        return true
    }
}
