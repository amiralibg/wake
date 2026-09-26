import AppKit
import Foundation

/// A browser profile on this Mac that Wake can import from.
///
/// Wake is sandboxed, so it can only read these folders because the entitlements
/// list them as read-only exceptions (`temporary-exception.files.home-relative-path`).
/// A browser keeping its data somewhere else won't be found.
struct BrowserProfile: Identifiable, Hashable, Sendable {
    enum Engine: Hashable, Sendable {
        /// Keychain services that may hold the cookie key ("Chrome Safe Storage"…).
        case chromium(keychainServices: [String])
        case firefox
        case safari
    }

    let browser: String
    let profileName: String?
    let directory: URL
    let engine: Engine
    let bundleID: String

    var id: String { directory.path }

    var title: String { profileName.map { "\(browser) · \($0)" } ?? browser }

    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// Chromium and Firefox keep site data we can read; Safari's lives in its own
    /// container, which macOS keeps private.
    var supportsSiteData: Bool { engine != .safari }
}

/// Finds installed browsers' profiles.
enum BrowserCatalog {
    /// The user's real home folder; inside the sandbox, `homeDirectoryForCurrentUser`
    /// is the app's container.
    static let home: URL = {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    private static var applicationSupport: URL { home.appendingPathComponent("Library/Application Support", isDirectory: true) }

    private struct Chromium {
        let name: String
        let bundleID: String
        let root: String
        let keychain: [String]
    }

    private static let chromium: [Chromium] = [
        Chromium(name: "Chrome", bundleID: "com.google.Chrome", root: "Google/Chrome", keychain: ["Chrome Safe Storage"]),
        Chromium(name: "Chrome Beta", bundleID: "com.google.Chrome.beta", root: "Google/Chrome Beta", keychain: ["Chrome Safe Storage"]),
        Chromium(name: "Arc", bundleID: "company.thebrowser.Browser", root: "Arc/User Data", keychain: ["Arc Safe Storage"]),
        Chromium(name: "Dia", bundleID: "company.thebrowser.dia", root: "Dia/User Data", keychain: ["Dia Safe Storage"]),
        Chromium(name: "Brave", bundleID: "com.brave.Browser", root: "BraveSoftware/Brave-Browser", keychain: ["Brave Safe Storage"]),
        Chromium(name: "Edge", bundleID: "com.microsoft.edgemac", root: "Microsoft Edge", keychain: ["Microsoft Edge Safe Storage"]),
        Chromium(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", root: "Vivaldi", keychain: ["Vivaldi Safe Storage"]),
        Chromium(name: "Opera", bundleID: "com.operasoftware.Opera", root: "com.operasoftware.Opera", keychain: ["Opera Safe Storage"]),
        Chromium(name: "Helium", bundleID: "net.imput.helium", root: "net.imput.helium", keychain: ["Helium Storage Key", "Helium Safe Storage"]),
        Chromium(name: "Chromium", bundleID: "org.chromium.Chromium", root: "Chromium", keychain: ["Chromium Safe Storage"]),
    ]

    private static let firefox: [(name: String, bundleID: String, root: String)] = [
        ("Firefox", "org.mozilla.firefox", "Firefox"),
        ("Zen", "app.zen-browser.zen", "zen"),
        ("Waterfox", "net.waterfox.waterfox", "Waterfox"),
    ]

    static func profiles() -> [BrowserProfile] {
        var found: [BrowserProfile] = []
        // Always listed: without Full Disk Access macOS hides the folder entirely, and
        // the sheet explains how to grant it.
        found.append(BrowserProfile(browser: "Safari", profileName: nil, directory: safariFolder, engine: .safari, bundleID: "com.apple.Safari"))
        for browser in chromium {
            let root = applicationSupport.appendingPathComponent(browser.root, isDirectory: true)
            found += chromiumProfiles(root: root).map {
                BrowserProfile(browser: browser.name, profileName: $0.name, directory: $0.directory,
                               engine: .chromium(keychainServices: browser.keychain), bundleID: browser.bundleID)
            }
        }
        for browser in firefox {
            let root = applicationSupport.appendingPathComponent(browser.root, isDirectory: true)
            found += firefoxProfiles(root: root).map {
                BrowserProfile(browser: browser.name, profileName: $0.name, directory: $0.directory, engine: .firefox, bundleID: browser.bundleID)
            }
        }
        return found
    }

    static var safariFolder: URL { home.appendingPathComponent("Library/Safari", isDirectory: true) }

    /// Safari's data is protected by macOS privacy (TCC) even for a folder Wake may
    /// read: without Full Disk Access, opening it fails.
    static var safariIsReadable: Bool {
        (try? FileHandle(forReadingFrom: safariFolder.appendingPathComponent("History.db")))?.closeFile() != nil
    }

    /// "Local State" names each profile; with one profile its name is left out.
    /// Opera keeps a single profile in the root itself.
    private static func chromiumProfiles(root: URL) -> [(name: String?, directory: URL)] {
        let manager = FileManager.default
        if manager.fileExists(atPath: root.appendingPathComponent("History").path) { return [(nil, root)] }
        var names: [String: String] = [:]
        if let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: Any] {
            for (folder, info) in cache { names[folder] = (info as? [String: Any])?["name"] as? String }
        }
        let folders = ((try? manager.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .filter { manager.fileExists(atPath: root.appendingPathComponent($0).appendingPathComponent("History").path) }
            .sorted { $0 == "Default" ? true : ($1 == "Default" ? false : $0.localizedStandardCompare($1) == .orderedAscending) }
        return folders.map { folder in
            (folders.count > 1 ? (names[folder] ?? folder) : nil, root.appendingPathComponent(folder, isDirectory: true))
        }
    }

    /// Profiles listed in profiles.ini that have history.
    private static func firefoxProfiles(root: URL) -> [(name: String?, directory: URL)] {
        guard let text = try? String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8) else { return [] }
        var profiles: [(name: String?, directory: URL)] = []
        var name: String?
        var path: String?
        var relative = true
        func flush() {
            defer { name = nil; path = nil; relative = true }
            guard let path else { return }
            let directory = relative ? root.appendingPathComponent(path, isDirectory: true) : URL(fileURLWithPath: path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("places.sqlite").path) else { return }
            profiles.append((name, directory))
        }
        for line in text.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { flush(); continue }
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "Name": name = parts[1]
            case "Path": path = parts[1]
            case "IsRelative": relative = parts[1] == "1"
            default: break
            }
        }
        flush()
        if profiles.count == 1 { profiles[0].name = nil }
        return profiles
    }
}
