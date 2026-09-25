import WebKit

extension WKWebViewConfiguration {
    @MainActor
    static func wake() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // WKWebView's default UA has no "Version/… Safari/…" suffix, and many sites
        // (Google, YouTube) then serve degraded pages. Present as the matching Safari.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        WebScripts.install(in: configuration.userContentController)
        return configuration
    }
}
