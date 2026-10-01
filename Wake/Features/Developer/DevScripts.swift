import WebKit

/// JavaScript for developer mode.
///
/// The hooks must run in the page's own world (`.page`), because they wrap the page's
/// `console`, `fetch`, `XMLHttpRequest` and `WebSocket`; an isolated world has its own
/// copies of those. They're only added to pages in developer mode.
@MainActor
enum DevScripts {
    static let handlerName = "wakeDev"

    static var hooks: WKUserScript {
        WKUserScript(source: hooksSource, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page)
    }

    /// Console, errors, fetch/XHR (with mocking) and HMR sockets, reported to Wake
    /// (`shared/scripts/dev-hooks.js`).
    static var hooksSource: String { SharedScript.devHooks.source(["channel": handlerName]) }

    /// Pushes the mocked routes into the page.
    static func setMocks(_ mocks: [String: String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: mocks)) ?? Data("{}".utf8)
        return "window.__wakeDev && (window.__wakeDev.mocks = \(String(decoding: data, as: UTF8.self)));"
    }

    /// Re-sends a captured request from the page, so cookies and origin match.
    static func replay(_ entry: NetworkEntry) -> String {
        var options: [String: Any] = ["method": entry.method, "headers": entry.requestHeaders]
        if let body = entry.requestBody { options["body"] = body }
        let optionsJSON = String(decoding: (try? JSONSerialization.data(withJSONObject: options)) ?? Data("{}".utf8), as: UTF8.self)
        let url = String(decoding: (try? JSONSerialization.data(withJSONObject: [entry.url.absoluteString])) ?? Data("[]".utf8), as: UTF8.self)
        return "fetch(\(url)[0], \(optionsJSON)).catch(() => {});"
    }
}
