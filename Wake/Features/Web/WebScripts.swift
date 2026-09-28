import WebKit

/// JavaScript Wake injects into pages. Runs in `WKContentWorld.defaultClient`, isolated
/// from the page's own scripts: pages can't read or overwrite `__wake`, but it still
/// sees the DOM and its events.
@MainActor
enum WebScripts {
    static let world = WKContentWorld.defaultClient
    static let handlerName = "wake"

    static func install(in controller: WKUserContentController) {
        controller.addUserScript(baseScript)
        controller.add(PageScriptBridge(), contentWorld: world, name: handlerName)
        // Developer-mode hooks run in the page world and report here. The handler is
        // always registered; the hooks themselves are only added in developer mode.
        controller.add(PageScriptBridge(route: .developer), contentWorld: .page, name: DevScripts.handlerName)
        // Wake's DevTools column (element picker) reports here.
        controller.add(PageScriptBridge(route: .devTools), contentWorld: .page, name: DevToolsScripts.handlerName)
    }

    /// Link interception, the scroll probe, page state, scroll sync and live-chip
    /// reporters, in Wake's world.
    static var baseScript: WKUserScript {
        let scripts: [SharedScript] = [.linkInterceptor, .scrollProbe, .pageState, .scrollSync, .live]
        return WKUserScript(
            source: scripts.map { $0.source(["channel": handlerName]) }.joined(separator: "\n"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: world
        )
    }
}

/// Routes script messages to the page that sent them. Stateless, so sharing one
/// user-content controller between an opener and its popup is fine.
private final class PageScriptBridge: NSObject, WKScriptMessageHandler {
    enum Route { case page, developer, devTools }

    let route: Route

    init(route: Route = .page) {
        self.route = route
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let page = message.webView?.navigationDelegate as? BrowserPage else { return }
            switch route {
            case .page: page.receive(message.body)
            case .developer: page.receiveDeveloperMessage(message.body)
            case .devTools: page.receiveDevToolsMessage(message.body)
            }
        }
    }
}
