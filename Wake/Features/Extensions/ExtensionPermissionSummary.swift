import AppKit
import WebKit

/// What the install sheet and the extension list say about an extension's access,
/// in plain words, most significant first.
@available(macOS 15.4, *)
@MainActor
struct ExtensionPermissionSummary {
    struct Line: Identifiable, Hashable {
        let symbol: String
        let text: String
        /// Broad access gets an emphasised row.
        var isBroad = false
        var id: String { text }
    }

    let lines: [Line]

    init(permissions: Set<WKWebExtension.Permission>, patterns: Set<WKWebExtension.MatchPattern>) {
        var lines: [Line] = []
        let names = Set(permissions.map(\.rawValue))
        let hosts = patterns.filter { !$0.matchesAllURLs && !$0.matchesAllHosts }.compactMap { $0.host }.map { $0.hasPrefix("*.") ? String($0.dropFirst(2)) : $0 }
        if patterns.contains(where: { $0.matchesAllURLs || $0.matchesAllHosts }) {
            lines.append(Line(symbol: "globe", text: "Read and change everything on every website", isBroad: true))
        } else if !hosts.isEmpty {
            let unique = Array(Set(hosts)).sorted()
            let shown = unique.prefix(3).joined(separator: ", ")
            let more = unique.count > 3 ? " and \(unique.count - 3) more" : ""
            lines.append(Line(symbol: "globe", text: "Read and change your data on \(shown)\(more)"))
        }
        let known: [(String, String, String)] = [
            ("tabs", "rectangle.stack", "See the titles and addresses of your columns"),
            ("history", "clock.arrow.circlepath", "Read your browsing history"),
            ("webNavigation", "location", "See where you go as you browse"),
            ("cookies", "lock.rectangle.stack", "Read and change cookies on sites it can access"),
            ("declarativeNetRequest", "shield.lefthalf.filled", "Block or change content on pages"),
            ("declarativeNetRequestWithHostAccess", "shield.lefthalf.filled", "Block or change content on pages"),
            ("webRequest", "network", "Watch the requests pages make"),
            ("scripting", "chevron.left.forwardslash.chevron.right", "Run scripts on pages it can access"),
            ("clipboardWrite", "doc.on.clipboard", "Write to your clipboard"),
            ("clipboardRead", "doc.on.clipboard", "Read your clipboard"),
            ("notifications", "bell.badge", "Show notifications"),
            ("contextMenus", "contextualmenu.and.cursorarrow", "Add items to menus"),
            ("menus", "contextualmenu.and.cursorarrow", "Add items to menus"),
            ("unlimitedStorage", "internaldrive", "Store any amount of data"),
        ]
        var seen = Set<String>()
        for (name, symbol, text) in known where names.contains(name) && seen.insert(text).inserted {
            lines.append(Line(symbol: symbol, text: text))
        }
        self.lines = lines
    }

    init(_ webExtension: WKWebExtension) {
        let optional = webExtension.optionalPermissionMatchPatterns
        self.init(
            permissions: webExtension.requestedPermissions,
            patterns: webExtension.requestedPermissionMatchPatterns.union(webExtension.allRequestedMatchPatterns.subtracting(optional))
        )
    }

    /// Manifest keys and permissions Wake (or WebKit) doesn't provide, so the person
    /// knows before installing which parts won't work.
    static func unsupported(in webExtension: WKWebExtension) -> [String] {
        let manifest = webExtension.manifest
        let permissions = Set(((manifest["permissions"] as? [Any]) ?? []).compactMap { $0 as? String })
            .union(((manifest["optional_permissions"] as? [Any]) ?? []).compactMap { $0 as? String })
        var missing: [String] = []
        if manifest["sidebar_action"] != nil || manifest["side_panel"] != nil || permissions.contains("sidePanel") { missing.append("Side panel") }
        if permissions.contains("nativeMessaging") { missing.append("Talking to an app on your Mac (native messaging)") }
        if permissions.contains("webRequestBlocking") { missing.append("Blocking requests with webRequest") }
        let apis: [(String, String)] = [
            ("downloads", "Downloads"), ("bookmarks", "Bookmarks"), ("history", "History"), ("proxy", "Proxy settings"),
            ("identity", "Signing in with your browser account"), ("management", "Managing other extensions"),
            ("topSites", "Top sites"), ("browsingData", "Clearing browsing data"), ("debugger", "Debugger"),
            ("contextualIdentities", "Containers"), ("sessions", "Recently closed tabs"), ("tabGroups", "Tab groups"),
        ]
        for (name, label) in apis where permissions.contains(name) { missing.append(label) }
        return missing
    }
}

/// A package read and waiting for the person's yes or no, shown by the window.
struct ExtensionInstallRequest: Identifiable {
    let id: String
    let name: String
    let version: String
    let summary: String
    let icon: NSImage?
    let origin: String
    let access: [AccessLine]
    let unsupported: [String]
    let manifestVersion: Int

    struct AccessLine: Identifiable, Hashable {
        let symbol: String
        let text: String
        let isBroad: Bool
        var id: String { text }
    }

    @available(macOS 15.4, *)
    @MainActor
    init(id: String, webExtension: WKWebExtension, source: ExtensionRecord.Source) {
        self.id = id
        name = webExtension.displayName ?? "Extension"
        version = webExtension.displayVersion ?? webExtension.version ?? ""
        summary = webExtension.displayDescription ?? ""
        icon = webExtension.icon(for: CGSize(width: 128, height: 128))
        access = ExtensionPermissionSummary(webExtension).lines.map { AccessLine(symbol: $0.symbol, text: $0.text, isBroad: $0.isBroad) }
        unsupported = ExtensionPermissionSummary.unsupported(in: webExtension)
        manifestVersion = Int(webExtension.manifestVersion)
        origin = switch source {
        case .file: "From a file"
        case .store(let store, _): "From \(store.title)"
        case .imported(let browser, _, _): "From \(browser)"
        }
    }
}

/// What the window shows for an install: the question, or why it can't go ahead.
enum ExtensionInstallPrompt: Identifiable {
    case request(ExtensionInstallRequest)
    case alreadyInstalled(String)
    case failed(String)

    var id: String {
        switch self {
        case .request(let request): request.id
        case .alreadyInstalled(let name): "installed-\(name)"
        case .failed(let reason): "failed-\(reason)"
        }
    }
}
