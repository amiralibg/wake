import Foundation

/// Bringing passwords in and taking them out.
///
/// - Chromium browsers (Chrome, Arc, Brave, Edge…): read straight from the
///   profile's `Login Data`, decrypted with the same "… Safe Storage" key as their
///   cookies. macOS asks first, as it does for the cookie import.
/// - Everything else (Safari and the Passwords app, Firefox, 1Password,
///   Bitwarden): their CSV export. Limitation: Firefox's own `logins.json` is
///   encrypted through NSS with a key in `key4.db`; Wake doesn't read that, so
///   Firefox and Zen go through File ▸ Export Logins in Firefox.
enum PasswordImport {
    enum Failure: LocalizedError {
        case noLogins(String)
        case noKey(String)
        case unreadableCSV

        var errorDescription: String? {
            switch self {
            case .noLogins(let browser): "\(browser) has no saved passwords in this profile."
            case .noKey(let browser): "Wake couldn't get \(browser)'s password key from the Keychain. Allow access when macOS asks, or export a CSV from \(browser) instead."
            case .unreadableCSV: "This file doesn't look like a password export: it needs url, username and password columns."
            }
        }
    }

    /// Chromium profiles on this Mac that have a password database.
    static func chromiumProfiles() -> [BrowserProfile] {
        BrowserCatalog.profiles().filter { profile in
            guard case .chromium = profile.engine else { return false }
            return FileManager.default.fileExists(atPath: profile.directory.appendingPathComponent("Login Data").path)
        }
    }

    /// Reads and decrypts a Chromium profile's logins. Blocks while macOS asks for
    /// the keychain key, so call it off the main actor.
    static func chromium(_ profile: BrowserProfile) throws -> [SavedLogin] {
        guard case .chromium(let services) = profile.engine else { return [] }
        let files = ["Login Data", "Login Data For Account"].map { profile.directory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        var key: Data?
        var triedKey = false
        var logins: [SavedLogin] = []
        for file in files {
            let database = try SQLiteDatabase(copying: file)
            try database.rows("SELECT origin_url, username_value, password_value, date_created, date_last_used FROM logins WHERE blacklisted_by_user = 0") { row in
                guard let address = row.text(0), let url = URL(string: address),
                      url.scheme == "https" || url.scheme == "http", let origin = PasswordVault.origin(of: url) else { return }
                let encrypted = row.data(2)
                guard !encrypted.isEmpty else { return }
                if !triedKey {
                    triedKey = true
                    key = ChromiumCrypto.key(services: services)
                }
                guard let key, let password = ChromiumCrypto.decrypt(encrypted, key: key, stripsDomainHash: false) else { return }
                var login = SavedLogin(origin: origin, username: row.text(1) ?? "", password: password, source: profile.browser)
                if row.int(3) > 0 { login.created = BrowserReader.chromiumDate(row.int(3)) }
                if row.int(4) > 0 { login.lastUsed = BrowserReader.chromiumDate(row.int(4)) }
                logins.append(login)
            }
        }
        if triedKey, key == nil { throw Failure.noKey(profile.browser) }
        if logins.isEmpty { throw Failure.noLogins(profile.browser) }
        return logins
    }

    // MARK: CSV

    /// Chrome (name,url,username,password,note), Safari (Title,URL,Username,
    /// Password,Notes,OTPAuth), Firefox (url,username,password,…), 1Password and
    /// Bitwarden (login_uri, login_username, login_password) exports.
    static func csv(_ text: String, source: String) throws -> [SavedLogin] {
        var rows = parseCSV(text)
        guard !rows.isEmpty else { throw Failure.unreadableCSV }
        let header = rows.removeFirst().map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func column(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
        guard let urlColumn = column(["url", "login_uri", "website", "web site", "origin", "hostname"]),
              let userColumn = column(["username", "login_username", "user name", "login", "email"]),
              let passwordColumn = column(["password", "login_password"]) else { throw Failure.unreadableCSV }
        return rows.compactMap { fields in
            guard fields.count > max(urlColumn, userColumn, passwordColumn) else { return nil }
            var address = fields[urlColumn].trimmingCharacters(in: .whitespaces)
            if !address.contains("://") { address = "https://" + address }
            guard let url = URL(string: address), let origin = PasswordVault.origin(of: url), !fields[passwordColumn].isEmpty else { return nil }
            return SavedLogin(origin: origin, username: fields[userColumn], password: fields[passwordColumn], source: source)
        }
    }

    /// Chrome's format, which Safari, Firefox, 1Password and Bitwarden all import.
    static func csv(_ logins: [SavedLogin]) -> String {
        let quote = { (value: String) -> String in
            value.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
        }
        let lines = logins.map { [$0.displayHost, $0.origin, $0.username, $0.password, ""].map(quote).joined(separator: ",") }
        return (["name,url,username,password,note"] + lines).joined(separator: "\n") + "\n"
    }

    /// RFC 4180: quoted fields, doubled quotes, newlines inside quotes.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()
        while let character = pending {
            pending = iterator.next()
            if inQuotes {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"": inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                field = ""
                if row != [""] { rows.append(row) }
                row = []
            default: field.append(character)
            }
        }
        row.append(field)
        if row != [""] { rows.append(row) }
        return rows
    }
}
