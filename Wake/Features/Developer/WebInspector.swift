import AppKit
import WebKit

/// WebKit's own Web Inspector, the one Safari uses: Elements with the styles
/// editor, Console, Sources with the debugger and breakpoints, Network, Timelines,
/// Storage, Graphics, Layers and Audit.
///
/// Limitation: WebKit has no public API to open it from an app. `isInspectable` only
/// lists the page under Safari ▸ Develop. Opening it in Wake uses WebKit SPI that
/// Safari itself relies on: the `developerExtrasEnabled` preference (which also adds
/// "Inspect Element" to the page's context menu) and `WKWebView._inspector`
/// (`_WKInspector`: show, close, attach, detach, showConsole, toggleElementSelection).
/// Both have been stable since macOS 10.14, but they're private, so every call is
/// checked with `responds(to:)` and Wake falls back to explaining Safari ▸ Develop.
/// An app using them can't ship on the Mac App Store.
@MainActor
enum WebInspector {
    /// Turns on the Web Inspector backend for pages made with this configuration.
    static func enable(in preferences: WKPreferences) {
        let setter = NSSelectorFromString("_setDeveloperExtrasEnabled:")
        guard preferences.responds(to: setter) else { return }
        preferences.setValue(true, forKey: "developerExtrasEnabled")
    }

    static func isAvailable(for webView: WKWebView) -> Bool {
        inspector(of: webView)?.responds(to: NSSelectorFromString("show")) == true
    }

    static func isVisible(for webView: WKWebView) -> Bool {
        guard let inspector = inspector(of: webView), inspector.responds(to: NSSelectorFromString("isVisible")) else { return false }
        return inspector.value(forKey: "visible") as? Bool ?? false
    }

    enum Panel { case elements, console, pickElement }

    /// Opens the inspector for `webView` on `panel`.
    @discardableResult
    static func show(for webView: WKWebView, panel: Panel = .elements) -> Bool {
        enable(in: webView.configuration.preferences)
        guard let inspector = inspector(of: webView) else { return false }
        // Docked, WebKit puts it in the web view's own container, so it stays
        // inside the page's column card; its dock buttons undock it into a window,
        // and WebKit remembers the choice.
        guard send("show", to: inspector) else { return false }
        switch panel {
        case .elements: break
        case .console: send("showConsole", to: inspector)
        case .pickElement: send("toggleElementSelection", to: inspector)
        }
        return true
    }

    static func close(for webView: WKWebView) {
        guard let inspector = inspector(of: webView) else { return }
        send("close", to: inspector)
    }

    static func toggle(for webView: WKWebView) {
        if isVisible(for: webView) { close(for: webView) } else { show(for: webView) }
    }

    private static func inspector(of webView: WKWebView) -> NSObject? {
        guard webView.responds(to: NSSelectorFromString("_inspector")) else { return nil }
        return webView.value(forKey: "_inspector") as? NSObject
    }

    @discardableResult
    private static func send(_ selector: String, to object: NSObject) -> Bool {
        let selector = NSSelectorFromString(selector)
        guard object.responds(to: selector) else { return false }
        object.perform(selector)
        return true
    }
}
