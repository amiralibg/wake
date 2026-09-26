import AppKit
import Observation
import WebKit

/// One live page: owns a WKWebView and mirrors its state for SwiftUI.
/// (Named to avoid WebKit's own `WebPage` type on macOS 26.)
@MainActor
@Observable
final class BrowserPage: NSObject, Identifiable {
    let id = UUID()
    /// Replaced by an empty placeholder once the page is closed (see `close()`).
    @ObservationIgnored private(set) var webView: WKWebView
    @ObservationIgnored private(set) var isClosed = false

    private(set) var title = ""
    private(set) var url: URL?
    private(set) var progress: Double = 0
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isSecure = false
    private(set) var faviconURL: URL?
    private(set) var failure: String?
    /// Reported by the page: audio or video is playing.
    private(set) var isPlayingMedia = false
    /// Reported by the page: a form has input that hasn't been submitted.
    private(set) var hasUnsavedInput = false
    /// Media time, price, CI, content changes and HTTP status, for live chips.
    private(set) var live = LiveState()
    @ObservationIgnored private var pendingHTTPStatus: Int?

    // MARK: Developer mode

    /// Console, network and HMR observed while in developer mode.
    let devtools = DevToolsLog()
    /// Set from DevTools ▸ Tools: the next documents load with their scripts off.
    var isJavaScriptDisabled = false
    @ObservationIgnored private var session: DevToolsSession?
    /// Elements, storage, performance and page overrides for the DevTools column.
    /// Made on first use: most pages are never inspected.
    var inspector: DevToolsSession {
        if let session { return session }
        let made = DevToolsSession(page: self)
        session = made
        return made
    }
    private(set) var isDeveloperMode = false
    /// The thread's choice; `nil` means automatic (on for localhost).
    var developerModeOverride: Bool? {
        didSet { updateDeveloperMode(for: url, applyNow: true) }
    }
    private(set) var isInspectingComponents = false
    /// The Pop Out picker is outlining elements under the pointer.
    private(set) var isPickingPopOut = false
    /// The document is JSON and is shown with the viewer.
    private(set) var isJSONDocument = false
    /// A DevTools column shows this page's log instead of a web page.
    @ObservationIgnored private(set) weak var inspectedPage: BrowserPage?
    let isDevTools: Bool
    /// Not saved with the thread (DevTools and responsive previews).
    @ObservationIgnored var isEphemeral = false
    /// Set on a responsive preview column: the device it lays the page out for.
    var device: DeviceFrame? {
        didSet {
            guard device?.preset.userAgent != oldValue?.preset.userAgent else { return }
            webView.customUserAgent = device?.preset.userAgent
            if oldValue != nil, url != nil { webView.reload() }
        }
    }
    /// Linked to a responsive preview: report scroll position after each load.
    @ObservationIgnored var syncsScroll = false

    /// The component inspector picked something.
    @ObservationIgnored var onInspect: ((ComponentPick) -> Void)?
    /// A linked page reports its scroll position (0…1).
    @ObservationIgnored var onScroll: ((Double) -> Void)?

    /// A moment to take the next loaded document back to (scroll and highlight).
    @ObservationIgnored var pendingRestore: MomentRestore?
    /// Where to scroll once the next document has loaded (a discarded thread coming back).
    @ObservationIgnored var pendingScrollY: Double?
    /// Called once a restore has been applied, e.g. to refresh the moment's baseline.
    @ObservationIgnored var onRestored: ((BrowserPage) -> Void)?

    /// Called after each committed main-frame load finishes.
    @ObservationIgnored var onDidFinish: ((BrowserPage) -> Void)?
    /// Set while a restored column loads its saved page: bringing a thread back isn't
    /// a new visit, so History skips that first load.
    @ObservationIgnored var isRestoring = false
    /// A link was clicked: open it as a new column (`background` = don't focus it).
    @ObservationIgnored var onOpenLink: ((URL, _ background: Bool) -> Void)?
    /// `target=_blank` / `window.open`: return the web view that hosts the popup.
    @ObservationIgnored var onOpenPopup: ((WKWebViewConfiguration) -> WKWebView?)?
    /// The page called `window.close()`.
    @ObservationIgnored var onClose: (() -> Void)?
    /// URL or title changed: time to persist.
    @ObservationIgnored var onStateChange: (() -> Void)?
    /// What was last asked for, before WebKit reports a committed URL.
    private(set) var requestedURL: URL?

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration = .wake()) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        isDevTools = false
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // Horizontal swipes belong to the trail, so WebKit's back/forward swipe is off.
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true
        webView.isInspectable = true
        observeWebView()
        #if BENCH
        Benchmark.track(self)
        #endif
    }

    /// A DevTools column for `target`. It never loads anything itself.
    init(devToolsFor target: BrowserPage) {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        isDevTools = true
        inspectedPage = target
        super.init()
        isEphemeral = true
    }

    var displayTitle: String {
        if isDevTools { return "DevTools · \(inspectedPage?.host ?? "")" }
        let base = !title.isEmpty ? title : ((url ?? requestedURL)?.host() ?? "New page")
        return device.map { "\($0.preset.name) · \(base)" } ?? base
    }

    var host: String {
        guard let host = url?.host() else { return url?.absoluteString ?? "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func load(_ url: URL) {
        failure = nil
        requestedURL = url
        webView.load(URLRequest(url: url))
    }

    func reload() { webView.reload() }

    /// The document's vertical scroll position, or nil if it can't be read.
    func scrollY() async -> Double? {
        try? await webView.evaluateJavaScript("window.scrollY") as? Double
    }

    /// Reloads without the cache (⌥⌘R).
    func reloadFromOrigin() { webView.reloadFromOrigin() }

    func stopLoading() { webView.stopLoading() }

    /// Columns scrolled well off the stage are hidden from WebKit, which then treats
    /// the page like a background tab: timers are throttled, requestAnimationFrame
    /// and CSS animations stop, and nothing is painted. Audio keeps playing.
    ///
    /// Limitation: WebKit only learns visibility from the view (hidden, or out of a
    /// window) and the window's occlusion; a view that is merely clipped or scrolled
    /// away still counts as visible, hence the explicit hiding.
    func setOnStage(_ onStage: Bool) {
        hideTask?.cancel()
        hideTask = nil
        if onStage {
            if webView.isHidden { webView.isHidden = false }
        } else if !webView.isHidden {
            // After the trail has finished sliding it out of view.
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, let self, self.webView.window?.firstResponder !== self.webView else { return }
                self.webView.isHidden = true
            }
        }
    }

    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// The column is gone for good: let its web view, and the WebContent process
    /// behind it, go now.
    ///
    /// SwiftUI can keep a removed view's values (and through them this page) until
    /// that part of the window next updates: the toolbar's trail chips, a context
    /// menu, a hover callback. Measured, closed pages kept 100–500 MB each for as
    /// long as the window sat idle. Swapping in an empty web view that never loads
    /// (WebKit starts a WebContent process on first load) frees the real one no
    /// matter who still holds the page.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        hideTask?.cancel()
        observations.forEach { $0.invalidate() }
        observations = []
        let old = webView
        old.stopLoading()
        old.navigationDelegate = nil
        old.uiDelegate = nil
        old.removeFromSuperview()
        webView = WKWebView(frame: .zero, configuration: Self.closedConfiguration)
        session = nil
    }

    private static let closedConfiguration: WKWebViewConfiguration = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }()

    // MARK: Zoom

    static let zoomSteps: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    /// Page zoom (⌘+ / ⌘−), like Safari's: text and layout scale together.
    private(set) var zoom: CGFloat = 1

    func zoomIn() { setZoom(Self.zoomSteps.first { $0 > zoom + 0.001 } ?? zoom) }
    func zoomOut() { setZoom(Self.zoomSteps.last { $0 < zoom - 0.001 } ?? zoom) }
    func resetZoom() { setZoom(1) }

    /// A device preview sets its own zoom to fit the device in the column, so it
    /// isn't touched by the page zoom commands.
    func setZoom(_ value: CGFloat) {
        zoom = value
        webView.pageZoom = value
    }

    /// Asks the page whether a horizontal scroll at `point` (in web view coordinates)
    /// would move something, in the direction of `direction` (+1 right, -1 left).
    func canScrollHorizontally(at point: CGPoint, direction: Int) async -> Bool {
        let scale = webView.pageZoom * webView.magnification
        let js = "__wake.canScrollX(\(point.x / scale), \(point.y / scale), \(direction))"
        let result = try? await webView.evaluateJavaScript(js, in: nil, contentWorld: WebScripts.world)
        return result as? Bool ?? false
    }

    func receive(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "scroll":
            if let fraction = message["fraction"] as? Double { onScroll?(fraction) }
        case "openLink":
            guard let href = message["href"] as? String, let url = URL(string: href) else { return }
            onOpenLink?(url, message["background"] as? Bool ?? false)
        case "state":
            isPlayingMedia = message["playing"] as? Bool ?? false
            hasUnsavedInput = message["unsaved"] as? Bool ?? false
        case "popOutPick":
            isPickingPopOut = false
            guard let url, let selector = message["selector"] as? String else { return }
            let pick = PopOutPick(
                url: url,
                title: displayTitle,
                selector: selector,
                label: message["label"] as? String ?? "",
                rect: CGRect(x: message["x"] as? Double ?? 0, y: message["y"] as? Double ?? 0,
                             width: message["w"] as? Double ?? 320, height: message["h"] as? Double ?? 200),
                layoutWidth: message["layoutWidth"] as? Double ?? webView.bounds.width
            )
            PopOutController.shared.open(pick, near: webView.window)
        case "popOutCancel":
            isPickingPopOut = false
        case "live":
            if message["reset"] as? Bool == true {
                live = LiveState(media: live.media, httpStatus: live.httpStatus)
                return
            }
            var next = live
            next.merge(message)
            if next != live { live = next }
            if let price = live.price, let url { PriceWatch.shared.observe(price.amount, at: url) }
        default:
            break
        }
    }

    // MARK: Developer mode

    func receiveDeveloperMessage(_ body: Any) {
        guard isDeveloperMode || isInspectingComponents, let message = body as? [String: Any] else { return }
        switch message["type"] as? String {
        case "inspect":
            onInspect?(ComponentPick(
                framework: message["framework"] as? String,
                name: message["name"] as? String,
                file: message["file"] as? String,
                line: message["line"] as? Int,
                pageURL: url
            ))
        case "inspectEnd":
            isInspectingComponents = false
        default:
            devtools.receive(message)
        }
    }

    func receiveDevToolsMessage(_ body: Any) {
        guard let message = body as? [String: Any] else { return }
        session?.receive(message)
    }

    static func isLocal(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"].contains(host)
            || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".test")
    }

    /// Adds or removes the page-world hooks so the next document matches the mode.
    /// `applyNow` also installs them into the current document (without a reload).
    private func updateDeveloperMode(for url: URL?, applyNow: Bool = false) {
        guard !isDevTools else { return }
        let wanted = developerModeOverride ?? (DeveloperSettings.shared.autoEnableForLocalhost && Self.isLocal(url))
        guard wanted != isDeveloperMode else { return }
        isDeveloperMode = wanted
        let controller = webView.configuration.userContentController
        if wanted {
            controller.addUserScript(DevScripts.hooks)
            if applyNow { webView.evaluateJavaScript(DevScripts.hooksSource, in: nil, in: .page) { _ in } }
        } else {
            controller.removeAllUserScripts()
            controller.addUserScript(WebScripts.baseScript)
        }
    }

    func setMock(_ body: String?, for path: String) {
        devtools.setMock(body, for: path)
        pushMocks()
    }

    private func pushMocks() {
        guard isDeveloperMode else { return }
        webView.evaluateJavaScript(DevScripts.setMocks(devtools.mocks), in: nil, in: .page) { _ in }
    }

    func replay(_ entry: NetworkEntry) {
        webView.evaluateJavaScript(DevScripts.replay(entry), in: nil, in: .page) { _ in }
    }

    func setInspectingComponents(_ on: Bool) {
        isInspectingComponents = on
        let script = on ? DevOverlayScripts.inspector + "window.__wakeInspect.start();" : "window.__wakeInspect && window.__wakeInspect.stop();"
        webView.evaluateJavaScript(script, in: nil, in: .page) { _ in }
    }

    /// Starts or stops the Pop Out picker in this page.
    func setPickingPopOut(_ on: Bool) {
        isPickingPopOut = on
        let script = on ? PopOutScripts.picker(handler: WebScripts.handlerName) : PopOutScripts.stopPicker
        webView.evaluateJavaScript(script, in: nil, in: WebScripts.world) { _ in }
        // The picker listens for Esc and arrow keys in the page.
        if on { webView.window?.makeFirstResponder(webView) }
    }

    /// Linked responsive previews report and follow each other's scroll position.
    func setScrollSync(_ on: Bool) {
        webView.evaluateJavaScript("window.__wake && (window.__wake.syncScroll = \(on));", in: nil, in: WebScripts.world) { _ in }
    }

    func scroll(toFraction fraction: Double) {
        webView.evaluateJavaScript("window.__wake && window.__wake.scrollToFraction(\(fraction));", in: nil, in: WebScripts.world) { _ in }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    private func observeWebView() {
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated {
                    self?.title = view.title ?? ""
                    self?.onStateChange?()
                }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated {
                    self?.url = view.url
                    self?.onStateChange?()
                }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated {
                    // WebKit reports progress in tiny steps; each published change
                    // re-renders the loading line, so only steps of 2% or the ends count.
                    guard let self else { return }
                    let value = view.estimatedProgress
                    if abs(value - self.progress) >= 0.02 || value >= 1 || value < self.progress {
                        self.progress = value
                    }
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isLoading = view.isLoading }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isSecure = view.hasOnlySecureContent }
            },
        ]
    }

    fileprivate func resolveFavicon() async {
        let script = """
        (() => {
          const link = document.querySelector("link[rel~='icon'][sizes='32x32'], link[rel~='icon'], link[rel='apple-touch-icon']");
          return link ? link.href : new URL('/favicon.ico', location.href).href;
        })()
        """
        let href = try? await webView.evaluateJavaScript(script) as? String
        faviconURL = href.flatMap(URL.init(string:))
    }

    fileprivate func fail(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        // WebKit reports "Frame load interrupted" (102) when a navigation becomes a
        // download, and "Plug-in handled load" (204) when its media player shows a
        // video or audio file itself. Neither is a failure.
        guard !(nsError.domain == "WebKitErrorDomain" && [102, 204].contains(nsError.code)) else { return }
        failure = nsError.localizedDescription
    }
}

extension BrowserPage: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        preferences.allowsContentJavaScript = !isJavaScriptDisabled
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return (.allow, preferences) }
        if ["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            if interceptsAsColumn(action, url: url) { return (.cancel, preferences) }
            // Before the document loads, so developer hooks are in place from its start.
            if action.targetFrame?.isMainFrame != false { updateDeveloperMode(for: url) }
            return (.allow, preferences)
        }
        // mailto:, facetime:, app deep links… belong to other apps.
        NSWorkspace.shared.open(url)
        return (.cancel, preferences)
    }

    /// Backstop for link clicks the injected script didn't see (links in iframes that
    /// target the top frame, pages with JavaScript off). ⌥-click stays in place.
    private func interceptsAsColumn(_ action: WKNavigationAction, url: URL) -> Bool {
        guard action.navigationType == .linkActivated,
              action.targetFrame?.isMainFrame == true,
              !action.modifierFlags.contains(.option),
              !isSameDocument(url),
              let onOpenLink
        else { return false }
        onOpenLink(url, action.modifierFlags.contains(.command))
        return true
    }

    private func isSameDocument(_ url: URL) -> Bool {
        guard let current = webView.url else { return false }
        var a = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var b = URLComponents(url: current, resolvingAgainstBaseURL: false)
        a?.fragment = nil
        b?.fragment = nil
        return a == b
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failure = nil
        faviconURL = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if response.isForMainFrame {
            let type = response.response.mimeType?.lowercased() ?? ""
            isJSONDocument = type.contains("json")
            pendingHTTPStatus = (response.response as? HTTPURLResponse)?.statusCode
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // A new document: whatever the old one was playing or holding is gone.
        isPlayingMedia = false
        hasUnsavedInput = false
        isInspectingComponents = false
        isPickingPopOut = false
        live = LiveState(httpStatus: pendingHTTPStatus)
        pendingHTTPStatus = nil
        devtools.reset()
        session?.documentChanged()
        pushMocks()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isJSONDocument {
            webView.evaluateJavaScript(DevOverlayScripts.jsonViewer, in: nil, in: WebScripts.world) { _ in }
        }
        if syncsScroll { setScrollSync(true) }
        if let y = pendingScrollY {
            pendingScrollY = nil
            if y > 0 {
                // Pages that build themselves after the load event get a second try.
                let script = "window.scrollTo(0, \(y))"
                webView.evaluateJavaScript(script) { _, _ in }
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(600))
                    guard let self, abs((await self.scrollY() ?? y) - y) > 4 else { return }
                    _ = try? await self.webView.evaluateJavaScript(script)
                }
            }
        }
        if let restore = pendingRestore {
            pendingRestore = nil
            Task {
                await applyRestore(restore)
                onRestored?(self)
                onRestored = nil
            }
        }
        Task { await resolveFavicon() }
        session?.documentFinished()
        onDidFinish?(self)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

extension BrowserPage: WKUIDelegate {
    /// `target=_blank` and `window.open` become a new column. WebKit loads the request
    /// into the returned web view itself.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard action.targetFrame == nil else { return nil }
        return onOpenPopup?(configuration)
    }

    func webViewDidClose(_ webView: WKWebView) {
        onClose?()
    }
}
