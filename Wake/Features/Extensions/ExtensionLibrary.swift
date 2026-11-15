import AppKit
import Observation
import WebKit

/// One installed extension, loaded or not.
@available(macOS 15.4, *)
@MainActor
@Observable
final class InstalledExtension: Identifiable {
    var record: ExtensionRecord
    /// Replaced when the extension updates.
    var webExtension: WKWebExtension
    /// Set while the extension is enabled and loaded into the controller.
    var context: WKWebExtensionContext?
    /// Bumped when the extension changes its toolbar action (icon, badge, title).
    var actionVersion = 0
    var loadError: String?

    init(record: ExtensionRecord, webExtension: WKWebExtension) {
        id = record.id
        self.record = record
        self.webExtension = webExtension
    }

    nonisolated let id: String
    var name: String { webExtension.displayName ?? webExtension.displayShortName ?? "Extension" }
    var version: String { webExtension.displayVersion ?? webExtension.version ?? "" }
    var summary: String { webExtension.displayDescription ?? "" }
    var isLoaded: Bool { context?.isLoaded == true }

    func icon(_ side: CGFloat) -> NSImage? {
        webExtension.icon(for: CGSize(width: side, height: side))
    }

    /// Manifest V2's `browser_action` / `page_action` or V3's `action`.
    var hasToolbarAction: Bool {
        let manifest = webExtension.manifest
        return manifest["action"] != nil || manifest["browser_action"] != nil || manifest["page_action"] != nil
    }

    /// WebKit's warnings about the manifest and anything that failed at load.
    var problems: [String] {
        (webExtension.errors + (context?.errors ?? [])).map(\.localizedDescription) + [loadError].compactMap { $0 }
    }
}

/// Wake's extensions: the WebKit controller every page joins, what's installed, the
/// install flow, and WebKit's delegate (tabs, popups, permission prompts).
@available(macOS 15.4, *)
@MainActor
@Observable
final class ExtensionLibrary: NSObject {
    static let shared = ExtensionLibrary()
    static let scheme = "webkit-extension"
    /// Fixed, so extension storage survives relaunches.
    private static let controllerID = UUID(uuidString: "6C1F7E52-2A4B-4F0E-9E57-57A6E0E1A7E1")!

    @ObservationIgnored let controller: WKWebExtensionController
    @ObservationIgnored private(set) lazy var tabs = ExtensionTabs(controller: controller)
    private(set) var items: [InstalledExtension] = []
    /// Install requests being shown, waiting for the person's answer.
    @ObservationIgnored private var staged: [String: (record: ExtensionRecord, webExtension: WKWebExtension)] = [:]
    /// Something is being downloaded or read for an install.
    var isPreparingInstall: Bool { installing != nil }
    @ObservationIgnored private var started = false
    /// The extensions installed at launch have all been loaded (or failed to).
    @ObservationIgnored private(set) var hasLoaded = false
    /// Toolbar buttons register here so a popup can open under its own button.
    @ObservationIgnored private var anchors: [String: [WeakView]] = [:]
    struct WeakView { weak var view: NSView? }

    private override init() {
        let configuration = WKWebExtensionController.Configuration(identifier: Self.controllerID)
        configuration.defaultWebsiteDataStore = .default()
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
    }

    var enabled: [InstalledExtension] { items.filter { $0.record.isEnabled } }

    // MARK: Launch

    func start() {
        guard !started else { return }
        started = true
        var records = Self.readRecords()
        // Earlier builds kept packages as ZIPs, which break after a relaunch.
        var migrated = false
        for index in records.indices {
            if let name = ExtensionPackage.unpackLegacyArchive(of: records[index]) {
                records[index].packageName = name
                migrated = true
            }
        }
        Task {
            for record in records {
                let url = ExtensionPackage.packageURL(for: record)
                do {
                    let webExtension = try await WKWebExtension(resourceBaseURL: url)
                    let item = InstalledExtension(record: record, webExtension: webExtension)
                    items.append(item)
                    if record.isEnabled { load(item) }
                } catch {
                    NSLog("Wake: extension \(record.id) didn't load: \(error.localizedDescription)")
                }
            }
            hasLoaded = true
            if migrated { save() }
            // Report the windows that opened before the extensions finished loading.
            tabs.resyncAll()
            refreshStorePages()
            NotificationCenter.default.post(name: Extensions.didChange, object: nil)
        }
        monitorShortcuts()
        scheduleUpdates()
    }

    private func load(_ item: InstalledExtension) {
        let context = WKWebExtensionContext(for: item.webExtension)
        context.uniqueIdentifier = item.id
        if let base = URL(string: "\(Self.scheme)://\(item.id.lowercased())/") {
            context.baseURL = base
            ExtensionTrackingExemption.exempt(base, in: controller.configuration.defaultWebsiteDataStore ?? .default())
        }
        context.isInspectable = true
        context.inspectionName = item.name
        grantPermissions(of: item, in: context)
        do {
            try controller.load(context)
            item.context = context
            item.loadError = nil
            if hasLoaded { NotificationCenter.default.post(name: Extensions.didChange, object: nil) }
        } catch {
            item.loadError = error.localizedDescription
        }
    }

    /// The install confirmation granted what the manifest asks for; optional
    /// permissions granted later are kept in the record. Host access follows the
    /// person's site-access choice.
    private func grantPermissions(of item: InstalledExtension, in context: WKWebExtensionContext) {
        for permission in item.webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for name in item.record.grantedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: name))
        }
        applySiteAccess(of: item, to: context)
    }

    // MARK: Site access

    /// For one site: does the extension run there by itself, only when clicked, or
    /// everywhere? Chrome's "This can read and change site data".
    enum SiteChoice: CaseIterable {
        case onClick, thisSite, allSites
    }

    /// Host patterns the manifest asks for up front (`host_permissions`, content
    /// scripts), as opposed to optional ones it asks for at run time.
    private static func requiredPatterns(_ webExtension: WKWebExtension) -> Set<WKWebExtension.MatchPattern> {
        webExtension.requestedPermissionMatchPatterns.union(webExtension.allRequestedMatchPatterns.subtracting(webExtension.optionalPermissionMatchPatterns))
    }

    /// The extension asks to read and change websites, so site access applies to it.
    func wantsSiteAccess(_ item: InstalledExtension) -> Bool {
        Self.requiredPatterns(item.webExtension).contains { $0.matchesAllURLs || $0.matchesAllHosts || $0.host?.isEmpty == false }
    }

    func siteChoice(of item: InstalledExtension, on host: String) -> SiteChoice {
        switch item.record.siteAccess {
        case .allSites: .allSites
        case .chosenSites: item.record.allowedSites.contains(host) ? .thisSite : .onClick
        }
    }

    /// Hosts granted by a click on the button (Chrome's "on click"), kept until Wake
    /// quits or the extension's site access changes.
    ///
    /// Limitation: Chrome drops a click grant when that tab leaves the site; Wake keeps
    /// it for the host in every column until relaunch, because WebKit's grants are per
    /// extension, not per tab.
    @ObservationIgnored private var clickGrants: [String: Set<String>] = [:]
    /// The page whose extensions changed access: it needs a reload to apply.
    private(set) var pageNeedingReload: BrowserPage.ID?

    func setSiteChoice(_ choice: SiteChoice, for item: InstalledExtension, on host: String, page: BrowserPage?) {
        guard siteChoice(of: item, on: host) != choice else { return }
        switch choice {
        case .allSites:
            item.record.siteAccess = .allSites
        case .thisSite:
            if item.record.siteAccess == .allSites { item.record.allowedSites = [] }
            item.record.siteAccess = .chosenSites
            item.record.allowedSites = Array(Set(item.record.allowedSites + [host])).sorted()
        case .onClick:
            if item.record.siteAccess == .allSites { item.record.allowedSites = [] }
            item.record.siteAccess = .chosenSites
            item.record.allowedSites.removeAll { $0 == host }
            // An earlier "Allow on this site?" for the same host gives way to this choice.
            if let url = URL(string: "https://\(host)/") {
                item.record.grantedMatchPatterns.removeAll { (try? WKWebExtension.MatchPattern(string: $0))?.matches(url) == true }
            }
        }
        clickGrants[item.id] = nil
        if let context = item.context { applySiteAccess(of: item, to: context) }
        item.actionVersion += 1
        pageNeedingReload = page?.id
        save()
    }

    func reloadAfterAccessChange(_ page: BrowserPage) {
        pageNeedingReload = nil
        page.reload()
    }

    /// The extension would run on this page but isn't allowed to: its button shows a
    /// dot, and clicking it grants the site.
    func wantsAccess(_ item: InstalledExtension, to url: URL?) -> Bool {
        guard let url, let context = item.context, item.record.siteAccess == .chosenSites,
              ["http", "https"].contains(url.scheme ?? "") else { return false }
        switch context.permissionStatus(for: url) {
        case .requestedImplicitly, .requestedExplicitly: return true
        // Denied by Wake when a site was taken away (see `applySiteAccess`), but the
        // manifest still asks for it.
        case .deniedExplicitly, .deniedImplicitly: return Self.requiredPatterns(item.webExtension).contains { $0.matchesAllURLs || $0.matches(url) }
        default: return false
        }
    }

    private func applySiteAccess(of item: InstalledExtension, to context: WKWebExtensionContext) {
        let required = Self.requiredPatterns(item.webExtension)
        let optional = item.record.grantedMatchPatterns.compactMap { try? WKWebExtension.MatchPattern(string: $0) }
        switch item.record.siteAccess {
        case .allSites:
            // Sites denied while access was limited are allowed again.
            for pattern in Array(context.deniedPermissionMatchPatterns.keys) {
                context.setPermissionStatus(.unknown, for: pattern)
            }
            for pattern in required.union(optional) {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
        case .chosenSites:
            // Only the chosen sites, click grants and site-specific optional grants stay.
            //
            // Limitation: WebKit keeps running content scripts it set up under a broad
            // grant (`<all_urls>`) when that grant is merely forgotten (`.unknown`); only
            // an explicit denial takes them out of pages. WebKit also remembers grants
            // across launches. So everything else is denied explicitly, then the kept
            // sites are granted, and an explicit grant for a site wins over the broad
            // denial. A side effect: `permissions.request` for a new site is refused
            // while access is limited; the extension's button grants it instead.
            let hosts = item.record.allowedSites + (clickGrants[item.id] ?? [])
            let kept = hosts.compactMap(Self.pattern(for:)) + optional.filter(Self.isSitePattern)
            let keep = Set(kept.map(\.string))
            for pattern in Array(context.grantedPermissionMatchPatterns.keys) + Array(required.union(optional)) where !keep.contains(pattern.string) {
                context.setPermissionStatus(.deniedExplicitly, for: pattern)
            }
            for pattern in kept {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
        }
    }

    /// `*://host/*`: one site, the way site access grants it.
    private static func pattern(for host: String) -> WKWebExtension.MatchPattern? {
        try? WKWebExtension.MatchPattern(string: "*://\(host)/*")
    }

    /// A pattern for a single named host, kept when access is narrowed to chosen sites.
    private static func isSitePattern(_ pattern: WKWebExtension.MatchPattern) -> Bool {
        guard !pattern.matchesAllURLs, !pattern.matchesAllHosts, let host = pattern.host, !host.isEmpty else { return false }
        return !host.hasPrefix("*")
    }

    /// A click on the button of an extension limited to chosen sites grants it the
    /// page's site, like Chrome's "When you click the extension".
    private func grantOnClick(_ item: InstalledExtension, tab: ExtensionTab?) {
        guard let page = tab?.page, let url = page.url, wantsAccess(item, to: url), let host = url.host(),
              let context = item.context, let pattern = Self.pattern(for: host) else { return }
        clickGrants[item.id, default: []].insert(host)
        context.setPermissionStatus(.grantedExplicitly, for: pattern)
        item.actionVersion += 1
        pageNeedingReload = page.id
    }

    // MARK: Installing

    /// Reads, downloads or fetches a package from a store, then asks in the front window.
    func beginInstall(_ source: ExtensionPackage.Source) {
        guard installing == nil else { return }
        if case .store(let store, let storeID) = source, let existing = items.first(where: { $0.record.matches(store: store, id: storeID) }) {
            present(.alreadyInstalled(existing.name))
            return
        }
        installing = source.key
        refreshStorePages()
        Task {
            defer {
                installing = nil
                refreshStorePages()
            }
            let id = UUID().uuidString
            do {
                var record = ExtensionRecord(id: id, packageName: "")
                let file: URL
                switch source {
                case .file(let url):
                    file = url
                case .download(let url):
                    file = try await ExtensionPackage.download(url)
                case .store(let store, let storeID):
                    guard let release = try await store.latest(storeID) else { throw ExtensionStore.Failure.notFound }
                    // Firefox Add-ons pages use a slug; imported add-ons are known by GUID.
                    if let guid = release.guid, let existing = items.first(where: { $0.record.matches(store: store, id: guid) }) {
                        existing.record.storeAliases = Array(Set(existing.record.storeAliases + [storeID]))
                        save()
                        present(.alreadyInstalled(existing.name))
                        return
                    }
                    file = try await ExtensionStore.download(release)
                    record.source = .store(store, id: storeID)
                    record.storeAliases = release.guid.map { [$0] } ?? []
                }
                defer { if case .file = source {} else { try? FileManager.default.removeItem(at: file) } }
                record.packageName = try ExtensionPackage.stage(file, id: id)
                let webExtension = try await WKWebExtension(resourceBaseURL: ExtensionPackage.packageURL(for: record))
                if let existing = duplicate(of: webExtension, from: record.source) {
                    try? FileManager.default.removeItem(at: ExtensionPackage.folder(for: id))
                    present(.alreadyInstalled(existing.name))
                    return
                }
                staged[id] = (record, webExtension)
                present(.request(ExtensionInstallRequest(id: id, webExtension: webExtension, source: record.source)))
            } catch {
                try? FileManager.default.removeItem(at: ExtensionPackage.folder(for: id))
                present(.failed(error.localizedDescription))
            }
        }
    }

    /// The same store item, or the same name and version.
    private func duplicate(of webExtension: WKWebExtension, from origin: ExtensionRecord.Source) -> InstalledExtension? {
        items.first { item in
            if let store = origin.storeItem, item.record.matches(store: store.store, id: store.id) { return true }
            return item.name == (webExtension.displayName ?? "") && item.version == (webExtension.displayVersion ?? webExtension.version ?? "")
        }
    }

    private func present(_ prompt: ExtensionInstallPrompt) {
        #if DEBUG
        // `-WakeDebugConfirm YES`: say yes without the sheet (see DebugLaunch).
        if UserDefaults.standard.bool(forKey: "WakeDebugConfirm") {
            if case .request(let request) = prompt { confirmInstall(request.id) }
            DebugLaunch.note("install prompt \(prompt.id)")
            return
        }
        #endif
        guard let browser = BrowserModel.active else { return }
        browser.extensionPrompt = prompt
        browser.window?.makeKeyAndOrderFront(nil)
    }

    func confirmInstall(_ id: String) {
        guard let (record, webExtension) = staged.removeValue(forKey: id) else { return }
        let item = InstalledExtension(record: record, webExtension: webExtension)
        // Without a toolbar action there's nothing to click; keep it out of the toolbar.
        item.record.isPinned = item.hasToolbarAction
        items.append(item)
        load(item)
        save()
        tabs.resyncAll()
        refreshStorePages()
    }

    func cancelInstall(_ id: String) {
        guard staged.removeValue(forKey: id) != nil else { return }
        try? FileManager.default.removeItem(at: ExtensionPackage.folder(for: id))
    }

    // MARK: Importing from other browsers

    private(set) var isImporting = false

    /// Copies extensions from other browsers' profiles. The person chose them in the
    /// import sheet, which showed what each can access, so there's no second question.
    /// Returns how many were added.
    @discardableResult
    func importExtensions(_ list: [ImportableExtension]) async -> Int {
        isImporting = true
        defer { isImporting = false }
        var added = 0
        var pinned = items.filter(\.record.isPinned).count
        for candidate in list {
            if let store = candidate.store, let storeID = candidate.storeID,
               items.contains(where: { $0.record.matches(store: store, id: storeID) }) { continue }
            if items.contains(where: { $0.name == candidate.name && $0.version == candidate.version }) { continue }
            let id = UUID().uuidString
            do {
                var record = ExtensionRecord(id: id, packageName: try ExtensionPackage.stage(candidate.package, id: id))
                record.source = .imported(browser: candidate.browser, store: candidate.store, id: candidate.storeID)
                record.isEnabled = candidate.isEnabled
                let webExtension = try await WKWebExtension(resourceBaseURL: ExtensionPackage.packageURL(for: record))
                let item = InstalledExtension(record: record, webExtension: webExtension)
                // A whole browser's worth would crowd the toolbar: the first few with a
                // button are pinned, the rest wait in the extensions menu.
                item.record.isPinned = item.hasToolbarAction && candidate.isEnabled && pinned < 5
                if item.record.isPinned { pinned += 1 }
                items.append(item)
                if record.isEnabled { load(item) }
                added += 1
            } catch {
                try? FileManager.default.removeItem(at: ExtensionPackage.folder(for: id))
                NSLog("Wake: couldn't import \(candidate.name) from \(candidate.browser): \(error.localizedDescription)")
            }
        }
        save()
        tabs.resyncAll()
        refreshStorePages()
        return added
    }

    // MARK: Updates

    private(set) var isCheckingForUpdates = false
    private(set) var lastUpdateCheck: Date? = UserDefaults.standard.object(forKey: "extensions.lastUpdateCheck") as? Date
    /// What the last check did, for Settings ("2 updated").
    private(set) var lastUpdateSummary: String?
    @ObservationIgnored private var updateLoop: Task<Void, Never>?
    private static let updateInterval: TimeInterval = 5 * 60 * 60

    /// Checks every few hours while Wake runs, starting shortly after launch.
    private func scheduleUpdates() {
        updateLoop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            while !Task.isCancelled {
                guard let self else { return }
                if Date().timeIntervalSince(self.lastUpdateCheck ?? .distantPast) > Self.updateInterval {
                    await self.checkForUpdates()
                }
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    /// Updates every extension that came from a store (or from a browser that got it
    /// from one). An update that asks for more access waits for a yes in Settings.
    func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        var updated: [String] = []
        var waiting = 0
        for item in items {
            guard let (store, storeID) = item.record.source.storeItem else { continue }
            do {
                guard let release = try await store.latest(storeID, currentVersion: item.webExtension.version ?? "0"),
                      ExtensionStore.isNewer(release.version, than: item.webExtension.version ?? "0") else { continue }
                switch try await applyUpdate(item, release, approved: false) {
                case .applied: updated.append(item.name)
                case .needsApproval: waiting += 1
                }
            } catch {
                NSLog("Wake: update check for \(item.name) failed: \(error.localizedDescription)")
            }
        }
        lastUpdateCheck = Date()
        UserDefaults.standard.set(lastUpdateCheck, forKey: "extensions.lastUpdateCheck")
        var parts: [String] = []
        if !updated.isEmpty { parts.append(updated.count == 1 ? "Updated \(updated[0])" : "Updated \(updated.count) extensions") }
        if waiting > 0 { parts.append("\(waiting) waiting for your OK") }
        lastUpdateSummary = parts.isEmpty ? "Everything is up to date" : parts.joined(separator: " · ")
        save()
    }

    /// Installs the pending update after the person agreed to its new access.
    func approveUpdate(_ item: InstalledExtension) async {
        guard let (store, storeID) = item.record.source.storeItem else { return }
        do {
            guard let release = try await store.latest(storeID, currentVersion: item.webExtension.version ?? "0") else {
                item.record.pendingUpdateVersion = nil
                save()
                return
            }
            _ = try await applyUpdate(item, release, approved: true)
        } catch {
            item.loadError = error.localizedDescription
        }
    }

    private enum UpdateResult { case applied, needsApproval }

    /// Swaps in the new package and reloads the extension under the same identity, so
    /// its storage and granted permissions carry over.
    private func applyUpdate(_ item: InstalledExtension, _ release: ExtensionStore.Release, approved: Bool) async throws -> UpdateResult {
        let file = try await ExtensionStore.download(release)
        defer { try? FileManager.default.removeItem(at: file) }
        let folder = ExtensionPackage.folder(for: item.id)
        let incoming = folder.appendingPathComponent("incoming-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: incoming) }
        let name = try ExtensionPackage.stage(file, into: incoming)
        let candidate = try await WKWebExtension(resourceBaseURL: incoming.appendingPathComponent(name))
        let before = Set(ExtensionPermissionSummary(item.webExtension).lines.map(\.text))
        let after = Set(ExtensionPermissionSummary(candidate).lines.map(\.text))
        if !approved, !after.isSubset(of: before) {
            item.record.pendingUpdateVersion = release.version
            save()
            return .needsApproval
        }
        let wasLoaded = item.context != nil
        if let context = item.context {
            context.action(for: nil)?.closePopup()
            try? controller.unload(context)
            item.context = nil
        }
        let manager = FileManager.default
        try? manager.removeItem(at: folder.appendingPathComponent(item.record.packageName))
        try manager.moveItem(at: incoming.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        item.record.packageName = name
        item.record.pendingUpdateVersion = nil
        item.webExtension = try await WKWebExtension(resourceBaseURL: ExtensionPackage.packageURL(for: item.record))
        if wasLoaded { load(item) }
        item.actionVersion += 1
        save()
        tabs.resyncAll()
        return .applied
    }

    // MARK: Store pages

    /// The store item being fetched, so its page shows "Adding…".
    private(set) var installing: String?

    /// What store pages need to label their buttons: installed ids per store.
    var storeState: [String: Any] {
        var installed: [String: [String]] = [:]
        for item in items {
            guard let (store, storeID) = item.record.source.storeItem else { continue }
            installed[store.rawValue, default: []] += [storeID] + item.record.storeAliases
        }
        return ["installed": installed, "installing": installing ?? ""]
    }

    /// Tells open store pages what changed (installed, removed, in progress).
    func refreshStorePages() {
        let state = storeState
        for browser in BrowserModel.everyWindow {
            for page in browser.trail.columns where ExtensionStore.item(in: page.url) != nil {
                page.webView.callAsyncJavaScript(
                    "window.__wakeStores && window.__wakeStores.update(state);",
                    arguments: ["state": state], in: nil, in: WebScripts.world
                ) { _ in }
            }
        }
    }

    /// A store page's "Remove from Wake".
    func removeFromStorePage(store: ExtensionStore, id: String) {
        guard let item = items.first(where: { $0.record.matches(store: store, id: id) }) else { return }
        Task {
            let alert = NSAlert()
            alert.messageText = "Remove “\(item.name)”?"
            alert.informativeText = "Its settings and the data it stored are deleted too."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            let answer: NSApplication.ModalResponse
            if let window = BrowserModel.active?.window { answer = await alert.beginSheetModal(for: window) } else { answer = alert.runModal() }
            if answer == .alertFirstButtonReturn { remove(item) }
        }
    }

    // MARK: Keyboard shortcuts

    @ObservationIgnored private var keyMonitor: Any?

    /// Extensions' `commands` (e.g. Dark Reader's ⌥⇧D). A shortcut Wake's own menus
    /// use stays Wake's.
    private func monitorShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { ExtensionLibrary.shared.performCommand(for: event) }
            return handled ? nil : event
        }
    }

    private func performCommand(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard !modifiers.isEmpty, !Self.menu(NSApp.mainMenu, claims: event) else { return false }
        for item in enabled {
            guard let context = item.context, let command = context.command(for: event) else { continue }
            // `_execute_action` opens the popup: hang it from the right button.
            context.performCommand(command)
            return true
        }
        return false
    }

    private static func menu(_ menu: NSMenu?, claims event: NSEvent) -> Bool {
        guard let menu else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let pressed = event.modifierFlags.intersection(mask)
        for item in menu.items {
            if !item.keyEquivalent.isEmpty, item.keyEquivalent.lowercased() == key,
               item.keyEquivalentModifierMask.intersection(mask).subtracting(.shift) == pressed.subtracting(.shift) {
                return true
            }
            if self.menu(item.submenu, claims: event) { return true }
        }
        return false
    }

    // MARK: Context menus

    /// Items extensions add to a page's right-click menu (`contextMenus` / `menus`):
    /// one extension's single item goes in as is, several go in a submenu named after it.
    func menuItems(for page: BrowserPage) -> [NSMenuItem] {
        guard let tab = tabs.existingTab(for: page) else { return [] }
        var result: [NSMenuItem] = []
        for item in enabled {
            guard let context = item.context else { continue }
            let entries = context.menuItems(for: tab)
            guard !entries.isEmpty else { continue }
            if entries.count == 1, let only = entries.first {
                if only.image == nil { only.image = item.icon(16).map(Self.menuIcon) }
                result.append(only)
            } else {
                let parent = NSMenuItem(title: item.name, action: nil, keyEquivalent: "")
                parent.image = item.icon(16).map(Self.menuIcon)
                let submenu = NSMenu(title: item.name)
                entries.forEach(submenu.addItem)
                parent.submenu = submenu
                result.append(parent)
            }
        }
        return result
    }

    private static func menuIcon(_ image: NSImage) -> NSImage {
        let sized = image.copy() as? NSImage ?? image
        sized.size = NSSize(width: 16, height: 16)
        return sized
    }

    // MARK: Managing

    func setEnabled(_ item: InstalledExtension, _ enabled: Bool) {
        guard item.record.isEnabled != enabled else { return }
        item.record.isEnabled = enabled
        if enabled {
            load(item)
            tabs.resyncAll()
        } else if let context = item.context {
            context.action(for: nil)?.closePopup()
            try? controller.unload(context)
            item.context = nil
        }
        save()
    }

    func setPinned(_ item: InstalledExtension, _ pinned: Bool) {
        item.record.isPinned = pinned
        save()
    }

    /// Unloads the extension, deletes its files and the data it stored.
    func remove(_ item: InstalledExtension) {
        let context = item.context
        if let context { try? controller.unload(context) }
        item.context = nil
        items.removeAll { $0 === item }
        save()
        refreshStorePages()
        try? FileManager.default.removeItem(at: ExtensionPackage.folder(for: item.id))
        guard let context else { return }
        let types = WKWebExtensionController.allExtensionDataTypes
        controller.fetchDataRecord(ofTypes: types, for: context) { [controller] record in
            guard let record else { return }
            MainActor.assumeIsolated {
                controller.removeData(ofTypes: types, from: [record]) {}
            }
        }
    }

    func openOptions(_ item: InstalledExtension) {
        guard let url = item.context?.optionsPageURL, let browser = BrowserModel.active else { return }
        browser.hideSettings()
        browser.trail.open(url)
    }

    // MARK: Toolbar

    func action(of item: InstalledExtension, in browser: BrowserModel) -> WKWebExtension.Action? {
        item.context?.action(for: tabs.activeTab(in: browser))
    }

    /// A toolbar button was clicked: the extension's popup opens, or its click handler runs.
    func performAction(_ item: InstalledExtension, in browser: BrowserModel) {
        guard let context = item.context else { return }
        let tab = tabs.activeTab(in: browser)
        grantOnClick(item, tab: tab)
        context.performAction(for: tab)
    }

    func register(anchor view: NSView, for id: String) {
        var list = anchors[id, default: []].filter { $0.view != nil && $0.view !== view }
        list.append(WeakView(view: view))
        anchors[id] = list
    }

    /// The button to hang a popup from: this extension's in the key window, else the
    /// extensions menu button, else nothing (the popup is then centred under the toolbar).
    private func anchor(for id: String) -> NSView? {
        let key = NSApp.keyWindow ?? BrowserModel.active?.window
        func visible(_ list: [WeakView]?) -> NSView? {
            list?.compactMap(\.view).first { $0.window === key && !$0.isHiddenOrHasHiddenAncestor && $0.window?.isVisible == true }
        }
        return visible(anchors[id]) ?? visible(anchors[Self.menuAnchorID])
    }

    static let menuAnchorID = "wake.extensions.menu"

    // MARK: Storage

    private static var indexURL: URL { ExtensionPackage.root.appendingPathComponent("extensions.json") }

    private static func readRecords() -> [ExtensionRecord] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([ExtensionRecord].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: ExtensionPackage.root, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items.map(\.record)).write(to: Self.indexURL, options: .atomic)
        } catch {
            NSLog("Wake: couldn't save extensions: \(error.localizedDescription)")
        }
    }

    fileprivate func item(for context: WKWebExtensionContext) -> InstalledExtension? {
        items.first { $0.context === context }
    }

    fileprivate func remember(_ item: InstalledExtension, permissions: Set<WKWebExtension.Permission> = [], patterns: Set<WKWebExtension.MatchPattern> = []) {
        item.record.grantedPermissions = Array(Set(item.record.grantedPermissions).union(permissions.map(\.rawValue))).sorted()
        item.record.grantedMatchPatterns = Array(Set(item.record.grantedMatchPatterns).union(patterns.map(\.string))).sorted()
        save()
    }
}

// MARK: - WebKit's questions

@available(macOS 15.4, *)
extension ExtensionLibrary: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        tabs.openWindows()
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        BrowserModel.active.map(tabs.window(for:))
    }

    /// `tabs.create`: a new column after the extension's tab, or at the end.
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        let browser = (configuration.window as? ExtensionWindow)?.browser ?? BrowserModel.active
        guard let browser else {
            completionHandler(nil, ExtensionTabs.failure("Wake has no window open."))
            return
        }
        let parent = (configuration.parentTab as? ExtensionTab)?.page
        let page = browser.trail.open(configuration.url ?? URL(string: "about:blank")!, after: parent, focus: configuration.shouldBeActive)
        Extensions.windowChanged(browser)
        completionHandler(tabs.tab(for: page, in: browser), nil)
    }

    /// `windows.create`.
    ///
    /// Limitation: a Wake window is a SwiftUI scene, which can't be created from here
    /// and handed back synchronously. The tabs open as columns in the front window,
    /// and that window is reported as the new one.
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard let browser = BrowserModel.active else {
            completionHandler(nil, ExtensionTabs.failure("Wake has no window open."))
            return
        }
        for url in configuration.tabURLs {
            browser.trail.open(url)
        }
        Extensions.windowChanged(browser)
        completionHandler(tabs.window(for: browser), nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let item = item(for: extensionContext) else {
            completionHandler(ExtensionTabs.failure("No options page."))
            return
        }
        openOptions(item)
        completionHandler(nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        guard let item = item(for: extensionContext) else { return completionHandler([], nil) }
        let lines = ExtensionPermissionSummary(permissions: permissions, patterns: []).lines.map { "• \($0.text)" }
        Task {
            let allowed = await Self.ask(
                "“\(item.name)” would like more access",
                lines.isEmpty ? permissions.map(\.rawValue).sorted().joined(separator: ", ") : lines.joined(separator: "\n")
            )
            if allowed { remember(item, permissions: permissions) }
            completionHandler(allowed ? permissions : [], nil)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        guard let item = item(for: extensionContext) else { return completionHandler([], nil) }
        let hosts = Set(urls.compactMap { $0.host() }).sorted()
        Task {
            let allowed = await Self.ask(
                "Allow “\(item.name)” on \(hosts.count == 1 ? hosts[0] : "these sites")?",
                "It will be able to read and change \(hosts.count == 1 ? "this site" : hosts.joined(separator: ", "))."
            )
            if allowed {
                remember(item, patterns: Set(hosts.compactMap { try? WKWebExtension.MatchPattern(string: "*://\($0)/*") }))
            }
            completionHandler(allowed ? urls : [], nil)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        guard let item = item(for: extensionContext) else { return completionHandler([], nil) }
        let summary = ExtensionPermissionSummary(permissions: [], patterns: matchPatterns)
        Task {
            let allowed = await Self.ask(
                "“\(item.name)” would like more access",
                summary.lines.map { "• \($0.text)" }.joined(separator: "\n")
            )
            if allowed { remember(item, patterns: matchPatterns) }
            completionHandler(allowed ? matchPatterns : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action, forExtensionContext context: WKWebExtensionContext) {
        item(for: context)?.actionVersion += 1
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let popover = action.popupPopover, let item = item(for: context) else {
            completionHandler(ExtensionTabs.failure("This extension has no popup."))
            return
        }
        popover.behavior = .transient
        if let anchor = anchor(for: item.id) {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else if let content = (NSApp.keyWindow ?? BrowserModel.active?.window)?.contentView {
            // The toolbar is hidden (Zen) or the extension isn't pinned and its menu is
            // closed: hang the popup from the top right, where the buttons would be.
            let y = content.isFlipped ? Metrics.toolbarHeight - 8 : content.bounds.maxY - Metrics.toolbarHeight + 8
            let rect = NSRect(x: content.bounds.maxX - 120, y: y, width: 1, height: 1)
            popover.show(relativeTo: rect, of: content, preferredEdge: content.isFlipped ? .maxY : .minY)
        }
        completionHandler(nil)
    }

    /// Limitation: native messaging (`runtime.sendNativeMessage`, `connectNative`)
    /// reaches the app, not a helper. Wake has no native hosts, and the App Sandbox
    /// would keep it from launching Chrome-style host executables, so these fail.
    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        replyHandler(nil, ExtensionTabs.failure("Wake doesn't support native messaging."))
    }

    private static func ask(_ title: String, _ message: String) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        if let window = NSApp.keyWindow ?? BrowserModel.active?.window {
            return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
