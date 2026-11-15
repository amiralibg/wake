import CryptoKit
import Foundation

/// The extension stores Wake installs from and keeps extensions updated through:
/// the Chrome Web Store (what Chrome, Arc, Dia, Brave and Helium use), Microsoft Edge
/// Add-ons, and Firefox Add-ons (what Firefox, Zen and Waterfox use).
///
/// Every package comes with a SHA-256 from the store over HTTPS, and Wake checks it
/// before installing. That matters for Edge, whose package host only works over plain
/// HTTP (its HTTPS certificate doesn't match), allowed by an ATS exception.
///
/// Limitation: the Chrome Web Store and Edge use Google's Omaha update protocol, which
/// is how their browsers fetch packages, not a documented public API. The Chrome Web
/// Store's terms offer its items "for use with Google Chrome"; see
/// docs/BROWSER_EXTENSIONS.md ▸ "Chrome Web Store and Firefox AMO packages".
enum ExtensionStore: String, Codable, CaseIterable, Sendable {
    case chrome, edge, firefox

    var title: String {
        switch self {
        case .chrome: "Chrome Web Store"
        case .edge: "Edge Add-ons"
        case .firefox: "Firefox Add-ons"
        }
    }

    var home: URL {
        switch self {
        case .chrome: URL(string: "https://chromewebstore.google.com/category/extensions")!
        case .edge: URL(string: "https://microsoftedge.microsoft.com/addons/category/Edge-Extensions")!
        case .firefox: URL(string: "https://addons.mozilla.org/firefox/extensions/")!
        }
    }

    /// The store item a listing page is about: a 32-letter id, or an AMO slug.
    static func item(in url: URL?) -> (store: ExtensionStore, id: String)? {
        guard let url, let host = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents
        func chromiumID() -> String? {
            guard let detail = parts.firstIndex(of: "detail") else { return nil }
            return parts.dropFirst(detail + 1).first { $0.count == 32 && $0.allSatisfy { ("a"..."p").contains(String($0)) } }
        }
        switch host {
        case "chromewebstore.google.com":
            return chromiumID().map { (.chrome, $0) }
        case "chrome.google.com" where url.path.hasPrefix("/webstore/"):
            return chromiumID().map { (.chrome, $0) }
        case "microsoftedge.microsoft.com" where url.path.hasPrefix("/addons/"):
            return chromiumID().map { (.edge, $0) }
        case "addons.mozilla.org":
            guard let addon = parts.firstIndex(of: "addon"), parts.indices.contains(addon + 1) else { return nil }
            let slug = parts[addon + 1]
            return slug == "/" || slug.isEmpty ? nil : (.firefox, slug)
        default:
            return nil
        }
    }

    /// The store's newest version of an item.
    struct Release: Sendable {
        let version: String
        let url: URL
        /// Hex SHA-256 of the package, from the store.
        let sha256: String?
        /// Firefox Add-ons' id for the add-on (its GUID), kept so imported Firefox
        /// extensions and store installs are recognised as the same thing.
        var guid: String?
    }

    enum Failure: LocalizedError {
        case notFound, badResponse(String), hashMismatch

        var errorDescription: String? {
            switch self {
            case .notFound: "The store doesn't offer this extension (it may be unlisted, or for its own browser only)."
            case .badResponse(let detail): "The store gave an unexpected answer (\(detail))."
            case .hashMismatch: "The downloaded package didn't match the store's checksum, so it wasn't installed."
            }
        }
    }

    /// Asks the store for the newest release. `currentVersion` "0" asks for any.
    func latest(_ id: String, currentVersion: String = "0.0.0.0") async throws -> Release? {
        switch self {
        case .chrome, .edge: return try await omahaCheck(id, currentVersion: currentVersion)
        case .firefox: return try await amoCheck(id)
        }
    }

    private func omahaCheck(_ id: String, currentVersion: String) async throws -> Release? {
        let base = self == .chrome
            ? "https://clients2.google.com/service/update2/crx"
            : "https://edge.microsoft.com/extensionwebstorebase/v1/crx"
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "response", value: "updatecheck"),
            URLQueryItem(name: "prodversion", value: "140.0.0.0"),
            URLQueryItem(name: "acceptformat", value: "crx2,crx3"),
            URLQueryItem(name: "x", value: "id=\(id)&v=\(currentVersion)&uc"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let check = OmahaResponse.parse(data)
        switch check?.status {
        case "ok":
            guard let codebase = check?.codebase, let url = URL(string: codebase), let version = check?.version else {
                throw Failure.badResponse("no package")
            }
            return Release(version: version, url: url, sha256: check?.sha256)
        case "noupdate":
            return nil
        default:
            throw Failure.notFound
        }
    }

    /// AMO's public API takes a slug or the add-on's GUID.
    private func amoCheck(_ id: String) async throws -> Release? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
        guard let api = URL(string: "https://addons.mozilla.org/api/v5/addons/addon/\(encoded)/") else { throw Failure.notFound }
        let (data, response) = try await URLSession.shared.data(from: api)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { throw Failure.notFound }
        struct Addon: Decodable {
            struct Version: Decodable {
                struct File: Decodable {
                    let url: URL
                    let hash: String?
                }
                let version: String
                let file: File
            }
            let guid: String?
            let current_version: Version?
        }
        guard let addon = try? JSONDecoder().decode(Addon.self, from: data), let current = addon.current_version else {
            throw Failure.badResponse("addons.mozilla.org")
        }
        let hash = current.file.hash.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        return Release(version: current.version, url: current.file.url, sha256: hash, guid: addon.guid)
    }

    /// Downloads a release and checks it against the store's checksum.
    static func download(_ release: Release) async throws -> URL {
        let file = try await ExtensionPackage.download(release.url)
        if let expected = release.sha256?.lowercased(), !expected.isEmpty {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                try? FileManager.default.removeItem(at: file)
                throw Failure.hashMismatch
            }
        }
        return file
    }

    /// Numeric, dot by dot: "4.9.135" is newer than "4.9.99".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// The `<app><updatecheck …/></app>` part of an Omaha (gupdate) answer.
private final class OmahaResponse: NSObject, XMLParserDelegate {
    var status: String?
    var codebase: String?
    var version: String?
    var sha256: String?

    static func parse(_ data: Data) -> OmahaResponse? {
        let response = OmahaResponse()
        let parser = XMLParser(data: data)
        parser.delegate = response
        return parser.parse() ? response : nil
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "app":
            // "error-unknownApplication" and friends live on <app>.
            if let status = attributes["status"], status != "ok" { self.status = status }
        case "updatecheck":
            if status == nil { status = attributes["status"] }
            codebase = attributes["codebase"]
            version = attributes["version"]
            sha256 = attributes["hash_sha256"]
        default:
            break
        }
    }
}
