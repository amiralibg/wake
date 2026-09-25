import Foundation
import WebKit

/// Looks at saved pages again in the background and marks the ones that changed.
///
/// Each check loads the page in an off-screen web view (with your cookies, so it
/// sees what you'd see), reads its visible text once it settles, and compares it
/// with the text saved with the moment. One page at a time, each at most every
/// 12 hours.
///
/// Limitation: checks only run while Wake is open. Checking with Wake closed would
/// need a separate login-item helper, which a sandboxed app can't add silently.
@MainActor
final class MomentWatcher: NSObject {
    static let shared = MomentWatcher()

    private let recheckAfter: TimeInterval = 12 * 3600
    private var loop: Task<Void, Never>?
    private var webView: WKWebView?
    private var finished: CheckedContinuation<Bool, Never>?
    /// Tells one load's timeout from the next load's.
    private var loadID = 0

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            // Let launch and the first window settle before doing background work.
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                await self?.runPass()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    private func runPass() async {
        let store = MomentStore.shared
        store.archiveStale()
        let now = Date.now
        let due = store.moments().filter { moment in
            moment.url.scheme?.hasPrefix("http") == true
                && moment.changedAt == nil
                && now.timeIntervalSince(moment.lastCheckedAt ?? .distantPast) >= recheckAfter
        }
        for moment in due.prefix(12) {
            guard !Task.isCancelled else { return }
            await check(moment)
        }
        webView = nil
    }

    private func check(_ moment: MomentRecord) async {
        guard let text = await load(moment.url), !text.isEmpty else { return }
        let store = MomentStore.shared
        let summary = MomentDiff.hash(text) == moment.contentHash ? nil : MomentDiff.summary(old: moment.contentText, new: text)
        store.update(moment) { moment in
            moment.lastCheckedAt = .now
            if let summary {
                moment.changedAt = .now
                moment.changeSummary = summary
            }
        }
    }

    /// Loads `url` off screen and returns its visible text, or `nil` if it failed.
    private func load(_ url: URL) async -> String? {
        let view = webView ?? makeWebView()
        webView = view
        loadID += 1
        let id = loadID
        let loaded = await withCheckedContinuation { continuation in
            finished = continuation
            view.load(URLRequest(url: url, timeoutInterval: 20))
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(25))
                guard let self, self.loadID == id else { return }
                self.finish(false)
            }
        }
        guard loaded else {
            view.stopLoading()
            return nil
        }
        // Script-rendered pages fill in after the load event.
        try? await Task.sleep(for: .seconds(2))
        let text = try? await view.evaluateJavaScript(MomentScripts.visibleText)
        return text as? String
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration)
        view.navigationDelegate = self
        return view
    }

    private func finish(_ success: Bool) {
        finished?.resume(returning: success)
        finished = nil
    }
}

extension MomentWatcher: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }
}
