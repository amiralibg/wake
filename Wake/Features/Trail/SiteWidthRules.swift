import Foundation
import Observation

/// One site's minimum column width.
struct SiteWidthRule: Codable, Identifiable, Hashable {
    var id = UUID()
    /// `github.com/*`: host and path, with `*` for anything.
    var pattern: String
    var minWidth: Double
}

/// Matching an address against a rule. Mirrored by `desktop/ui/src/model/site-pattern.ts`.
enum SitePattern {
    /// Scheme and a leading `www.` don't count; a pattern with no path covers the whole site.
    static func matches(_ pattern: String, url: URL) -> Bool {
        guard let subject = subject(of: url) else { return false }
        return glob(normalized(pattern), subject)
    }

    /// `https://www.GitHub.com` and `github.com` are the same rule: `github.com/*`.
    static func normalized(_ pattern: String) -> String {
        var text = pattern.trimmingCharacters(in: .whitespaces)
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        let slash = text.firstIndex(of: "/") ?? text.endIndex
        var host = text[..<slash].lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = String(text[slash...])
        return host + (path.isEmpty || path == "/" ? "/*" : path)
    }

    /// How specific a pattern is: the longest match wins when several apply.
    static func specificity(_ pattern: String) -> Int {
        normalized(pattern).count { $0 != "*" }
    }

    private static func subject(of url: URL) -> String? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), var host = url.host()?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if let port = url.port { host += ":\(port)" }
        let path = url.path(percentEncoded: true)
        return host + (path.isEmpty ? "/" : path)
    }

    /// `*` matches any run of characters, slashes included.
    private static func glob(_ pattern: String, _ text: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return pattern == text }
        guard text.hasPrefix(parts[0]) else { return false }
        var rest = text.dropFirst(parts[0].count)
        for part in parts.dropFirst().dropLast() where !part.isEmpty {
            guard let range = rest.range(of: part) else { return false }
            rest = rest[range.upperBound...]
        }
        return rest.hasSuffix(parts[parts.count - 1])
    }
}

/// Minimum column widths by address pattern. Shared, because every trail reads them.
@MainActor
@Observable
final class SiteWidthRules {
    static let shared = SiteWidthRules()

    var rules: [SiteWidthRule] { didSet { save() } }

    @ObservationIgnored private let defaultsKey = "browsing.siteWidths"

    private init() {
        let data = UserDefaults.standard.data(forKey: defaultsKey)
        rules = data.flatMap { try? JSONDecoder().decode([SiteWidthRule].self, from: $0) } ?? []
    }

    /// Only web addresses have a site to remember.
    nonisolated static func canHaveRule(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host() != nil
    }

    func minimumWidth(for url: URL) -> CGFloat? {
        rules
            .filter { $0.minWidth > 0 && !$0.pattern.isEmpty && SitePattern.matches($0.pattern, url: url) }
            .max { SitePattern.specificity($0.pattern) < SitePattern.specificity($1.pattern) }
            .map { CGFloat($0.minWidth) }
    }

    /// Whole-site rule for the address, replacing what's there.
    func remember(width: CGFloat, for url: URL) {
        guard Self.canHaveRule(url), let host = url.host() else { return }
        let port = url.port.map { ":\($0)" } ?? ""
        let pattern = SitePattern.normalized(host + port)
        rules.removeAll { SitePattern.normalized($0.pattern) == pattern }
        rules.append(SiteWidthRule(pattern: pattern, minWidth: Double(width.rounded())))
    }

    /// Removes every rule that applies to the address.
    func forget(_ url: URL) {
        rules.removeAll { SitePattern.matches($0.pattern, url: url) }
    }

    func add() {
        rules.append(SiteWidthRule(pattern: "", minWidth: 800))
    }

    func remove(_ rule: SiteWidthRule) {
        rules.removeAll { $0.id == rule.id }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: defaultsKey)
    }
}
