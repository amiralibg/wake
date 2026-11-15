#if DEBUG
import AppKit

/// Debug builds only: `-WakeDebugShow <what>` opens one screen by itself after launch,
/// so it can be checked or screenshotted without driving the keyboard or mouse.
///
/// - `extensions`: Settings ▸ Extensions
/// - `popup`: the first enabled extension's toolbar popup
/// - `open:<url>`: a new column
/// - `store:<chrome|edge|firefox>:<id>`: install from a store
/// - `import:<browser>`: import every extension a browser has
/// - `updates`: check for updates now
/// - `install:<path>`: the install sheet for a package or folder
@MainActor
enum DebugLaunch {
    static func run() {
        guard let what = UserDefaults.standard.string(forKey: "WakeDebugShow"), let browser = BrowserModel.active else { return }
        switch what {
        case "extensions":
            browser.showSettings(.extensions)
        case "popup":
            if #available(macOS 15.4, *), let item = ExtensionLibrary.shared.enabled.first {
                ExtensionLibrary.shared.performAction(item, in: browser)
            }
        case let value where value.hasPrefix("store:"):
            // store:<chrome|edge|firefox>:<id>
            let parts = value.split(separator: ":", maxSplits: 2).map(String.init)
            if #available(macOS 15.4, *), parts.count == 3, let store = ExtensionStore(rawValue: parts[1]) {
                ExtensionLibrary.shared.beginInstall(.store(store, id: parts[2]))
            }
        case let value where value.hasPrefix("import:"):
            // import:<browser name>: everything that browser has
            let name = String(value.dropFirst("import:".count))
            if #available(macOS 15.4, *) {
                Task {
                    let found = await Task.detached { ExtensionImporter.scan() }.value
                    let count = await ExtensionLibrary.shared.importExtensions(found.filter { $0.browser == name })
                    NSLog("Wake debug: imported \(count) from \(name)")
                    browser.showSettings(.extensions)
                }
            }
        case "updates":
            if #available(macOS 15.4, *) {
                Task {
                    await ExtensionLibrary.shared.checkForUpdates()
                    NSLog("Wake debug: \(ExtensionLibrary.shared.lastUpdateSummary ?? "")")
                    browser.showSettings(.extensions)
                }
            }
        case let value where value.hasPrefix("open:"):
            if let url = URL(string: String(value.dropFirst("open:".count))) {
                browser.hidePalette()
                browser.trail.open(url)
            }
        case let value where value.hasPrefix("install:"):
            if #available(macOS 15.4, *) {
                ExtensionLibrary.shared.beginInstall(.file(URL(fileURLWithPath: String(value.dropFirst("install:".count)))))
            }
        default:
            break
        }
    }
}
#endif
