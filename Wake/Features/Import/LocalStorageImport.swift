import Foundation
import WebKit

/// localStorage from another browser: read from its files, written into WebKit by
/// briefly becoming each site.
///
/// Limitations, reported in the import sheet:
/// - Only localStorage moves across. IndexedDB, Cache Storage and service workers are
///   stored in engine-specific formats (Chromium's are LevelDB with V8-serialised
///   values), so WebKit can't take them; sites rebuild them as you use them.
/// - Safari's site data lives in its private container and isn't read.
enum LocalStorageReader {
    typealias Sites = [String: [(key: String, value: String)]]

    static let siteLimit = 2_000
    static let itemsPerSiteLimit = 2_000

    static func read(_ profile: BrowserProfile) -> Sites {
        switch profile.engine {
        case .chromium: chromium(profile.directory.appendingPathComponent("Local Storage/leveldb", isDirectory: true))
        case .firefox: firefox(profile.directory.appendingPathComponent("storage/default", isDirectory: true))
        case .safari: [:]
        }
    }

    /// Keys are `_` + origin + NUL + encoded key; strings start with a format byte:
    /// 0 for UTF-16LE, 1 for Latin-1.
    static func chromium(_ folder: URL) -> Sites {
        var sites: Sites = [:]
        for (key, value) in LevelDB.read(folder) {
            guard key.first == UInt8(ascii: "_"), let separator = key.firstIndex(of: 0) else { continue }
            guard let origin = String(data: key[key.index(after: key.startIndex)..<separator], encoding: .utf8),
                  isWebOrigin(origin),
                  let name = decode(key[key.index(after: separator)...]),
                  let text = decode(value)
            else { continue }
            if sites[origin, default: []].count < itemsPerSiteLimit { sites[origin, default: []].append((name, text)) }
        }
        return limited(sites)
    }

    /// One `ls/data.sqlite` per origin folder ("https+++example.com+8443"); values may
    /// be Snappy-compressed (compression_type 1) and are UTF-8 (conversion_type 1).
    static func firefox(_ folder: URL) -> Sites {
        var sites: Sites = [:]
        let manager = FileManager.default
        for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] {
            // "^userContextId=…" folders belong to container tabs.
            guard !name.contains("^"), let origin = firefoxOrigin(name) else { continue }
            let file = folder.appendingPathComponent(name).appendingPathComponent("ls/data.sqlite")
            guard manager.fileExists(atPath: file.path), let database = try? SQLiteDatabase(copying: file) else { continue }
            var items: [(key: String, value: String)] = []
            try? database.rows("SELECT key, value, compression_type, conversion_type FROM data LIMIT \(itemsPerSiteLimit)") { row in
                guard let key = row.text(0) else { return }
                var bytes = [UInt8](row.data(1))
                if row.int(2) == 1 { bytes = Snappy.decompress(bytes) ?? [] }
                let text = row.int(3) == 1
                    ? String(decoding: bytes, as: UTF8.self)
                    : String(data: Data(bytes), encoding: .utf16LittleEndian) ?? String(decoding: bytes, as: UTF8.self)
                items.append((key, text))
            }
            if !items.isEmpty { sites[origin] = items }
        }
        return limited(sites)
    }

    private static func decode(_ data: Data) -> String? {
        guard let format = data.first else { return nil }
        let body = data.dropFirst()
        switch format {
        case 0: return String(data: body, encoding: .utf16LittleEndian)
        case 1: return String(data: body, encoding: .isoLatin1)
        default: return nil
        }
    }

    /// "https+++example.com+8443" → "https://example.com:8443".
    static func firefoxOrigin(_ folder: String) -> String? {
        guard let range = folder.range(of: "+++") else { return nil }
        let scheme = folder[..<range.lowerBound]
        var host = String(folder[range.upperBound...])
        var port = ""
        if let plus = host.lastIndex(of: "+"), host[host.index(after: plus)...].allSatisfy(\.isNumber) {
            port = ":" + host[host.index(after: plus)...]
            host = String(host[..<plus])
        }
        let origin = "\(scheme)://\(host)\(port)"
        return isWebOrigin(origin) ? origin : nil
    }

    private static func isWebOrigin(_ origin: String) -> Bool {
        origin.hasPrefix("https://") || origin.hasPrefix("http://")
    }

    private static func limited(_ sites: Sites) -> Sites {
        sites.count <= siteLimit ? sites : Dictionary(uniqueKeysWithValues: sites.prefix(siteLimit).map { ($0.key, $0.value) })
    }
}

/// Writes localStorage into Wake's website data store. Each origin is "visited" with
/// `loadSimulatedRequest`: the page is a blank document served locally, so no request
/// reaches the site, yet it runs with the site's origin and storage.
@MainActor
final class LocalStorageWriter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var waiting: CheckedContinuation<Bool, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    /// Adds keys the site doesn't already have in Wake. Returns how many were written.
    func write(origin: String, items: [(key: String, value: String)]) async -> Int {
        guard let url = URL(string: origin + "/") else { return 0 }
        let loaded = await withCheckedContinuation { continuation in
            waiting = continuation
            webView.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<!doctype html><meta charset=utf-8>")
        }
        guard loaded else { return 0 }
        let result = try? await webView.callAsyncJavaScript("""
            let written = 0;
            for (const [key, value] of items) {
              try { if (localStorage.getItem(key) === null) { localStorage.setItem(key, value); written++; } } catch (e) { break; }
            }
            return written;
            """, arguments: ["items": items.map { [$0.key, $0.value] }], contentWorld: .defaultClient)
        return (result as? Int) ?? 0
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finish(true) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finish(false) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finish(false) }
    }

    private func finish(_ loaded: Bool) {
        waiting?.resume(returning: loaded)
        waiting = nil
    }
}
