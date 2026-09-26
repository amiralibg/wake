import CommonCrypto
import Foundation
import Security

/// A cookie read from another browser, ready to become an `HTTPCookie`.
struct ImportedCookie: Sendable {
    let domain: String
    let path: String
    let name: String
    let value: String
    /// Nil for a session cookie.
    let expires: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    /// "lax" or "strict"; nil when unspecified or None.
    let sameSite: String?

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain, .path: path.isEmpty ? "/" : path, .name: name, .value: value,
        ]
        if let expires { properties[.expires] = expires } else { properties[.discard] = "TRUE" }
        if isSecure { properties[.secure] = "TRUE" }
        if isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let sameSite { properties[.sameSitePolicy] = sameSite }
        return HTTPCookie(properties: properties)
    }
}

enum ImportFailure: LocalizedError {
    case unreadable(String)
    case needsFullDiskAccess
    case noCookieKey(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let what): "Couldn't read \(what)."
        case .needsFullDiskAccess: "macOS keeps Safari's data private. Give Wake Full Disk Access in System Settings ▸ Privacy & Security, then try again."
        case .noCookieKey(let browser): "Cookies were skipped: macOS didn't give Wake \(browser)'s cookie key from the keychain."
        }
    }
}

/// Reads another browser's files. Nothing here touches Wake's own data; it runs off
/// the main thread and hands plain values back.
enum BrowserReader {
    /// Most browsers keep 90 days; Firefox and Safari can keep years. The newest pages win.
    static let historyLimit = 25_000

    // MARK: History

    static func history(_ profile: BrowserProfile) throws -> [HistoryStore.ImportedVisit] {
        var visits: [HistoryStore.ImportedVisit] = []
        func add(_ url: String?, _ title: String?, _ count: Int64, _ date: Date) {
            guard let url, let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
            visits.append(.init(url: parsed, title: title ?? "", lastVisit: date, visitCount: Int(count)))
        }
        switch profile.engine {
        case .chromium:
            let database = try open(profile.directory.appendingPathComponent("History"), what: "\(profile.browser) history")
            try database.rows("SELECT url, title, visit_count, last_visit_time FROM urls WHERE last_visit_time > 0 ORDER BY last_visit_time DESC LIMIT \(historyLimit)") {
                add($0.text(0), $0.text(1), $0.int(2), chromiumDate($0.int(3)))
            }
        case .firefox:
            let database = try open(profile.directory.appendingPathComponent("places.sqlite"), what: "\(profile.browser) history")
            try database.rows("SELECT url, title, visit_count, last_visit_date FROM moz_places WHERE last_visit_date IS NOT NULL AND hidden = 0 ORDER BY last_visit_date DESC LIMIT \(historyLimit)") {
                add($0.text(0), $0.text(1), $0.int(2), Date(timeIntervalSince1970: Double($0.int(3)) / 1_000_000))
            }
        case .safari:
            guard BrowserCatalog.safariIsReadable else { throw ImportFailure.needsFullDiskAccess }
            let database = try open(profile.directory.appendingPathComponent("History.db"), what: "Safari history")
            try database.rows("""
                SELECT i.url, v.title, i.visit_count, MAX(v.visit_time) FROM history_items i
                JOIN history_visits v ON v.history_item = i.id GROUP BY i.id ORDER BY 4 DESC LIMIT \(historyLimit)
                """) {
                add($0.text(0), $0.text(1), $0.int(2), Date(timeIntervalSinceReferenceDate: $0.double(3)))
            }
        }
        return visits
    }

    // MARK: Searches

    /// Chromium records search terms itself; for every browser, results pages found in
    /// the imported history count too.
    static func searches(_ profile: BrowserProfile, visits: [HistoryStore.ImportedVisit]) -> [HistoryStore.ImportedSearch] {
        var searches: [HistoryStore.ImportedSearch] = []
        if case .chromium = profile.engine,
           let database = try? SQLiteDatabase(copying: profile.directory.appendingPathComponent("History")) {
            try? database.rows("""
                SELECT k.term, u.url, u.last_visit_time FROM keyword_search_terms k
                JOIN urls u ON u.id = k.url_id ORDER BY u.last_visit_time DESC LIMIT 10000
                """) { row in
                guard let term = row.text(0)?.trimmingCharacters(in: .whitespacesAndNewlines), !term.isEmpty,
                      let url = row.text(1).flatMap(URL.init(string:)) else { return }
                let engine = SearchQuery.match(url)?.engine ?? Self.engineName(url)
                searches.append(.init(query: term, engine: engine, url: url, date: chromiumDate(row.int(2))))
            }
        }
        for visit in visits {
            if let match = SearchQuery.match(visit.url) {
                searches.append(.init(query: match.query, engine: match.engine, url: visit.url, date: visit.lastVisit))
            }
        }
        return searches
    }

    private static func engineName(_ url: URL) -> String {
        var host = url.host() ?? "Search"
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    // MARK: Cookies

    static func cookies(_ profile: BrowserProfile) throws -> [ImportedCookie] {
        switch profile.engine {
        case .chromium(let services): try chromiumCookies(profile, services: services)
        case .firefox: try firefoxCookies(profile)
        case .safari: try SafariCookies.read()
        }
    }

    private static func chromiumCookies(_ profile: BrowserProfile, services: [String]) throws -> [ImportedCookie] {
        // Newer profiles keep cookies under Network/.
        let candidates = [profile.directory.appendingPathComponent("Network/Cookies"), profile.directory.appendingPathComponent("Cookies")]
        guard let file = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return [] }
        let database = try open(file, what: "\(profile.browser) cookies")
        // From version 24, the decrypted value starts with a SHA-256 of the domain.
        let version = Int(database.scalar("SELECT value FROM meta WHERE key = 'version'") ?? "") ?? 0
        var key: Data?
        var triedKey = false
        var cookies: [ImportedCookie] = []
        let now = Date.now
        try database.rows("SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, has_expires FROM cookies") { row in
            guard let domain = row.text(0), let name = row.text(1) else { return }
            var value = row.text(2) ?? ""
            let encrypted = row.data(3)
            if value.isEmpty, !encrypted.isEmpty {
                if !triedKey {
                    triedKey = true
                    key = ChromiumCrypto.key(services: services)
                }
                guard let key, let decrypted = ChromiumCrypto.decrypt(encrypted, key: key, stripsDomainHash: version >= 24) else { return }
                value = decrypted
            }
            let expires: Date? = row.int(9) == 0 ? nil : chromiumDate(row.int(5))
            if let expires, expires < now { return }
            let sameSite: String? = switch row.int(8) {
            case 1: "lax"
            case 2: "strict"
            default: nil
            }
            cookies.append(ImportedCookie(domain: domain, path: row.text(4) ?? "/", name: name, value: value, expires: expires,
                                          isSecure: row.int(6) != 0, isHTTPOnly: row.int(7) != 0, sameSite: sameSite))
        }
        if triedKey, key == nil { throw ImportFailure.noCookieKey(profile.browser) }
        return cookies
    }

    private static func firefoxCookies(_ profile: BrowserProfile) throws -> [ImportedCookie] {
        let database = try open(profile.directory.appendingPathComponent("cookies.sqlite"), what: "\(profile.browser) cookies")
        var cookies: [ImportedCookie] = []
        let now = Date.now
        // Container tabs keep their own cookies (non-empty originAttributes); Wake has one jar.
        try database.rows("SELECT host, name, value, path, expiry, isSecure, isHttpOnly, sameSite FROM moz_cookies WHERE originAttributes = ''") { row in
            guard let domain = row.text(0), let name = row.text(1) else { return }
            // Firefox switched expiry from seconds to milliseconds.
            let raw = Double(row.int(4))
            let expires = Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1_000 : raw)
            guard expires > now else { return }
            let sameSite: String? = switch row.int(7) {
            case 1: "lax"
            case 2: "strict"
            default: nil
            }
            cookies.append(ImportedCookie(domain: domain, path: row.text(3) ?? "/", name: name, value: row.text(2) ?? "", expires: expires,
                                          isSecure: row.int(5) != 0, isHTTPOnly: row.int(6) != 0, sameSite: sameSite))
        }
        return cookies
    }

    // MARK: Helpers

    private static func open(_ url: URL, what: String) throws -> SQLiteDatabase {
        do { return try SQLiteDatabase(copying: url) } catch { throw ImportFailure.unreadable(what) }
    }

    /// Chromium counts microseconds from 1601.
    static func chromiumDate(_ value: Int64) -> Date {
        Date(timeIntervalSince1970: Double(value) / 1_000_000 - 11_644_473_600)
    }
}

/// Chromium on macOS encrypts cookie values with AES-128-CBC, keyed from a password
/// it keeps in the login keychain ("Chrome Safe Storage").
///
/// Limitation: reading another app's keychain item asks you first (macOS shows
/// "Wake wants to use your confidential information…"). If you deny it, or macOS
/// won't hand it to a sandboxed app, cookies from that browser are skipped.
enum ChromiumCrypto {
    static func key(services: [String]) -> Data? {
        for service in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let password = result as? Data else { continue }
            return derive(password)
        }
        return nil
    }

    private static func derive(_ password: Data) -> Data? {
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let status = password.withUnsafeBytes { raw in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), raw.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                                 salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
        }
        return status == kCCSuccess ? Data(key) : nil
    }

    static func decrypt(_ encrypted: Data, key: Data, stripsDomainHash: Bool) -> String? {
        guard encrypted.count > 3, encrypted.prefix(3) == Data("v10".utf8) else { return nil }
        let payload = encrypted.dropFirst(3)
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var output = [UInt8](repeating: 0, count: payload.count + kCCBlockSizeAES128)
        var written = 0
        let status = key.withUnsafeBytes { keyBytes in
            payload.withUnsafeBytes { input in
                CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, iv, input.baseAddress, payload.count, &output, output.count, &written)
            }
        }
        guard status == kCCSuccess else { return nil }
        var plain = Data(output.prefix(written))
        if stripsDomainHash, plain.count >= 32 { plain = plain.dropFirst(32) }
        return String(data: plain, encoding: .utf8)
    }
}
