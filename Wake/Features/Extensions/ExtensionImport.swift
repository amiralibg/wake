import AppKit
import Foundation

/// An extension installed in another browser on this Mac, which Wake can copy.
struct ImportableExtension: Identifiable, Hashable, Sendable {
    let browser: String
    /// The browser app, for its icon.
    let bundleID: String
    let profile: String?
    let name: String
    let version: String
    /// The extension's folder (Chromium) or `.xpi` (Firefox family).
    let package: URL
    /// The store it updates from in that browser, if any.
    let store: ExtensionStore?
    /// The store's id for it: a 32-letter id, or a Firefox add-on GUID.
    let storeID: String?
    let isEnabled: Bool
    let iconFile: URL?

    var id: String { package.path }

    var icon: NSImage? { iconFile.flatMap(NSImage.init(contentsOf:)) }
}

/// Finds extensions in the browsers `BrowserCatalog` knows (Chrome, Arc, Dia, Brave,
/// Edge, Vivaldi, Opera, Helium, Chromium; Firefox, Zen, Waterfox), through the same
/// read-only sandbox exceptions the history import uses.
///
/// Chromium keeps each extension unpacked under `<profile>/Extensions/<id>/<version>`
/// and describes it in `Secure Preferences` / `Preferences`; Firefox keeps `.xpi`
/// files in `<profile>/extensions` and describes them in `extensions.json`. Wake
/// copies the package, so nothing is downloaded.
///
/// Limitation: extension settings and data don't come along: each browser keeps them
/// in its own storage format. The extensions start fresh in Wake.
enum ExtensionImporter {
    static func scan() -> [ImportableExtension] {
        BrowserCatalog.profiles().flatMap { profile -> [ImportableExtension] in
            switch profile.engine {
            case .chromium: chromium(profile)
            case .firefox: firefox(profile)
            case .safari: []
            }
        }
    }

    // MARK: Chromium

    /// Locations Chromium uses for extensions a person installed: from the store or a
    /// `.crx` (1, INTERNAL) and "Load unpacked" (4, UNPACKED). Built-ins (5, 10) and
    /// ones a policy or another app installed are left out.
    private static let userLocations: Set<Int> = [1, 4]

    private static func chromium(_ profile: BrowserProfile) -> [ImportableExtension] {
        var settings: [String: [String: Any]] = [:]
        for file in ["Preferences", "Secure Preferences"] {
            guard let data = try? Data(contentsOf: profile.directory.appendingPathComponent(file)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let found = (json["extensions"] as? [String: Any])?["settings"] as? [String: Any] else { continue }
            for (id, value) in found {
                guard let value = value as? [String: Any] else { continue }
                settings[id, default: [:]].merge(value) { _, new in new }
            }
        }
        let extensionsFolder = profile.directory.appendingPathComponent("Extensions", isDirectory: true)
        return settings.compactMap { id, entry -> ImportableExtension? in
            guard let location = entry["location"] as? Int, userLocations.contains(location) else { return nil }
            let folder: URL
            if location == 4, let path = entry["path"] as? String {
                folder = URL(fileURLWithPath: path, isDirectory: true)
            } else if let path = entry["path"] as? String {
                folder = extensionsFolder.appendingPathComponent(path, isDirectory: true)
            } else {
                guard let newest = newestVersionFolder(in: extensionsFolder.appendingPathComponent(id)) else { return nil }
                folder = newest
            }
            guard let manifest = readJSON(folder.appendingPathComponent("manifest.json")) else { return nil }
            if manifest["theme"] != nil { return nil } // Themes aren't extensions.
            let name = localized(manifest["name"] as? String, in: folder, manifest: manifest) ?? id
            let updateURL = (manifest["update_url"] as? String ?? "").lowercased()
            let store: ExtensionStore? = location == 4 ? nil
                : updateURL.contains("edge.microsoft.com") ? .edge
                : (entry["from_webstore"] as? Bool == true || updateURL.contains("clients2.google.com")) ? .chrome
                : nil
            // Chrome writes a non-empty `disable_reasons` (or `state` 0 in older
            // versions) for an extension that's turned off.
            let reasons = entry["disable_reasons"]
            let disabled = (reasons as? [Any]).map { !$0.isEmpty } ?? ((reasons as? Int).map { $0 != 0 } ?? (entry["state"] as? Int == 0))
            return ImportableExtension(
                browser: profile.browser,
                bundleID: profile.bundleID,
                profile: profile.profileName,
                name: name,
                version: manifest["version"] as? String ?? "",
                package: folder,
                store: store,
                storeID: store == nil ? nil : id,
                isEnabled: !disabled,
                iconFile: iconFile(manifest, in: folder)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func newestVersionFolder(in folder: URL) -> URL? {
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return versions.filter { !$0.hasPrefix(".") }
            .max { ExtensionStore.isNewer($1.replacingOccurrences(of: "_", with: "."), than: $0.replacingOccurrences(of: "_", with: ".")) }
            .map { folder.appendingPathComponent($0, isDirectory: true) }
    }

    /// `__MSG_appName__` names come from `_locales/<default>/messages.json`.
    private static func localized(_ value: String?, in folder: URL, manifest: [String: Any]) -> String? {
        guard let value, value.hasPrefix("__MSG_"), value.hasSuffix("__") else { return value }
        let key = String(value.dropFirst(6).dropLast(2)).lowercased()
        let locale = manifest["default_locale"] as? String ?? "en"
        let messages = readJSON(folder.appendingPathComponent("_locales/\(locale)/messages.json")) ?? [:]
        let entry = messages.first { $0.key.lowercased() == key }?.value as? [String: Any]
        return entry?["message"] as? String ?? value
    }

    private static func iconFile(_ manifest: [String: Any], in folder: URL) -> URL? {
        guard let icons = manifest["icons"] as? [String: Any] else { return nil }
        let best = icons.compactMap { key, value -> (Int, String)? in
            guard let size = Int(key), let path = value as? String else { return nil }
            return (size, path)
        }
        .min { abs($0.0 - 64) < abs($1.0 - 64) }
        return best.map { folder.appendingPathComponent($0.1) }
    }

    // MARK: Firefox

    private static func firefox(_ profile: BrowserProfile) -> [ImportableExtension] {
        guard let json = readJSON(profile.directory.appendingPathComponent("extensions.json")),
              let addons = json["addons"] as? [[String: Any]] else { return [] }
        return addons.compactMap { addon -> ImportableExtension? in
            guard addon["type"] as? String == "extension",
                  addon["location"] as? String == "app-profile",
                  let guid = addon["id"] as? String,
                  let path = addon["path"] as? String else { return nil }
            let package = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: package.path) else { return nil }
            let locale = addon["defaultLocale"] as? [String: Any]
            // Firefox records where it downloaded the add-on: AMO means AMO keeps it updated.
            let fromAMO = (addon["sourceURI"] as? String)?.contains("addons.mozilla.org") == true
            return ImportableExtension(
                browser: profile.browser,
                bundleID: profile.bundleID,
                profile: profile.profileName,
                name: locale?["name"] as? String ?? guid,
                version: addon["version"] as? String ?? "",
                package: package,
                store: fromAMO ? .firefox : nil,
                storeID: fromAMO ? guid : nil,
                isEnabled: addon["active"] as? Bool ?? !(addon["userDisabled"] as? Bool ?? false),
                iconFile: nil
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
