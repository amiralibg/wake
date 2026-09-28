import WebKit

/// The page-side half of Wake's DevTools (`shared/scripts/devtools.js`): DOM tree,
/// element details and highlight, the element picker, storage, performance metrics,
/// audits, resource timing and console evaluation.
///
/// It runs in the page's own world (`.page`) so the console sees the page's globals
/// and `$0` is the element selected in Elements. Nothing is injected until a DevTools
/// pane asks for it: every call carries the installer, which returns at once when
/// `__wakeDT` is already there (a new document simply gets it again).
@MainActor
enum DevToolsScripts {
    static let handlerName = "wakeDT"

    /// Wraps `expression` so the library is installed before it runs.
    static func call(_ expression: String) -> String {
        "(() => { \(library) return (\(expression)); })()"
    }

    /// For `callAsyncJavaScript`: installs the library, then runs `script` with the
    /// call's `params` argument.
    static func asyncBody(_ script: SharedScript) -> String {
        "\(library)\n\(script.asyncBody)"
    }

    /// `text` as a JavaScript string literal.
    static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    private static var library: String { SharedScript.devTools.source(["channel": handlerName]) }

    /// Evaluates console input (`params.code`) in the page. Declarations stay global
    /// (indirect eval), promises are awaited, and `await` works at the top level.
    static var evaluate: String { asyncBody(.devToolsEvaluate) }

    /// Suggestions for the console prompt: properties of the object before the last dot.
    static var completions: String { asyncBody(.devToolsCompletions) }

    /// Storage the page can list only asynchronously.
    static var asyncStorage: String { asyncBody(.devToolsStorage) }

    /// "deleted", "blocked" (the page still has it open; the delete waits), or "error".
    static var deleteDatabase: String { asyncBody(.devToolsDeleteDatabase) }

    static var deleteCache: String { asyncBody(.devToolsDeleteCache) }

    static var unregisterWorker: String { asyncBody(.devToolsUnregisterWorker) }

    /// Fetches a script or stylesheet with the page's cookies. Runs in Wake's isolated
    /// world, whose `fetch` isn't the one developer mode wraps, so DevTools' own
    /// requests don't show up in Network.
    static var fetchSource: String { SharedScript.fetchSource.asyncBody }
}
