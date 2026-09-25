import Foundation

/// Decides whether typed text is an address or a search.
enum URLInput {
    static func url(from text: String) -> URL? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !input.contains(" ") else { return nil }

        if let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about"].contains(scheme) {
            return url
        }

        let hostPart = input.split(separator: "/", maxSplits: 1).first.map(String.init) ?? input
        let host = hostPart.split(separator: ":").first.map(String.init) ?? hostPart
        if isLocal(host) {
            return URL(string: "http://" + input)
        }
        let labels = host.split(separator: ".")
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2,
              tld.allSatisfy(\.isLetter) else { return nil }
        return URL(string: "https://" + input)
    }

    private static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".")
        return octets.count == 4 && octets.allSatisfy { UInt8($0) != nil }
    }
}
