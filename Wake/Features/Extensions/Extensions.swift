import AppKit
import WebKit

/// The rest of Wake talks to browser extensions through this, so callers never need
/// an availability check.
///
/// Limitation: WebKit's extension runtime (`WKWebExtension*`) is public only from
/// macOS 15.4. On macOS 14.0 to 15.3, which Wake still supports, every call here does
/// nothing and Settings ▸ Extensions says why.
@MainActor
enum Extensions {
    static var isSupported: Bool {
        if #available(macOS 15.4, *) { true } else { false }
    }

    /// Loads the installed extensions. Called once at launch.
    static func start() {
        guard #available(macOS 15.4, *) else { return }
        ExtensionLibrary.shared.start()
    }

    /// Every page web view joins the extension controller, so content scripts and
    /// `tabs` APIs reach it.
    static func attach(to configuration: WKWebViewConfiguration) {
        guard #available(macOS 15.4, *) else { return }
        configuration.webExtensionController = ExtensionLibrary.shared.controller
    }

    /// An extension's own pages (options, tabs it opens) must load in a web view made
    /// from that extension's configuration, not Wake's.
    static func configuration(for url: URL) -> WKWebViewConfiguration? {
        guard #available(macOS 15.4, *), url.scheme == ExtensionLibrary.scheme else { return nil }
        return ExtensionLibrary.shared.controller.extensionContext(for: url)?.webViewConfiguration
    }

    /// The window's columns changed (opened, closed, moved, focused, thread switched).
    static func windowChanged(_ browser: BrowserModel) {
        guard #available(macOS 15.4, *) else { return }
        ExtensionLibrary.shared.tabs.sync(browser)
    }

    static func windowClosed(_ browser: BrowserModel) {
        guard #available(macOS 15.4, *) else { return }
        ExtensionLibrary.shared.tabs.close(browser)
    }

    enum PageChange { case title, url, loading, audio, zoom }

    static func pageChanged(_ page: BrowserPage, _ change: PageChange) {
        guard #available(macOS 15.4, *) else { return }
        ExtensionLibrary.shared.tabs.pageChanged(page, change)
    }

    /// A download the page started is an extension package (an AMO "Download file"
    /// link, a `.crx` from a developer's site): offer to install it instead.
    static func isPackageResponse(_ response: URLResponse) -> Bool {
        guard isSupported else { return false }
        let type = response.mimeType?.lowercased() ?? ""
        if ["application/x-xpinstall", "application/x-chrome-extension"].contains(type) { return true }
        let ext = response.url?.pathExtension.lowercased() ?? ""
        return (ext == "xpi" || ext == "crx") && !type.hasPrefix("text/")
    }

    /// What store pages show: which items are installed or being added.
    static var storeState: [String: Any] {
        guard #available(macOS 15.4, *) else { return [:] }
        return ExtensionLibrary.shared.storeState
    }

    /// A store page's "Add to Wake" or "Remove from Wake".
    static func storeButtonPressed(_ message: [String: Any]) {
        guard #available(macOS 15.4, *),
              let store = (message["store"] as? String).flatMap(ExtensionStore.init(rawValue:)),
              let id = message["id"] as? String, !id.isEmpty else { return }
        if message["type"] as? String == "storeRemove" {
            ExtensionLibrary.shared.removeFromStorePage(store: store, id: id)
        } else {
            ExtensionLibrary.shared.beginInstall(.store(store, id: id))
        }
    }

    /// Items extensions add to the page's right-click menu.
    static func menuItems(for page: BrowserPage) -> [NSMenuItem] {
        guard #available(macOS 15.4, *) else { return [] }
        return ExtensionLibrary.shared.menuItems(for: page)
    }

    static func installFromWeb(_ url: URL) {
        guard #available(macOS 15.4, *) else { return }
        ExtensionLibrary.shared.beginInstall(.download(url))
    }

    /// File ▸ Add Extension…: a folder, `.zip`, `.crx` or `.xpi`.
    static func chooseAndInstall() {
        guard #available(macOS 15.4, *) else { return }
        let panel = NSOpenPanel()
        panel.title = "Add Extension"
        panel.message = "Choose an extension folder, or a .crx, .xpi or .zip file."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ExtensionLibrary.shared.beginInstall(.file(url))
    }
}
