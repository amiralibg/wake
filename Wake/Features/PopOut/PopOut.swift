import AppKit
import Observation
import SwiftUI
import WebKit

/// What the picker chose: where the element is and how the page was laid out.
struct PopOutPick {
    let url: URL
    let title: String
    let selector: String
    /// The element's own name (alt text, label, heading), or empty.
    let label: String
    /// Document coordinates, CSS pixels.
    let rect: CGRect
    /// The page's layout width when picked, so the copy lays out the same way.
    let layoutWidth: CGFloat
}

/// One popped-out element: its own live copy of the page, clipped to the element.
///
/// The copy runs separately from the column it came from (it has your cookies, so
/// it shows the same thing), and lays out at the source page's width so the element
/// keeps its size. Only the element's box is visible; links open in the trail.
///
/// Limitation: WebKit can't render one DOM element of a page in another view, so
/// the element lives in a second copy of the page. State that exists only in the
/// original tab (an unsent form, a scrolled carousel) isn't carried over.
@MainActor
@Observable
final class PopOut: NSObject, Identifiable {
    enum State { case loading, live, lost }

    let id = UUID()
    let pick: PopOutPick
    private(set) var state: State = .loading
    /// The element's current box (x in document coordinates, CSS pixels).
    private(set) var rect: CGRect
    var isPinned = false {
        didSet { onPinChange(isPinned) }
    }
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored var onPinChange: (Bool) -> Void = { _ in }
    @ObservationIgnored var onSizeChange: (CGSize) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}

    static let headerHeight: CGFloat = 34
    private static let handler = "wakePopOut"
    private static let maxSize = CGSize(width: 760, height: 620)

    init(pick: PopOutPick) {
        self.pick = pick
        rect = pick.rect
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(
            source: PopOutScripts.isolate(selector: pick.selector, handler: Self.handler),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        controller.add(PopOutBridge(owner: self), contentWorld: .defaultClient, name: Self.handler)
        webView.navigationDelegate = self
        webView.isInspectable = true
        webView.load(URLRequest(url: pick.url))
    }

    var host: String {
        let host = pick.url.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Big elements are shown smaller (page zoom keeps their layout).
    var scale: CGFloat {
        guard rect.width > 0, rect.height > 0 else { return 1 }
        return max(0.3, min(1, Self.maxSize.width / rect.width, Self.maxSize.height / rect.height))
    }

    /// The element's box on screen.
    var contentSize: CGSize {
        CGSize(width: max(1, rect.width * scale), height: max(1, rect.height * scale))
    }

    /// Room for the header too; never narrower than the header needs.
    var panelSize: CGSize {
        CGSize(width: max(280, contentSize.width), height: contentSize.height + Self.headerHeight)
    }

    func reload() {
        state = .loading
        webView.reload()
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any] else { return }
        switch message["type"] as? String {
        case "found":
            state = .live
        case "lost":
            state = .lost
        case "rect":
            let next = CGRect(
                x: message["x"] as? Double ?? rect.minX,
                y: rect.minY,
                width: message["w"] as? Double ?? rect.width,
                height: message["h"] as? Double ?? rect.height
            )
            guard next.width >= 1, next.height >= 1, next != rect else { return }
            rect = next
            onSizeChange(panelSize)
        default:
            break
        }
    }
}

extension PopOut: WKNavigationDelegate {
    /// The popped-out copy stays on its page: clicked links open in the trail.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
        NSApp.activate()
        if let browser = BrowserModel.active {
            browser.trail.open(url)
            browser.window?.makeKeyAndOrderFront(nil)
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        state = .lost
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        state = .lost
    }
}

/// Weak hop from the content controller (which retains its handlers) to the pop-out.
private final class PopOutBridge: NSObject, WKScriptMessageHandler {
    weak var owner: PopOut?

    init(owner: PopOut) {
        self.owner = owner
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { owner?.receive(message.body) }
    }
}

/// Keeps every pop-out's panel alive, app-wide.
@MainActor
final class PopOutController {
    static let shared = PopOutController()

    private var panels: [UUID: PopOutPanel] = [:]

    func open(_ pick: PopOutPick, near window: NSWindow?) {
        let popOut = PopOut(pick: pick)
        let panel = PopOutPanel(popOut: popOut)
        // Weak all round: the pop-out owns this closure, so capturing it would keep
        // every closed pop-out (and its web view's WebContent process) alive.
        popOut.onClose = { [weak self, weak panel, id = popOut.id] in
            panel?.popOut.webView.stopLoading()
            panel?.close()
            self?.panels[id] = nil
        }
        panels[popOut.id] = panel
        // Beside the window's top-right corner, cascading if there are several.
        let anchor = window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        let offset = CGFloat(panels.count - 1) * 24
        panel.setFrameTopLeftPoint(NSPoint(x: anchor.maxX - panel.frame.width - 24 - offset, y: anchor.maxY - 80 - offset))
        panel.orderFrontRegardless()
    }
}

/// A floating glass panel that doesn't take focus from the app you're in. It stays
/// above other windows, also when Wake is in the background; pinned, it follows you
/// to every Space and over full-screen apps.
final class PopOutPanel: NSPanel {
    let popOut: PopOut

    init(popOut: PopOut) {
        self.popOut = popOut
        let size = popOut.panelSize
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary]
        contentView = NSHostingView(rootView: PopOutView(popOut: popOut))
        popOut.onSizeChange = { [weak self] size in self?.resize(to: size) }
        popOut.onPinChange = { [weak self] pinned in
            self?.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
        }
    }

    /// Typing into the popped-out element (a search box, a chat) needs key status.
    override var canBecomeKey: Bool { true }

    /// Grows and shrinks with the element, keeping the top-left corner in place.
    private func resize(to size: CGSize) {
        var frame = self.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        setFrame(frame, display: true, animate: false)
    }
}
