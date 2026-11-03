import Foundation

/// Decides whether typed text is an address or a search.
enum URLInput {
    static func url(from text: String) -> URL? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        // Paths may contain spaces, so they're checked first.
        if let file = fileURL(from: input) { return file }
        guard !input.contains(" ") else { return nil }

        if let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           ["http", "https", "about"].contains(scheme) {
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

    /// `file:` URLs, `~/…`, and absolute paths under the places files normally live.
    /// Other text starting with a slash stays a search ("/r/swift" isn't a file), and
    /// a recognised path never goes to the search engine's suggestions.
    private static func fileURL(from input: String) -> URL? {
        var text = input
        if text.count > 1, let quote = text.first, quote == "'" || quote == "\"", text.last == quote {
            text = String(text.dropFirst().dropLast())
        }
        if text.lowercased().hasPrefix("file:") {
            let encoded = text.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.union(["%", ":", "#", "?", "&", "="]))
            return encoded.flatMap(URL.init(string:))
        }
        // A path pasted from Terminal escapes its spaces.
        text = text.replacing("\\ ", with: " ")
        if text == "~" || text.hasPrefix("~/") {
            return URL(filePath: realHomeDirectory + text.dropFirst())
        }
        guard fileRoots.contains(where: { text.hasPrefix($0) }) else { return nil }
        return URL(filePath: text)
    }

    private static let fileRoots = ["/Users/", "/Volumes/", "/tmp/", "/private/", "/Applications/", "/Library/", "/System/", "/opt/"]

    /// The user's home. In the sandbox `NSHomeDirectory()` is the app's container.
    static var realHomeDirectory: String {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: directory)
    }

    private static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".")
        return octets.count == 4 && octets.allSatisfy { UInt8($0) != nil }
    }
}
