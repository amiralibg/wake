import Foundation

/// A page script from `shared/scripts`, which the Windows and Linux apps use too.
///
/// Each file is the body of a function of `(wake, params)`: `wake.post(channel,
/// message)` reaches the host and `params` holds the values the host fills in, so no
/// Swift value is ever spliced into JavaScript source. See `shared/scripts/README.md`.
enum SharedScript: String, CaseIterable {
    case linkInterceptor = "link-interceptor"
    case scrollProbe = "scroll-probe"
    case pageState = "page-state"
    case scrollSync = "scroll-sync"
    case live
    case momentCapture = "moment-capture"
    case momentRestore = "moment-restore"
    case visibleText = "visible-text"
    case favicon
    case popOutPicker = "popout-picker"
    case popOutIsolate = "popout-isolate"
    case devHooks = "dev-hooks"
    case componentInspector = "component-inspector"
    case jsonViewer = "json-viewer"
    case devTools = "devtools"
    case devToolsEvaluate = "async-devtools-evaluate"
    case devToolsCompletions = "async-devtools-completions"
    case devToolsStorage = "async-devtools-storage"
    case devToolsDeleteDatabase = "async-devtools-delete-database"
    case devToolsDeleteCache = "async-devtools-delete-cache"
    case devToolsUnregisterWorker = "async-devtools-unregister-worker"
    case fetchSource = "async-fetch-source"
    case localStorageWrite = "async-local-storage-write"

    /// A statement that runs the script; evaluated, its value is what the body returns.
    func source(_ params: [String: Any] = [:]) -> String {
        "(function (wake, params) {\n\(body)\n})(\(Self.bridge), \(Self.json(params)));"
    }

    /// A function body for `callAsyncJavaScript`, which must be given the parameters
    /// as its `params` argument (`arguments: ["params": …]`).
    var asyncBody: String {
        "return await (async function (wake, params) {\n\(body)\n})(\(Self.bridge), params);"
    }

    var body: String {
        guard let body = Self.bodies[rawValue] else {
            preconditionFailure("shared/scripts/\(rawValue).js is missing from the app bundle")
        }
        return body
    }

    /// `bridge.js`, called: an expression for the bridge object.
    private static let bridge = "(function () {\n\(load("bridge"))\n})()"

    private static let bodies: [String: String] = Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, load($0.rawValue)) })

    private static func load(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "scripts"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { preconditionFailure("shared/scripts/\(name).js is missing from the app bundle") }
        return text
    }

    private static func json(_ params: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: params) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
