// Runs every shared page script in a real WKWebView, the way the Mac app wraps them
// (through `SharedScript`), and checks what each one posts or returns.
// Usage: Scripts/script-tests/run.sh
import AppKit
import WebKit

final class Recorder: NSObject, WKScriptMessageHandler {
    var messages: [(channel: String, body: [String: Any])] = []

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        messages.append((message.name, message.body as? [String: Any] ?? [:]))
    }

    func first(_ channel: String, _ type: String, where test: ([String: Any]) -> Bool = { _ in true }) -> [String: Any]? {
        messages.first { $0.channel == channel && $0.body["type"] as? String == type && test($0.body) }?.body
    }
}

final class Loader: NSObject, WKNavigationDelegate {
    var done = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
}

@MainActor
func spin(until condition: () -> Bool, timeout: TimeInterval = 6) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    return condition()
}

@MainActor
func eval(_ view: WKWebView, _ js: String, world: WKContentWorld? = nil) -> Any? {
    let world = world ?? .defaultClient
    var result: Any?, finished = false
    view.evaluateJavaScript(js, in: nil, in: world) { outcome in
        if case .success(let value) = outcome { result = value } else if case .failure(let error) = outcome { result = "ERROR: \(error)" }
        finished = true
    }
    _ = spin(until: { finished })
    return result
}

@MainActor
func callAsync(_ view: WKWebView, _ body: String, _ params: [String: Any], world: WKContentWorld? = nil) -> Any? {
    let world = world ?? .page
    var result: Any?, finished = false
    view.callAsyncJavaScript(body, arguments: ["params": params], in: nil, in: world) { outcome in
        if case .success(let value) = outcome { result = value } else if case .failure(let error) = outcome { result = "ERROR: \(error)" }
        finished = true
    }
    _ = spin(until: { finished })
    return result
}

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> Any = "") {
    print(ok ? "  ok    \(name)" : "  FAIL  \(name)  \(detail())")
    if !ok { failures += 1 }
}

let page = """
<!doctype html><html lang="en"><head><title>Script test</title>
<link rel="icon" href="/icon-32.png" sizes="32x32">
<script type="application/ld+json">{"@type":"Product","offers":{"price":"19.99","priceCurrency":"EUR"}}</script>
</head><body style="margin:0">
<a id="link" href="/other?x=1">Other</a>
<a id="hash" href="#top">Top</a>
<form><input id="field"></form>
<section id="card" style="width:300px;height:200px;background:#eee"><h2>Card title</h2><p>Some words to find again later in this card.</p></section>
<p id="para">The quick brown fox jumps over the lazy dog. The quick brown fox again.</p>
<div style="height:3000px"></div>
</body></html>
"""

@MainActor
func run() {
    let recorder = Recorder()
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let controller = configuration.userContentController
    let base: [SharedScript] = [.linkInterceptor, .scrollProbe, .pageState, .scrollSync, .live]
    controller.addUserScript(WKUserScript(source: base.map { $0.source(["channel": "wake"]) }.joined(separator: "\n"),
                                          injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
    controller.addUserScript(WKUserScript(source: SharedScript.devHooks.source(["channel": "wakeDev"]),
                                          injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
    controller.add(recorder, contentWorld: .defaultClient, name: "wake")
    controller.add(recorder, contentWorld: .defaultClient, name: "wakePopOut")
    controller.add(recorder, contentWorld: .page, name: "wakeDev")
    controller.add(recorder, contentWorld: .page, name: "wakeDT")

    // On screen (but out of the way), so timers and requestAnimationFrame aren't throttled.
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
    let view = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
    window.contentView = view
    window.orderFrontRegardless()
    let loader = Loader()
    view.navigationDelegate = loader
    view.loadHTMLString(page, baseURL: URL(string: "https://example.test/start")!)
    guard spin(until: { loader.done }) else { print("page didn't load"); exit(1) }

    print("Wake world")
    _ = eval(view, "document.getElementById('link').click()", world: .page)
    let link = recorder.first("wake", "openLink")
    check("link-interceptor opens links in a column", link?["href"] as? String == "https://example.test/other?x=1", link as Any)
    _ = eval(view, "document.getElementById('hash').click()", world: .page)
    check("link-interceptor leaves #hash links alone", recorder.messages.filter { $0.body["type"] as? String == "openLink" }.count == 1)

    check("scroll-probe answers canScrollX", eval(view, "__wake.canScrollX(10, 10, 1)") as? Bool == false)

    _ = eval(view, "{ const f = document.getElementById('field'); f.value = 'x'; f.dispatchEvent(new Event('input', { bubbles: true })) }", world: .page)
    let state = recorder.first("wake", "state")
    check("page-state reports unsaved input", state?["unsaved"] as? Bool == true, state as Any)

    _ = eval(view, "__wake.syncScroll = true")
    _ = eval(view, "window.scrollTo(0, 500)", world: .page)
    if eval(view, "document.visibilityState") as? String == "visible" {
        check("scroll-sync reports a fraction", spin(until: { recorder.first("wake", "scroll") != nil }), recorder.messages.map(\.body))
    } else {
        // WebKit pauses requestAnimationFrame while the window isn't visible (a test
        // run from a terminal that stays in front), and scroll-sync reports from one.
        print("  skip  scroll-sync reports a fraction (the page isn't visible, so requestAnimationFrame doesn't run)")
    }
    _ = eval(view, "__wake.scrollToFraction(0)")
    check("scroll-sync scrolls to a fraction", (eval(view, "window.scrollY") as? Double) == 0)

    let gotPrice = spin(until: { recorder.first("wake", "live", where: { $0["price"] != nil }) != nil }, timeout: 4)
    let price = recorder.first("wake", "live", where: { $0["price"] != nil })?["price"] as? [String: Any]
    check("live finds the JSON-LD price", gotPrice && price?["amount"] as? Double == 19.99 && price?["currency"] as? String == "EUR", price as Any)

    let favicon = eval(view, SharedScript.favicon.source()) as? String
    check("favicon picks the 32 px icon", favicon == "https://example.test/icon-32.png", favicon as Any)

    _ = eval(view, """
        { const t = document.getElementById('para').firstChild;
        const r = document.createRange(); r.setStart(t, 45); r.setEnd(t, 60);
        getSelection().removeAllRanges(); getSelection().addRange(r); }
        """, world: .page)
    let captured = eval(view, SharedScript.momentCapture.source(["maxText": 40_000])) as? [String: Any]
    check("moment-capture reads the selection and prefix",
          captured?["selection"] as? String == "The quick brown" && (captured?["prefix"] as? String ?? "").hasSuffix("lazy dog. "), captured as Any)
    check("moment-capture reads the text", (captured?["text"] as? String ?? "").contains("Card title"))
    check("visible-text honours maxText", (eval(view, SharedScript.visibleText.source(["maxText": 5])) as? String)?.count == 5)

    let restored = eval(view, SharedScript.momentRestore.source(["key": "The quick brown", "prefix": "over the lazy dog. ", "scrollY": 0, "scrollFraction": 0])) as? Bool
    check("moment-restore finds the second match", restored == true, restored as Any)
    let highlighted = eval(view, "CSS.highlights.get('wake-moment') ? [...CSS.highlights.get('wake-moment')][0].startOffset : -1") as? Int
    check("moment-restore highlights it", highlighted == 45, highlighted as Any)
    check("moment-restore reports a missing selection", eval(view, SharedScript.momentRestore.source(["key": "not on this page", "prefix": "", "scrollY": 0, "scrollFraction": 0])) as? Bool == false)

    _ = eval(view, SharedScript.popOutPicker.source(["channel": "wake"]))
    _ = eval(view, """
        { const r = document.getElementById('card').getBoundingClientRect();
        const at = { clientX: r.left + 20, clientY: r.top + 20, bubbles: true };
        window.dispatchEvent(new MouseEvent('mousemove', at));
        document.getElementById('card').dispatchEvent(new MouseEvent('click', at)); }
        """, world: .page)
    let pick = recorder.first("wake", "popOutPick")
    check("popout-picker picks an element", pick?["selector"] as? String == "#card > h2" && pick?["w"] as? Double == 300, pick as Any)
    check("popout-picker stops after a pick", eval(view, "window.__wakePick === undefined") as? Bool == true)

    _ = eval(view, SharedScript.popOutIsolate.source(["channel": "wakePopOut", "selector": "#card"]))
    check("popout-isolate finds the element", spin(until: { recorder.first("wakePopOut", "found") != nil }))
    let rect = recorder.first("wakePopOut", "rect")
    check("popout-isolate reports its size", rect?["h"] as? Double == 200, rect as Any)

    print("Page world")
    _ = eval(view, "console.log('hello', { a: 1 })", world: .page)
    let log = recorder.first("wakeDev", "console", where: { ($0["message"] as? String ?? "").hasPrefix("hello") })
    check("dev-hooks forward console.log", log?["message"] as? String == "hello {\"a\":1}", log as Any)
    _ = eval(view, "console.count('n'); console.count('n')", world: .page)
    check("dev-hooks count", recorder.first("wakeDev", "console", where: { $0["message"] as? String == "n: 2" }) != nil)
    _ = eval(view, "window.__wakeDev.mocks = { '/api': '{\"ok\":true}' }", world: .page)
    let mocked = callAsync(view, "return await (await fetch('/api')).text()", [:])
    check("dev-hooks serve mocks", mocked as? String == "{\"ok\":true}", mocked as Any)
    check("dev-hooks report the request", recorder.first("wakeDev", "response", where: { $0["mocked"] as? Bool == true }) != nil)

    _ = eval(view, SharedScript.componentInspector.source(["channel": "wakeDev"]) + "window.__wakeInspect.start();", world: .page)
    check("component-inspector starts", eval(view, "document.documentElement.style.cursor", world: .page) as? String == "crosshair")
    _ = eval(view, "window.__wakeInspect.stop()", world: .page)
    check("component-inspector restores the cursor", eval(view, "document.documentElement.style.cursor", world: .page) as? String == "")

    let library = SharedScript.devTools.source(["channel": "wakeDT"])
    let call = { (expression: String) in eval(view, "(() => { \(library) return (\(expression)); })()", world: .page) }
    let tree = call("__wakeDT.document()") as? [String: Any]
    check("devtools lists the document", (tree?["nodes"] as? [Any])?.isEmpty == false, tree as Any)
    let found = call("__wakeDT.search('#card')") as? [[String: Any]]
    check("devtools searches", found?.count == 1, found as Any)
    let asyncBody = { (script: SharedScript) in "\(library)\n\(script.asyncBody)" }
    let evaluated = callAsync(view, asyncBody(.devToolsEvaluate), ["code": "await Promise.resolve(40 + 2)"]) as? [String: Any]
    check("devtools console evaluates with await", evaluated?["text"] as? String == "42", evaluated as Any)
    let global = callAsync(view, asyncBody(.devToolsEvaluate), ["code": "var wakeTestGlobal = 7"]) as? [String: Any]
    check("devtools console declarations stay global", global?["ok"] as? Bool == true && eval(view, "window.wakeTestGlobal", world: .page) as? Int == 7)
    let completions = callAsync(view, asyncBody(.devToolsCompletions), ["code": "document.bo"]) as? [String]
    check("devtools completes properties", completions?.contains("body") == true, completions as Any)
    let storage = callAsync(view, asyncBody(.devToolsStorage), [:]) as? [String: Any]
    check("devtools lists async storage", storage?["databases"] != nil, storage as Any)
    let deleted = callAsync(view, asyncBody(.devToolsDeleteDatabase), ["name": "none"]) as? String
    check("devtools deletes a database", deleted == "deleted", deleted as Any)

    let written = callAsync(view, SharedScript.localStorageWrite.asyncBody, ["items": [["k", "v"], ["k2", "v2"]]], world: .defaultClient)
    check("local-storage-write writes new items", written as? Int == 2, written as Any)

    let json = Loader()
    view.navigationDelegate = json
    view.loadHTMLString("<html><head></head><body>{\"a\":[1,2],\"b\":\"https://x.test\"}</body></html>", baseURL: URL(string: "https://example.test/data.json")!)
    _ = spin(until: { json.done })
    check("json-viewer formats JSON", eval(view, SharedScript.jsonViewer.source()) as? Bool == true)
    check("json-viewer builds a tree", (eval(view, "document.querySelectorAll('details').length", world: .page) as? Int ?? 0) >= 2)

    let errors = recorder.messages.filter { $0.channel == "wakeDev" && $0.body["level"] as? String == "error" }
    check("no script errors reached the page", errors.isEmpty, errors.map(\.body))

    print(failures == 0 ? "All script tests passed." : "\(failures) failed.")
    exit(failures == 0 ? 0 : 1)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    run()
}
