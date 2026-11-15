#if DEBUG
import AppKit
import WebKit

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
/// - `menu`: the toolbar's extensions menu
/// - `access:<onClick|thisSite|allSites>`: the first extension's site access for the
///   focused page
/// - `wait:<seconds>`: pause before the next step
/// - `reload`: reload the focused page
/// - `background`: start each extension's background and log errors
/// - `probe`: log whether the test fixture's content script ran in the focused page
@MainActor
enum DebugLaunch {
    /// Logs a line, also appended to `<container>/tmp/wake-debug.log`, which scripts read
    /// (the unified log hides NSLog lines from `log show` on some systems).
    static func note(_ line: String) {
        NSLog("Wake debug: %@", line)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wake-debug.log")
        let data = Data("\(Date().formatted(.iso8601)) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Several steps run in order when separated by `;;` (`open:<url>;;wait:4;;menu`).
    static func run() {
        guard let value = UserDefaults.standard.string(forKey: "WakeDebugShow") else { return }
        Task {
            // The window can come up after launch finishes; wait for it (up to 15 s).
            var browser = BrowserModel.active
            for _ in 0..<30 where browser == nil {
                try? await Task.sleep(for: .milliseconds(500))
                browser = BrowserModel.active
            }
            guard let browser else { return note("no window for \(value)") }
            for what in value.components(separatedBy: ";;") { await handle(what, browser) }
        }
    }

    private static func handle(_ what: String, _ browser: BrowserModel) async {
        switch what {
        case "extensions":
            browser.showSettings(.extensions)
        case "menu":
            browser.showsExtensionsMenu = true
        case let value where value.hasPrefix("wait:"):
            try? await Task.sleep(for: .seconds(Double(value.dropFirst(5)) ?? 1))
        case "background":
            // Starts every enabled extension's background content and logs what happens.
            if #available(macOS 15.4, *) {
                for item in ExtensionLibrary.shared.enabled {
                    guard let context = item.context else {
                        note("background \(item.name): not loaded \(item.problems)")
                        continue
                    }
                    let error: String? = await withCheckedContinuation { done in
                        context.loadBackgroundContent { done.resume(returning: $0?.localizedDescription) }
                    }
                    note("background \(item.name): \(error ?? "ok") problems=\(item.problems) mv=\(item.webExtension.manifestVersion)")
                }
            }
        case "swdata":
            // Service worker registrations and other data the page store keeps for extensions.
            let records = await WKWebsiteDataStore.default().dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            for record in records {
                note("data \(record.displayName) \(record.dataTypes.sorted())")
            }
            note("data records: \(records.count)")
        case let value where value.hasPrefix("swclear:"):
            let host = String(value.dropFirst(8))
            let store = WKWebsiteDataStore.default()
            let records = await store.dataRecords(ofTypes: [WKWebsiteDataTypeServiceWorkerRegistrations])
            let matching = records.filter { $0.displayName.lowercased().contains(host.lowercased()) }
            await store.removeData(ofTypes: [WKWebsiteDataTypeServiceWorkerRegistrations], for: matching)
            note("swclear \(host): removed \(matching.count)")
        case let value where value.hasPrefix("toggle:"):
            // Turns the named extension off and on again.
            let name = String(value.dropFirst(7))
            if #available(macOS 15.4, *), let item = ExtensionLibrary.shared.items.first(where: { $0.name.hasPrefix(name) }) {
                ExtensionLibrary.shared.setEnabled(item, false)
                try? await Task.sleep(for: .seconds(1))
                ExtensionLibrary.shared.setEnabled(item, true)
                note("toggled \(item.name)")
            }
        case let value where value.hasPrefix("remove:"):
            // Removes every extension whose name starts with this.
            let name = String(value.dropFirst(7))
            if #available(macOS 15.4, *) {
                for item in ExtensionLibrary.shared.items where item.name.hasPrefix(name) {
                    ExtensionLibrary.shared.remove(item)
                    note("removed \(item.name)")
                }
            }
        case let value where value.hasPrefix("grants:"):
            // What WebKit has granted the named extension, and its status for the focused page.
            let name = String(value.dropFirst(7))
            if #available(macOS 15.4, *), let item = ExtensionLibrary.shared.items.first(where: { $0.name.hasPrefix(name) }), let context = item.context {
                let url = browser.webPage?.url
                note("grants \(item.name) mode=\(item.record.siteAccess) allowed=\(item.record.allowedSites) optional=\(item.record.grantedMatchPatterns): granted=\(context.grantedPermissionMatchPatterns.map { "\($0.key.string)" }.sorted()) denied=\(context.deniedPermissionMatchPatterns.map { "\($0.key.string)" }.sorted()) status(\(url?.absoluteString ?? "-"))=\(url.map { context.permissionStatus(for: $0).rawValue } ?? 99) allURLs=\(context.hasAccessToAllURLs) allHosts=\(context.hasAccessToAllHosts) requested=\(item.webExtension.allRequestedMatchPatterns.map(\.string).sorted())")
            }
        case "closepopups":
            if #available(macOS 15.4, *) {
                for item in ExtensionLibrary.shared.enabled {
                    ExtensionLibrary.shared.action(of: item, in: browser)?.closePopup()
                }
            }
        case "reload":
            browser.webPage?.reload()
        case "probe":
            let state = try? await browser.webPage?.webView.evaluateJavaScript("document.documentElement.dataset.wakeTestExtension || 'absent'")
            note("probe \(browser.webPage?.url?.absoluteString ?? "-") content script \(state.map { "\($0)" } ?? "?")")
        case let value where value.hasPrefix("access:"):
            let choice = String(value.dropFirst("access:".count))
            if #available(macOS 15.4, *), let item = ExtensionLibrary.shared.enabled.first,
               let pick = ExtensionLibrary.SiteChoice.allCases.first(where: { "\($0)" == choice }) {
                let page = browser.webPage
                ExtensionLibrary.shared.setSiteChoice(pick, for: item, on: page?.url?.host() ?? "", page: page)
            }
        case let value where value == "popup" || value.hasPrefix("popup:"):
            // popup or popup:<name prefix>
            let name = value.hasPrefix("popup:") ? String(value.dropFirst(6)) : ""
            if #available(macOS 15.4, *),
               let item = ExtensionLibrary.shared.enabled.first(where: { name.isEmpty || $0.name.hasPrefix(name) }) {
                ExtensionLibrary.shared.performAction(item, in: browser)
            }
        case let value where value.hasPrefix("popupjs:"):
            // popupjs:<name>|<async JS body returning a value>, run in the open popup.
            let rest = String(value.dropFirst(8))
            let parts = rest.split(separator: "|", maxSplits: 1).map(String.init)
            if #available(macOS 15.4, *), parts.count == 2,
               let item = ExtensionLibrary.shared.enabled.first(where: { $0.name.hasPrefix(parts[0]) }),
               let webView = ExtensionLibrary.shared.action(of: item, in: browser)?.popupWebView {
                do {
                    let result = try await webView.callAsyncJavaScript(parts[1], contentWorld: .page)
                    note("popupjs \(item.name): \(result.map { "\($0)" } ?? "nil")")
                } catch {
                    note("popupjs \(item.name) threw: \(error)")
                }
            }
        case let value where value.hasPrefix("popupprobe:"):
            // What the named extension's open popup shows, and its size.
            let name = String(value.dropFirst(11))
            if #available(macOS 15.4, *), let item = ExtensionLibrary.shared.enabled.first(where: { $0.name.hasPrefix(name) }),
               let action = ExtensionLibrary.shared.action(of: item, in: browser) {
                let webView = action.popupWebView
                let text = try? await webView?.evaluateJavaScript("location.href + ' | ' + document.readyState + ' | ' + document.documentElement.outerHTML.length + ' | ' + (document.body ? document.body.innerText.slice(0, 200) : 'no body')")
                note("popupprobe \(item.name): view=\(webView.map { "\($0.frame.size)" } ?? "nil") loading=\(webView?.isLoading ?? false) \(text.map { "\($0)" } ?? "?")")
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
                    note("imported \(count) from \(name)")
                    browser.showSettings(.extensions)
                }
            }
        case "updates":
            if #available(macOS 15.4, *) {
                Task {
                    await ExtensionLibrary.shared.checkForUpdates()
                    note(ExtensionLibrary.shared.lastUpdateSummary ?? "")
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
