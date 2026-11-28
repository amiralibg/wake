import CryptoKit
import Foundation
import LocalAuthentication
import Observation

/// A saved sign-in.
struct SavedLogin: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    /// Scheme, host and port: "https://github.com".
    var origin: String
    var username: String
    var password: String
    var created = Date.now
    var modified = Date.now
    var lastUsed: Date?
    var timesUsed = 0
    /// Where it came from, for imported ones ("Chrome").
    var source: String?

    var host: String { URL(string: origin)?.host() ?? origin }

    /// The host without "www.", for showing.
    var displayHost: String { host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
}

/// Wake's passwords: one AES-GCM sealed file in the app's container, keyed by a
/// random 256-bit key kept in the Keychain. Nothing is read until a password is
/// needed (a login form, or Settings ▸ Passwords), so launch doesn't pay for it.
///
/// Limitation: the Touch ID check before filling or showing a password is Wake's own
/// (LocalAuthentication), not a Keychain access control on the key. Binding the key
/// to biometrics needs the data-protection keychain, which needs a team-signed app
/// with a keychain access group; Wake is ad-hoc signed.
@MainActor
@Observable
final class PasswordVault {
    static let shared = PasswordVault()

    private struct Contents: Codable {
        var logins: [SavedLogin] = []
        /// Hosts where "Never" was chosen.
        var neverSave: [String] = []
    }

    private var contents = Contents()
    private(set) var isLoaded = false
    /// Set when the file exists but couldn't be opened (its key is gone).
    private(set) var loadError: String?
    /// Something to tell you about the vault, shown in Settings ▸ Passwords.
    private(set) var notice: String?
    /// When Touch ID last succeeded; filling within a few minutes doesn't ask again.
    private var lastAuthenticated: Date?

    // Preferences
    var offersToSave: Bool = UserDefaults.standard.object(forKey: "passwords.offerToSave") as? Bool ?? true {
        didSet { UserDefaults.standard.set(offersToSave, forKey: "passwords.offerToSave") }
    }
    var autofills: Bool = UserDefaults.standard.object(forKey: "passwords.autofill") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autofills, forKey: "passwords.autofill") }
    }
    var requiresAuthentication: Bool = UserDefaults.standard.object(forKey: "passwords.requireAuth") as? Bool ?? true {
        didSet { UserDefaults.standard.set(requiresAuthentication, forKey: "passwords.requireAuth") }
    }

    private static let keyAccount = "passwords.vault-key"
    private static let graceInterval: TimeInterval = 5 * 60

    private static var fileURL: URL {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("Passwords", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("vault.sealed")
    }

    // MARK: Reading

    var logins: [SavedLogin] {
        loadIfNeeded()
        return contents.logins
    }

    var neverSaveHosts: [String] {
        loadIfNeeded()
        return contents.neverSave
    }

    /// Logins for a page: the same host first, then the rest of the same site
    /// (accounts.google.com's login also offered on google.com), most used first.
    func logins(for url: URL?) -> [SavedLogin] {
        guard let host = url?.host()?.lowercased() else { return [] }
        let site = Self.site(of: host)
        let all = logins.filter { Self.site(of: $0.host.lowercased()) == site }
        return all.sorted { a, b in
            let aExact = Self.sameHost(a.host, host), bExact = Self.sameHost(b.host, host)
            if aExact != bExact { return aExact }
            return (a.lastUsed ?? a.modified) > (b.lastUsed ?? b.modified)
        }
    }

    func isNeverSave(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return true }
        return neverSaveHosts.contains { Self.sameHost($0, host) }
    }

    // MARK: Writing

    /// Adds a login, or replaces the password of the one with the same site and name.
    func save(origin: String, username: String, password: String, source: String? = nil) {
        loadIfNeeded()
        guard loadError == nil else { return }
        if let index = contents.logins.firstIndex(where: { Self.sameHost($0.host, URL(string: origin)?.host() ?? "") && $0.username == username }) {
            contents.logins[index].password = password
            contents.logins[index].modified = .now
        } else {
            contents.logins.append(SavedLogin(origin: origin, username: username, password: password, source: source))
        }
        persist()
    }

    func update(_ login: SavedLogin) {
        loadIfNeeded()
        guard let index = contents.logins.firstIndex(where: { $0.id == login.id }) else { return }
        var login = login
        login.modified = .now
        contents.logins[index] = login
        persist()
    }

    func delete(_ login: SavedLogin) {
        loadIfNeeded()
        contents.logins.removeAll { $0.id == login.id }
        persist()
    }

    func markUsed(_ login: SavedLogin) {
        guard let index = contents.logins.firstIndex(where: { $0.id == login.id }) else { return }
        contents.logins[index].lastUsed = .now
        contents.logins[index].timesUsed += 1
        persist()
    }

    func neverSave(_ host: String) {
        loadIfNeeded()
        let host = host.lowercased()
        guard !contents.neverSave.contains(host) else { return }
        contents.neverSave.append(host)
        persist()
    }

    func allowSaving(_ host: String) {
        contents.neverSave.removeAll { $0 == host }
        persist()
    }

    /// Adds many at once (an import), skipping exact duplicates. Returns how many were new.
    @discardableResult
    func add(_ imported: [SavedLogin]) -> Int {
        loadIfNeeded()
        guard loadError == nil else { return 0 }
        var added = 0
        for login in imported where !login.password.isEmpty {
            let duplicate = contents.logins.contains {
                Self.sameHost($0.host, login.host) && $0.username == login.username && $0.password == login.password
            }
            if !duplicate {
                contents.logins.append(login)
                added += 1
            }
        }
        if added > 0 { persist() }
        return added
    }

    // MARK: Touch ID

    var isUnlocked: Bool {
        guard requiresAuthentication else { return true }
        guard let lastAuthenticated else { return false }
        return Date.now.timeIntervalSince(lastAuthenticated) < Self.graceInterval
    }

    /// Asks for Touch ID (or the Mac's password) unless it succeeded a moment ago.
    func authenticate(reason: String) async -> Bool {
        if isUnlocked { return true }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No password set on the Mac at all: nothing to check against.
            return true
        }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        if ok { lastAuthenticated = .now }
        return ok
    }

    func lock() { lastAuthenticated = nil }

    // MARK: Health

    /// Passwords used on more than one site.
    var reusedIDs: Set<UUID> {
        var bySecret: [String: [SavedLogin]] = [:]
        for login in logins { bySecret[login.password, default: []].append(login) }
        return Set(bySecret.values.filter { Set($0.map { Self.site(of: $0.host) }).count > 1 }.flatMap { $0.map(\.id) })
    }

    nonisolated static func isWeak(_ password: String) -> Bool {
        let classes = [
            password.contains(where: \.isLowercase),
            password.contains(where: \.isUppercase),
            password.contains(where: \.isNumber),
            password.contains { !$0.isLetter && !$0.isNumber },
        ].filter(\.self).count
        if password.count < 8 { return true }
        if password.count >= 16 { return false }
        return classes < 3
    }

    // MARK: Hosts

    nonisolated static func sameHost(_ a: String, _ b: String) -> Bool {
        strip(a.lowercased()) == strip(b.lowercased())
    }

    nonisolated private static func strip(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The registrable part of a host, close enough for matching logins: the last
    /// two labels, or three under common two-part suffixes (example.co.uk).
    nonisolated static func site(of host: String) -> String {
        let labels = host.lowercased().split(separator: ".")
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        let twoPart: Set<String> = ["co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.jp", "ne.jp",
                                    "com.br", "com.cn", "co.in", "co.nz", "co.za", "com.mx", "com.tr", "co.kr", "co.il",
                                    "ac.ir", "co.ir", "com.ar", "com.sg", "com.hk", "com.tw", "github.io"]
        return (twoPart.contains(lastTwo) ? labels.suffix(3) : labels.suffix(2)).joined(separator: ".")
    }

    nonisolated static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host() else { return nil }
        if let port = url.port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    // MARK: Storage

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        let url = Self.fileURL
        guard let sealed = try? Data(contentsOf: url) else { return }
        guard let key = Self.existingKey() else {
            // The key went missing (Keychain reset): set the file aside, start empty.
            notice = "Your earlier passwords couldn't be opened because their key is missing from the Keychain. The file was kept in Wake's container."
            try? FileManager.default.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date.now.timeIntervalSince1970))"))
            return
        }
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            let plain = try AES.GCM.open(box, using: key)
            contents = try JSONDecoder().decode(Contents.self, from: plain)
        } catch {
            loadError = "Saved passwords couldn't be opened."
        }
    }

    private func persist() {
        guard loadError == nil, let key = Self.existingKey() ?? Self.makeKey() else { return }
        guard let plain = try? JSONEncoder().encode(contents),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return }
        let url = Self.fileURL
        Task.detached(priority: .utility) {
            try? sealed.write(to: url, options: .atomic)
        }
    }

    private static func existingKey() -> SymmetricKey? {
        guard let encoded = KeychainStore.string(for: keyAccount), let data = Data(base64Encoded: encoded), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    private static func makeKey() -> SymmetricKey? {
        let key = SymmetricKey(size: .bits256)
        let encoded = key.withUnsafeBytes { Data($0).base64EncodedString() }
        KeychainStore.set(encoded, for: keyAccount)
        return existingKey()
    }
}

// MARK: - Generator

enum PasswordGenerator {
    /// Three groups of six, like Safari's: "kTq9vB-mzR4wc-Xp7hNa". 18 letters and
    /// digits from an alphabet without look-alikes (0/O, 1/l/I), always with an upper
    /// case letter and a digit, from the system's secure random source.
    static func strong() -> String {
        let lower = Array("abcdefghijkmnopqrstuvwxyz"), upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ"), digits = Array("23456789")
        let all = lower + upper + digits
        var rng = SystemRandomNumberGenerator()
        while true {
            let characters = (0..<18).map { _ in all.randomElement(using: &rng)! }
            let text = String(characters)
            guard text.contains(where: \.isUppercase), text.contains(where: \.isNumber), text.contains(where: \.isLowercase) else { continue }
            return [0, 6, 12].map { String(characters[$0..<$0 + 6]) }.joined(separator: "-")
        }
    }
}
