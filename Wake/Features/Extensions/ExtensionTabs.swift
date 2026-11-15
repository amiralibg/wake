import AppKit
import WebKit

/// How Wake looks to extensions: each browser window is a `chrome.windows` window,
/// and the columns of the thread it shows are its tabs, in trail order.
///
/// - DevTools columns, device previews, pinned apps, Pop Out panels and the Moments
///   watcher are not tabs. Pinned apps still get content scripts (their web views
///   join the controller), so an ad blocker covers them too.
/// - Threads you switched away from aren't reported: switching threads closes the
///   old thread's tabs and opens the new one's, as far as extensions can tell.
///   Discarded threads have no web views to report anyway.
@available(macOS 15.4, *)
@MainActor
final class ExtensionTabs {
    private let controller: WKWebExtensionController
    private var tabs: [BrowserPage.ID: ExtensionTab] = [:]
    private var windows: [ObjectIdentifier: ExtensionWindow] = [:]
    private var focusObserver: NSObjectProtocol?

    init(controller: WKWebExtensionController) {
        self.controller = controller
        focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let window, let match = self.windows.values.first(where: { $0.browser?.window === window }) else { return }
                self.controller.didFocusWindow(match)
            }
        }
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "app.wake.extensions", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func window(for browser: BrowserModel) -> ExtensionWindow {
        let key = ObjectIdentifier(browser)
        if let existing = windows[key] { return existing }
        let made = ExtensionWindow(browser: browser, tabs: self)
        windows[key] = made
        return made
    }

    func tab(for page: BrowserPage, in browser: BrowserModel) -> ExtensionTab {
        if let existing = tabs[page.id] { return existing }
        let made = ExtensionTab(page: page, window: window(for: browser))
        tabs[page.id] = made
        return made
    }

    /// The tab already reported for a page; nil for pages that aren't tabs (pinned apps).
    func existingTab(for page: BrowserPage) -> ExtensionTab? { tabs[page.id] }

    func activeTab(in browser: BrowserModel) -> ExtensionTab? {
        guard let page = browser.webPage, Self.isTab(page) else { return nil }
        return tab(for: page, in: browser)
    }

    /// Windows front to back.
    func openWindows() -> [any WKWebExtensionWindow] {
        let open = windows.values.filter { $0.browser?.window != nil && $0.isReported }
        let order = NSApp.orderedWindows
        return open.sorted { a, b in
            (order.firstIndex { $0 === a.browser?.window } ?? .max) < (order.firstIndex { $0 === b.browser?.window } ?? .max)
        }
    }

    static func isTab(_ page: BrowserPage) -> Bool {
        !page.isDevTools && !page.isEphemeral && !page.isClosed
    }

    static func pages(in browser: BrowserModel) -> [BrowserPage] {
        browser.trail.columns.filter(isTab)
    }

    // MARK: Telling WebKit what changed

    /// Diffs the window's tabs against what was last reported.
    func sync(_ browser: BrowserModel) {
        let window = window(for: browser)
        if !window.isReported {
            window.isReported = true
            controller.didOpenWindow(window)
        }
        let pages = Self.pages(in: browser)
        let ids = pages.map(\.id)
        let previous = window.reportedIDs
        let current = Set(ids)
        for id in previous where !current.contains(id) {
            if let tab = tabs.removeValue(forKey: id) { controller.didCloseTab(tab, windowIsClosing: false) }
        }
        let kept = Set(previous)
        for page in pages where !kept.contains(page.id) {
            controller.didOpenTab(tab(for: page, in: browser))
        }
        // Moves among the tabs that were there before and still are.
        let before = previous.filter(current.contains)
        let after = ids.filter(kept.contains)
        if before != after {
            for (index, id) in after.enumerated() where before[index] != id {
                if let tab = tabs[id], let from = before.firstIndex(of: id) { controller.didMoveTab(tab, from: from, in: window) }
            }
        }
        window.reportedIDs = ids
        let active = activeTab(in: browser)
        if active?.page?.id != window.reportedActiveID {
            let previousTab = window.reportedActiveID.flatMap { tabs[$0] }
            if let active { controller.didActivateTab(active, previousActiveTab: previousTab) }
            window.reportedActiveID = active?.page?.id
        }
    }

    /// After extensions load, so they see windows that were already open.
    func resyncAll() {
        for window in windows.values {
            if let browser = window.browser { sync(browser) }
        }
        if let browser = BrowserModel.active { sync(browser) }
    }

    func close(_ browser: BrowserModel) {
        guard let window = windows.removeValue(forKey: ObjectIdentifier(browser)) else { return }
        for id in window.reportedIDs {
            if let tab = tabs.removeValue(forKey: id) { controller.didCloseTab(tab, windowIsClosing: true) }
        }
        if window.isReported { controller.didCloseWindow(window) }
    }

    func pageChanged(_ page: BrowserPage, _ change: Extensions.PageChange) {
        guard let tab = tabs[page.id] else { return }
        let properties: WKWebExtension.TabChangedProperties = switch change {
        case .title: .title
        case .url: .URL
        case .loading: .loading
        case .audio: .playingAudio
        case .zoom: .zoomFactor
        }
        controller.didChangeTabProperties(properties, for: tab)
    }
}

/// One Wake window, as `chrome.windows` sees it.
@available(macOS 15.4, *)
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    weak var browser: BrowserModel?
    private unowned let registry: ExtensionTabs
    var isReported = false
    var reportedIDs: [BrowserPage.ID] = []
    var reportedActiveID: BrowserPage.ID?

    init(browser: BrowserModel, tabs: ExtensionTabs) {
        self.browser = browser
        registry = tabs
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let browser else { return [] }
        return ExtensionTabs.pages(in: browser).map { registry.tab(for: $0, in: browser) }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        browser.flatMap(registry.activeTab(in:))
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = browser?.window else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return window.isZoomed ? .maximized : .normal
    }

    func setWindowState(_ state: WKWebExtension.WindowState, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let window = browser?.window else { return completionHandler(ExtensionTabs.failure("The window is gone.")) }
        switch state {
        case .minimized: window.miniaturize(nil)
        case .fullscreen: if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        case .maximized: if !window.isZoomed { window.zoom(nil) }
        default:
            if window.isMiniaturized { window.deminiaturize(nil) }
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
        completionHandler(nil)
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        browser?.window?.frame ?? .null
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        browser?.window?.screen?.frame ?? NSScreen.main?.frame ?? .null
    }

    func setFrame(_ frame: CGRect, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        browser?.window?.setFrame(frame, display: true, animate: false)
        completionHandler(nil)
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        browser?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        browser?.window?.performClose(nil)
        completionHandler(nil)
    }
}

/// One column, as `chrome.tabs` sees it.
@available(macOS 15.4, *)
@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    weak var page: BrowserPage?
    private weak var owner: ExtensionWindow?

    init(page: BrowserPage, window: ExtensionWindow) {
        self.page = page
        owner = window
    }

    private var trail: TrailModel? { owner?.browser?.trail }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { owner }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        guard let browser = owner?.browser, let page else { return 0 }
        return ExtensionTabs.pages(in: browser).firstIndex { $0 === page } ?? 0
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        page.flatMap { $0.isClosed ? nil : $0.webView }
    }

    func title(for context: WKWebExtensionContext) -> String? { page?.title }
    func url(for context: WKWebExtensionContext) -> URL? { page?.url }

    func pendingURL(for context: WKWebExtensionContext) -> URL? {
        guard let page, page.isLoading, page.requestedURL != page.url else { return nil }
        return page.requestedURL
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !(page?.isLoading ?? false) }
    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool { page?.isPlayingMedia ?? false }
    func isSelected(for context: WKWebExtensionContext) -> Bool { trail?.focused === page }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { Double(page?.zoom ?? 1) }

    func size(for context: WKWebExtensionContext) -> CGSize {
        page?.webView.bounds.size ?? .zero
    }

    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        page?.setZoom(CGFloat(zoomFactor))
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        page?.load(url)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        fromOrigin ? page?.reloadFromOrigin() : page?.reload()
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        page?.goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        page?.goForward()
        completionHandler(nil)
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let page, let browser = owner?.browser else { return completionHandler(ExtensionTabs.failure("The tab is gone.")) }
        browser.window?.makeKeyAndOrderFront(nil)
        browser.trail.focus(id: page.id)
        completionHandler(nil)
    }

    func duplicate(using configuration: WKWebExtension.TabConfiguration, for context: WKWebExtensionContext, completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let page, let browser = owner?.browser, let url = page.url ?? page.requestedURL else {
            return completionHandler(nil, ExtensionTabs.failure("The tab is gone."))
        }
        let copy = browser.trail.open(url, after: page, focus: configuration.shouldBeActive)
        Extensions.windowChanged(browser)
        completionHandler(ExtensionLibrary.shared.tabs.tab(for: copy, in: browser), nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let page { trail?.close(page) }
        completionHandler(nil)
    }

    func takeSnapshot(using configuration: WKSnapshotConfiguration, for context: WKWebExtensionContext, completionHandler: @escaping (NSImage?, (any Error)?) -> Void) {
        guard let webView = page?.webView else { return completionHandler(nil, ExtensionTabs.failure("The tab is gone.")) }
        webView.takeSnapshot(with: configuration) { image, error in
            completionHandler(image, error)
        }
    }

    /// A click in the page grants `activeTab`, as in Chrome and Safari.
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }
}
