import AppKit
import Observation
import WebKit

/// Everything Wake's DevTools column knows about one inspected page beyond the
/// developer-mode log: the DOM tree and selection, resource timing, storage,
/// performance and audits, and the page overrides from the Tools menu. Made the
/// first time a DevTools pane asks for it, then kept for the page's lifetime.
@MainActor
@Observable
final class DevToolsSession {
    enum Tab: String, CaseIterable, Identifiable {
        case elements, console, network, sources, storage, performance

        var id: Self { self }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .elements: "chevron.left.forwardslash.chevron.right"
            case .console: "terminal"
            case .network: "network"
            case .sources: "doc.text"
            case .storage: "cylinder.split.1x2"
            case .performance: "gauge.with.dots.needle.67percent"
            }
        }
    }

    @ObservationIgnored private weak var page: BrowserPage?
    var tab: Tab = .console

    init(page: BrowserPage) {
        self.page = page
    }

    // MARK: Evaluation

    private var webView: WKWebView? { page?.webView }

    /// Runs `expression` against `__wakeDT` in the page world.
    @discardableResult
    func run(_ expression: String) async -> Any? {
        guard let webView else { return nil }
        let result = try? await webView.evaluateJavaScript(DevToolsScripts.call(expression), in: nil, contentWorld: .page)
        return result is NSNull ? nil : result
    }

    @discardableResult
    func runAsync(_ body: String, arguments: [String: Any] = [:], world: WKContentWorld = .page) async -> Any? {
        guard let webView else { return nil }
        let result = try? await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: world)
        return result is NSNull ? nil : result
    }

    /// Bumps each time a document finishes loading. Panes key their loading on it
    /// rather than the URL, which a reload leaves unchanged.
    private(set) var documentLoads = 0

    func documentFinished() {
        documentLoads += 1
    }

    /// A new document: node ids and timings belong to the old one.
    func documentChanged() {
        roots = []
        children = [:]
        expanded = []
        selectedID = nil
        details = nil
        hoveredID = nil
        isPicking = false
        resources = []
        resourceCursor = 0
        metrics = nil
        audits = []
        fpsSamples = []
        localItems = []
        sessionItems = []
        asyncStorage = .init()
        blockedDatabase = nil
        sources = []
        stylesDisabled = false
        outlinesShown = false
        designMode = false
        treeVersion += 1
    }

    func receive(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "picked":
            isPicking = false
            setWakePickFlag(false)
            guard let id = message["id"] as? Int else { return }
            let path = (message["path"] as? [Any])?.compactMap { $0 as? Int } ?? []
            Task { await reveal(id, path: path) }
            tab = .elements
        case "pickEnd":
            isPicking = false
            setWakePickFlag(false)
        default:
            break
        }
    }

    // MARK: Elements

    struct DOMNode: Identifiable, Hashable {
        let id: Int
        let type: Int
        let tag: String?
        let attributes: [Attribute]
        let text: String?
        let childCount: Int

        struct Attribute: Hashable {
            let name: String
            let value: String
        }

        var isElement: Bool { type == 1 }
        var isExpandable: Bool { childCount > 0 }

        init?(_ any: Any) {
            guard let object = any as? [String: Any], let id = object["id"] as? Int else { return nil }
            self.id = id
            type = object["type"] as? Int ?? 1
            tag = object["tag"] as? String
            attributes = (object["attrs"] as? [[Any]] ?? []).compactMap { pair in
                guard pair.count == 2, let name = pair[0] as? String else { return nil }
                return Attribute(name: name, value: pair[1] as? String ?? "")
            }
            text = object["text"] as? String
            childCount = object["childCount"] as? Int ?? 0
        }

        var label: String {
            guard let tag else { return text ?? "" }
            let id = attributes.first { $0.name == "id" }.map { "#\($0.value)" } ?? ""
            let classes = attributes.first { $0.name == "class" }?.value
                .split(separator: " ").prefix(2).map { ".\($0)" }.joined() ?? ""
            return tag + id + classes
        }
    }

    struct ElementDetails {
        let id: Int
        let path: [Int]
        let node: DOMNode?
        let selector: String
        var box: Box?
        var computed: [(String, String)]
        var inlineStyle: String
        var rules: [Rule]
        var isHidden: Bool
        var htmlLength: Int

        struct Box {
            let x, y, width, height: Double
            let margin, border, padding: [Double]
            let position, display, boxSizing: String
        }

        struct Rule: Identifiable {
            let id = UUID()
            let selector: String
            /// Name/value pairs as authored: the page folds WebKit's expanded longhands
            /// back into shorthands (`font`, `margin`, …), and values may contain `;`.
            let declarations: [(String, String)]
            let source: String
            let media: String?
        }
    }

    private(set) var roots: [DOMNode] = []
    private(set) var children: [Int: [DOMNode]] = [:]
    var expanded: Set<Int> = []
    private(set) var selectedID: Int?
    private(set) var details: ElementDetails?
    private(set) var isPicking = false
    private(set) var hoveredID: Int?
    /// Bumped when the whole tree is reloaded, so views can reset scroll state.
    private(set) var treeVersion = 0
    private(set) var searchMatches: [Int] = []
    private(set) var searchIndex = 0

    func loadDocument() async {
        guard let result = await run("__wakeDT.document()") as? [String: Any] else { return }
        roots = (result["nodes"] as? [Any] ?? []).compactMap(DOMNode.init)
        children = [:]
        treeVersion += 1
        // Like Safari: <html> and <body> open, everything else closed.
        if let html = roots.first(where: { $0.tag == "html" }) {
            await expand(html.id)
            if let body = children[html.id]?.first(where: { $0.tag == "body" }) { await expand(body.id) }
        }
        if selectedID == nil, let body = children.values.joined().first(where: { $0.tag == "body" }) {
            await select(body.id, highlight: false)
        }
    }

    /// Reloads what's open without losing the selection.
    func refreshTree() async {
        let open = expanded
        let selected = selectedID
        guard let result = await run("__wakeDT.document()") as? [String: Any] else { return }
        roots = (result["nodes"] as? [Any] ?? []).compactMap(DOMNode.init)
        children = [:]
        for id in open { await loadChildren(id) }
        expanded = Set(open.filter { children[$0] != nil })
        if let selected { await select(selected, highlight: false) }
    }

    func loadChildren(_ id: Int) async {
        guard let result = await run("__wakeDT.children(\(id))") as? [Any] else { return }
        children[id] = result.compactMap(DOMNode.init)
    }

    func expand(_ id: Int) async {
        if children[id] == nil { await loadChildren(id) }
        expanded.insert(id)
    }

    func toggle(_ id: Int, recursive: Bool = false) async {
        if expanded.contains(id) {
            expanded.remove(id)
            return
        }
        await expand(id)
        guard recursive else { return }
        for child in children[id] ?? [] where child.isExpandable { await toggle(child.id, recursive: true) }
    }

    /// Selects synchronously, so key repeats step from the new row, then loads details.
    func choose(_ id: Int) {
        selectedID = id
        Task { await select(id) }
    }

    func select(_ id: Int, highlight: Bool = true) async {
        selectedID = id
        let result = await run("__wakeDT.details(\(id))") as? [String: Any]
        // Arrow keys fire faster than details arrive; drop answers for rows already left.
        guard selectedID == id else { return }
        guard let result else {
            details = nil
            return
        }
        details = Self.parseDetails(result, id: id)
        if highlight { await run("__wakeDT.highlight(\(id))") }
    }

    /// Opens every ancestor of `id` and selects it.
    func reveal(_ id: Int, path: [Int]) async {
        if roots.isEmpty { await loadDocument() }
        for ancestor in path.dropLast() { await expand(ancestor) }
        await select(id, highlight: false)
    }

    func hover(_ id: Int?) {
        guard hoveredID != id else { return }
        hoveredID = id
        Task { _ = await run(id.map { "__wakeDT.highlight(\($0))" } ?? "__wakeDT.unhighlight()") }
    }

    func setPicking(_ on: Bool) {
        isPicking = on
        setWakePickFlag(on)
        Task { _ = await run("__wakeDT.pick(\(on))") }
        if on, let webView { webView.window?.makeFirstResponder(webView) }
    }

    /// Wake's link interceptor lives in its own world and checks its own `__wakePick`,
    /// so a click that picks an element isn't also opened as a link.
    private func setWakePickFlag(_ on: Bool) {
        webView?.evaluateJavaScript("window.__wakePick = \(on); true;", in: nil, in: WebScripts.world) { _ in }
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let result = await run("__wakeDT.search(\(DevToolsScripts.quoted(query)))") as? [[String: Any]] else {
            searchMatches = []
            return
        }
        searchMatches = result.compactMap { $0["id"] as? Int }
        searchIndex = 0
        if let first = result.first, let id = first["id"] as? Int {
            await reveal(id, path: (first["path"] as? [Any])?.compactMap { $0 as? Int } ?? [])
            await run("__wakeDT.scrollTo(\(id))")
        }
    }

    func nextMatch(_ delta: Int) async {
        guard !searchMatches.isEmpty else { return }
        searchIndex = (searchIndex + delta + searchMatches.count) % searchMatches.count
        let id = searchMatches[searchIndex]
        let path = (await run("__wakeDT.path(\(id))") as? [Any])?.compactMap { $0 as? Int } ?? []
        await reveal(id, path: path)
        await run("__wakeDT.scrollTo(\(id))")
    }

    /// Edits that change the tree reload the edited node's parent.
    func edit(_ expression: String, reloadingParentOf id: Int) async {
        await run(expression)
        let parent = parentID(of: id)
        if let parent { await loadChildren(parent) }
        if let selectedID, selectedID == id { await select(id, highlight: false) }
    }

    func setAttribute(_ name: String, value: String, on id: Int) async {
        await edit("__wakeDT.setAttribute(\(id), \(DevToolsScripts.quoted(name)), \(DevToolsScripts.quoted(value)))", reloadingParentOf: id)
    }

    func removeAttribute(_ name: String, from id: Int) async {
        await edit("__wakeDT.removeAttribute(\(id), \(DevToolsScripts.quoted(name)))", reloadingParentOf: id)
    }

    func setInlineStyle(_ css: String, on id: Int) async {
        await edit("__wakeDT.setStyle(\(id), \(DevToolsScripts.quoted(css)))", reloadingParentOf: id)
    }

    func remove(_ id: Int) async {
        let parent = parentID(of: id)
        // Like Safari: the next sibling takes the selection (else the previous, else
        // the parent), so ⌫ can clear several nodes in a row.
        let siblings = parent.flatMap { children[$0] } ?? []
        let neighbour = siblings.firstIndex { $0.id == id }.flatMap { index in
            siblings.indices.contains(index + 1) ? siblings[index + 1].id : (index > 0 ? siblings[index - 1].id : nil)
        }
        await run("__wakeDT.remove(\(id))")
        if let parent {
            await loadChildren(parent)
            let stillThere = neighbour.flatMap { next in children[parent]?.contains { $0.id == next } == true ? next : nil }
            await select(stillThere ?? parent, highlight: false)
        }
    }

    func duplicate(_ id: Int) async { await edit("__wakeDT.duplicate(\(id))", reloadingParentOf: id) }
    func toggleHidden(_ id: Int) async { await edit("__wakeDT.toggleHidden(\(id))", reloadingParentOf: id) }
    func scrollIntoView(_ id: Int) async { await run("__wakeDT.scrollTo(\(id))") }

    func outerHTML(_ id: Int) async -> String {
        await run("__wakeDT.outerHTML(\(id))") as? String ?? ""
    }

    func setOuterHTML(_ html: String, on id: Int) async {
        let parent = parentID(of: id)
        let replaced = await run("__wakeDT.setOuterHTML(\(id), \(DevToolsScripts.quoted(html)))") as? [String: Any]
        if let parent { await loadChildren(parent) }
        // Select what the edit made, as Safari does, rather than its parent.
        if let replaced, let newID = replaced["id"] as? Int {
            await reveal(newID, path: (replaced["path"] as? [Any])?.compactMap { $0 as? Int } ?? [])
        } else if let parent {
            await select(parent, highlight: false)
        }
    }

    func parentID(of id: Int) -> Int? {
        children.first { $0.value.contains { $0.id == id } }?.key
    }

    func node(_ id: Int) -> DOMNode? {
        roots.first { $0.id == id } ?? children.values.lazy.joined().first { $0.id == id }
    }

    /// Rows for the tree, in document order, with closing tags after open elements.
    struct TreeRow: Identifiable {
        let node: DOMNode
        let depth: Int
        let isClosing: Bool
        var id: String { isClosing ? "/\(node.id)" : "\(node.id)" }
    }

    var treeRows: [TreeRow] {
        var rows: [TreeRow] = []
        func add(_ nodes: [DOMNode], depth: Int) {
            for node in nodes {
                rows.append(TreeRow(node: node, depth: depth, isClosing: false))
                if expanded.contains(node.id), let kids = children[node.id] {
                    add(kids, depth: depth + 1)
                    if node.isElement { rows.append(TreeRow(node: node, depth: depth, isClosing: true)) }
                }
            }
        }
        add(roots, depth: 0)
        return rows
    }

    private static func parseDetails(_ object: [String: Any], id: Int) -> ElementDetails {
        let box = (object["box"] as? [String: Any]).map { box in
            ElementDetails.Box(
                x: number(box["x"]), y: number(box["y"]), width: number(box["width"]), height: number(box["height"]),
                margin: (box["margin"] as? [Any] ?? []).map(number),
                border: (box["border"] as? [Any] ?? []).map(number),
                padding: (box["padding"] as? [Any] ?? []).map(number),
                position: box["position"] as? String ?? "", display: box["display"] as? String ?? "",
                boxSizing: box["boxSizing"] as? String ?? ""
            )
        }
        let computed = (object["computed"] as? [[Any]] ?? []).compactMap { pair -> (String, String)? in
            guard pair.count == 2, let name = pair[0] as? String else { return nil }
            return (name, pair[1] as? String ?? "")
        }
        let rules = (object["rules"] as? [[String: Any]] ?? []).map {
            ElementDetails.Rule(
                selector: $0["selector"] as? String ?? "",
                declarations: ($0["decls"] as? [[Any]] ?? []).compactMap { pair in
                    guard pair.count == 2, let name = pair[0] as? String, let value = pair[1] as? String else { return nil }
                    return (name, value)
                },
                source: $0["source"] as? String ?? "", media: $0["media"] as? String)
        }
        return ElementDetails(
            id: id,
            path: (object["path"] as? [Any] ?? []).compactMap { $0 as? Int },
            node: object["node"].flatMap(DOMNode.init),
            selector: object["selector"] as? String ?? "",
            box: box,
            computed: computed,
            inlineStyle: object["inline"] as? String ?? "",
            rules: rules,
            isHidden: object["hidden"] as? Bool ?? false,
            htmlLength: object["html"] as? Int ?? 0
        )
    }

    // MARK: Console

    private(set) var history: [String] = []

    func evaluate(_ code: String) async {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, let page else { return }
        if history.last != code { history.append(code) }
        if history.count > 200 { history.removeFirst(history.count - 200) }
        page.devtools.addLocal(.input, code)
        let result = await runAsync(DevToolsScripts.evaluate, arguments: ["code": code]) as? [String: Any]
        guard let result else {
            page.devtools.addLocal(.error, "Couldn't evaluate in this page.")
            return
        }
        let ok = result["ok"] as? Bool ?? false
        page.devtools.addLocal(ok ? .result : .error, result["text"] as? String ?? "undefined")
        if ok, result["kind"] as? String == "node" { await refreshSelectionFromPage() }
    }

    func completions(for code: String) async -> [String] {
        (await runAsync(DevToolsScripts.completions, arguments: ["code": code]) as? [String]) ?? []
    }

    /// An element returned in the console becomes `$0` and the Elements selection.
    private func refreshSelectionFromPage() async {
        guard let current = await run("__wakeDT.current()") as? [String: Any], let id = current["id"] as? Int else { return }
        await reveal(id, path: (current["path"] as? [Any])?.compactMap { $0 as? Int } ?? [])
    }

    // MARK: Network (resource timing)

    struct Resource: Identifiable, Hashable {
        let id: Int
        let url: URL
        let type: String
        let start: Double
        let duration: Double
        let transferSize: Int
        let encodedSize: Int
        let decodedSize: Int
        let protocolName: String
        let status: Int
        let blocked, dns, connect, tls, wait, download: Double

        var isCached: Bool { transferSize == 0 && decodedSize > 0 }
    }

    private(set) var resources: [Resource] = []
    @ObservationIgnored private var resourceCursor = 0

    func pollResources() async {
        guard let result = await run("__wakeDT.resources(\(resourceCursor))") as? [String: Any] else { return }
        let total = result["total"] as? Int ?? 0
        if total < resourceCursor {
            // The page cleared its buffer (or it's a new document).
            resourceCursor = 0
            resources = []
            return
        }
        let entries = (result["entries"] as? [[String: Any]] ?? []).enumerated().compactMap { offset, entry -> Resource? in
            guard let string = entry["url"] as? String, let url = URL(string: string) else { return nil }
            let n = { (key: String) in Self.number(entry[key]) }
            return Resource(
                id: resources.count + offset, url: url, type: entry["type"] as? String ?? "other",
                start: n("start"), duration: n("duration"),
                transferSize: Int(n("transfer")), encodedSize: Int(n("encoded")), decodedSize: Int(n("decoded")),
                protocolName: entry["protocol"] as? String ?? "", status: Int(n("status")),
                blocked: n("blocked"), dns: n("dns"), connect: n("connect"), tls: n("tls"), wait: n("wait"), download: n("download")
            )
        }
        resourceCursor = total
        if !entries.isEmpty { resources.append(contentsOf: entries) }
    }

    func clearResources() {
        resources = []
    }

    // MARK: Storage

    struct StorageItem: Identifiable, Hashable {
        let key: String
        let value: String
        let length: Int
        var id: String { key }
    }

    struct AsyncStorage {
        struct Database: Identifiable, Hashable { let name: String; let version: Int; var id: String { name } }
        struct Cache: Identifiable, Hashable { let name: String; let count: Int; var id: String { name } }
        struct Worker: Identifiable, Hashable { let scope: String; let script: String; let state: String; var id: String { scope } }
        var databases: [Database] = []
        var caches: [Cache] = []
        var workers: [Worker] = []
    }

    private(set) var localItems: [StorageItem] = []
    private(set) var sessionItems: [StorageItem] = []
    private(set) var cookies: [HTTPCookie] = []
    private(set) var asyncStorage = AsyncStorage()

    func loadStorage() async {
        localItems = await items("local")
        sessionItems = await items("session")
        await loadCookies()
        if let result = await runAsync(DevToolsScripts.asyncStorage) as? [String: Any] {
            asyncStorage = AsyncStorage(
                databases: (result["databases"] as? [[String: Any]] ?? []).map { .init(name: $0["name"] as? String ?? "", version: Int(Self.number($0["version"]))) },
                caches: (result["caches"] as? [[String: Any]] ?? []).map { .init(name: $0["name"] as? String ?? "", count: $0["count"] as? Int ?? 0) },
                workers: (result["workers"] as? [[String: Any]] ?? []).map { .init(scope: $0["scope"] as? String ?? "", script: $0["script"] as? String ?? "", state: $0["state"] as? String ?? "") }
            )
        }
    }

    private func items(_ kind: String) async -> [StorageItem] {
        (await run("__wakeDT.storage('\(kind)')") as? [[Any]] ?? []).compactMap { row in
            guard row.count == 3, let key = row[0] as? String else { return nil }
            return StorageItem(key: key, value: row[1] as? String ?? "", length: row[2] as? Int ?? 0)
        }
    }

    func setStorage(_ kind: String, key: String, value: String) async {
        await run("__wakeDT.storageSet('\(kind)', \(DevToolsScripts.quoted(key)), \(DevToolsScripts.quoted(value)))")
        await reloadItems(kind)
    }

    func removeStorage(_ kind: String, key: String) async {
        await run("__wakeDT.storageRemove('\(kind)', \(DevToolsScripts.quoted(key)))")
        await reloadItems(kind)
    }

    func clearStorage(_ kind: String) async {
        await run("__wakeDT.storageClear('\(kind)')")
        await reloadItems(kind)
    }

    private func reloadItems(_ kind: String) async {
        if kind == "local" { localItems = await items("local") } else { sessionItems = await items("session") }
    }

    private var cookieStore: WKHTTPCookieStore? { webView?.configuration.websiteDataStore.httpCookieStore }

    func loadCookies() async {
        guard let store = cookieStore, let host = page?.url?.host()?.lowercased() else {
            cookies = []
            return
        }
        let all = await store.allCookies()
        cookies = all.filter { Self.cookie($0, matches: host) }.sorted { $0.name < $1.name }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        await cookieStore?.deleteCookie(cookie)
        await loadCookies()
    }

    func setCookie(name: String, value: String, replacing old: HTTPCookie?) async {
        guard let store = cookieStore, let url = page?.url, let host = url.host() else { return }
        var properties: [HTTPCookiePropertyKey: Any] = old?.properties ?? [.domain: host, .path: "/"]
        properties[.name] = name
        properties[.value] = value
        if let old, old.name != name { await store.deleteCookie(old) }
        guard let cookie = HTTPCookie(properties: properties) else { return }
        await store.setCookie(cookie)
        await loadCookies()
    }

    func clearCookies() async {
        for cookie in cookies { await cookieStore?.deleteCookie(cookie) }
        await loadCookies()
    }

    /// Set when a database delete is waiting on the page.
    var blockedDatabase: String?

    /// Limitation: a page can't close another script's IndexedDB connection, and WebKit
    /// has no API to force it. While the page holds the database open, the delete is
    /// queued ("blocked") and completes once the page lets go, e.g. on reload.
    func deleteDatabase(_ name: String) async {
        let result = await runAsync(DevToolsScripts.deleteDatabase, arguments: ["name": name]) as? String
        blockedDatabase = result == "blocked" ? name : nil
        await loadStorage()
    }

    func deleteCache(_ name: String) async {
        await runAsync(DevToolsScripts.deleteCache, arguments: ["name": name])
        await loadStorage()
    }

    func unregisterWorker(_ scope: String) async {
        await runAsync(DevToolsScripts.unregisterWorker, arguments: ["name": scope])
        await loadStorage()
    }

    /// Cookies, storage, caches and databases for the page's site, then a reload.
    func clearSiteData() async {
        guard let store = webView?.configuration.websiteDataStore, let host = page?.url?.host()?.lowercased() else { return }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let matching = records.filter { host == $0.displayName || host.hasSuffix("." + $0.displayName) }
        await store.removeData(ofTypes: types, for: matching)
        page?.reload()
        documentChanged()
    }

    static func cookie(_ cookie: HTTPCookie, matches host: String) -> Bool {
        let domain = cookie.domain.lowercased()
        let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return host == bare || host.hasSuffix("." + bare)
    }

    // MARK: Performance

    struct Metrics {
        var ttfb, domInteractive, dcl, load, fcp, lcp, cls, inp: Double?
        var support: [String: Bool]
        var requests: Int
        var transfer: Int
        var decoded: Int
        var documentTransfer: Int
        var protocolName: String
        var navigationType: String
        var byType: [(type: String, count: Int, transfer: Int, decoded: Int)]
        var domNodes, domDepth, scripts, styleSheets, images, iframes: Int
        var devicePixelRatio: Double
        var viewport: String
    }

    struct Audit: Identifiable {
        enum State: String { case pass, warn, fail }
        let id: String
        let title: String
        let state: State
        let detail: String
        let count: Int
    }

    private(set) var metrics: Metrics?
    private(set) var audits: [Audit] = []
    private(set) var fpsSamples: [Double] = []

    func loadMetrics() async {
        guard let m = await run("__wakeDT.metrics()") as? [String: Any] else { return }
        let optional = { (key: String) -> Double? in (m[key] as? NSNumber)?.doubleValue }
        let byType = (m["byType"] as? [String: [String: Any]] ?? [:]).map {
            (type: $0.key, count: $0.value["count"] as? Int ?? 0, transfer: Int(Self.number($0.value["transfer"])), decoded: Int(Self.number($0.value["decoded"])))
        }.sorted { $0.decoded > $1.decoded }
        metrics = Metrics(
            ttfb: optional("ttfb"), domInteractive: optional("domInteractive"), dcl: optional("dcl"), load: optional("load"),
            fcp: optional("fcp"), lcp: optional("lcp"), cls: optional("cls"), inp: optional("inp"),
            support: m["support"] as? [String: Bool] ?? [:],
            requests: m["requests"] as? Int ?? 0, transfer: Int(Self.number(m["transfer"])), decoded: Int(Self.number(m["decoded"])),
            documentTransfer: Int(Self.number(m["docTransfer"])),
            protocolName: m["protocol"] as? String ?? "", navigationType: m["navType"] as? String ?? "",
            byType: byType,
            domNodes: m["domNodes"] as? Int ?? 0, domDepth: m["domDepth"] as? Int ?? 0,
            scripts: m["scripts"] as? Int ?? 0, styleSheets: m["styleSheets"] as? Int ?? 0,
            images: m["images"] as? Int ?? 0, iframes: m["iframes"] as? Int ?? 0,
            devicePixelRatio: Self.number(m["dpr"]), viewport: m["viewport"] as? String ?? ""
        )
    }

    func runAudits() async {
        audits = (await run("__wakeDT.audits()") as? [[String: Any]] ?? []).map {
            Audit(id: $0["id"] as? String ?? UUID().uuidString, title: $0["title"] as? String ?? "",
                  state: Audit.State(rawValue: $0["state"] as? String ?? "") ?? .warn,
                  detail: $0["detail"] as? String ?? "", count: $0["count"] as? Int ?? 0)
        }
    }

    func sampleFPS() async {
        guard let value = await run("__wakeDT.fps()") as? Double else { return }
        fpsSamples.append(min(value, 240))
        if fpsSamples.count > 60 { fpsSamples.removeFirst(fpsSamples.count - 60) }
    }

    func stopFPS() {
        Task { _ = await run("__wakeDT.fpsStop()") }
    }

    // MARK: Sources

    struct Source: Identifiable, Hashable {
        enum Kind: String { case script, style }
        let kind: Kind
        let url: URL?
        let index: Int
        let isModule: Bool
        /// 1-based among the page's inline scripts or styles (`index` counts every one).
        var inlineNumber = 0
        var id: String { url?.absoluteString ?? "\(kind.rawValue)#\(index)" }

        var name: String {
            guard let url else { return kind == .script ? "Inline script \(inlineNumber)" : "Inline style \(inlineNumber)" }
            let last = url.lastPathComponent
            return last.isEmpty || last == "/" ? (url.host() ?? url.absoluteString) : last
        }

        var group: String { url?.host() ?? "Inline" }
    }

    private(set) var sources: [Source] = []

    func loadSources() async {
        var seen = Set<String>()
        var inlineCounts: [Source.Kind: Int] = [:]
        sources = (await run("__wakeDT.sources()") as? [[String: Any]] ?? []).compactMap { item in
            var source = Source(
                kind: Source.Kind(rawValue: item["kind"] as? String ?? "") ?? .script,
                url: (item["url"] as? String).flatMap(URL.init(string:)),
                index: item["index"] as? Int ?? 0,
                isModule: item["module"] as? Bool ?? false
            )
            guard seen.insert(source.id).inserted else { return nil }
            if source.url == nil {
                inlineCounts[source.kind, default: 0] += 1
                source.inlineNumber = inlineCounts[source.kind, default: 1]
            }
            return source
        }
    }

    /// The text of a script or stylesheet: inline ones from the DOM, the rest fetched
    /// with the page's cookies, falling back to a plain request when CORS refuses.
    func text(of source: Source) async -> String {
        guard let url = source.url else {
            return await run("__wakeDT.inlineSource('\(source.kind.rawValue)', \(source.index))") as? String ?? ""
        }
        return await text(of: url)
    }

    func text(of url: URL) async -> String {
        if let text = await runAsync(DevToolsScripts.fetchSource, arguments: ["url": url.absoluteString], world: WebScripts.world) as? String {
            return text
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The document as the server sent it (⌥⌘U).
    func documentSource() async -> String {
        guard let url = page?.url else { return "" }
        return await text(of: url)
    }

    // MARK: Page overrides

    enum ColorScheme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    private(set) var colorScheme: ColorScheme = .system
    private(set) var userAgent: UserAgentPreset?
    private(set) var stylesDisabled = false
    private(set) var outlinesShown = false
    private(set) var designMode = false

    /// `prefers-color-scheme` follows the web view's own appearance.
    func setColorScheme(_ scheme: ColorScheme) {
        colorScheme = scheme
        webView?.appearance = switch scheme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// `nil` goes back to Wake's own (Safari's) user agent. Reloads, since servers
    /// read it on the first request.
    func setUserAgent(_ preset: UserAgentPreset?) {
        userAgent = preset
        webView?.customUserAgent = preset?.string
        page?.reload()
    }

    var isJavaScriptDisabled: Bool { page?.isJavaScriptDisabled ?? false }

    func setJavaScriptDisabled(_ on: Bool) {
        page?.isJavaScriptDisabled = on
        page?.reload()
    }

    func setStylesDisabled(_ on: Bool) {
        stylesDisabled = on
        Task { _ = await run("__wakeDT.styles(\(on))") }
    }

    func setOutlines(_ on: Bool) {
        outlinesShown = on
        Task { _ = await run("__wakeDT.outlines(\(on))") }
    }

    func setDesignMode(_ on: Bool) {
        designMode = on
        Task { _ = await run("__wakeDT.designMode(\(on))") }
    }

    func copyScreenshot() async {
        guard let webView, let image = try? await webView.takeSnapshot(configuration: nil) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    /// The whole page, not just what's on screen, as a PDF on the clipboard.
    func copyFullPagePDF() async {
        guard let webView, let data = try? await webView.pdf() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .pdf)
    }

    static func emptyCaches() async {
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]
        await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast)
    }

    // MARK: Helpers

    static func number(_ any: Any?) -> Double {
        (any as? NSNumber)?.doubleValue ?? 0
    }
}

/// Common user agents for the Tools menu. Wake presents as Safari by default.
enum UserAgentPreset: String, CaseIterable, Identifiable {
    case safariMac, safariiPhone, safariiPad, chromeMac, chromeWindows, chromeAndroid, firefoxMac, edgeWindows

    var id: Self { self }

    var title: String {
        switch self {
        case .safariMac: "Safari — macOS"
        case .safariiPhone: "Safari — iPhone"
        case .safariiPad: "Safari — iPad"
        case .chromeMac: "Chrome — macOS"
        case .chromeWindows: "Chrome — Windows"
        case .chromeAndroid: "Chrome — Android"
        case .firefoxMac: "Firefox — macOS"
        case .edgeWindows: "Edge — Windows"
        }
    }

    var string: String {
        switch self {
        case .safariMac: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        case .safariiPhone: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        case .safariiPad: "Mozilla/5.0 (iPad; CPU OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        case .chromeMac: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
        case .chromeWindows: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
        case .chromeAndroid: "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36"
        case .firefoxMac: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.6; rv:142.0) Gecko/20100101 Firefox/142.0"
        case .edgeWindows: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0"
        }
    }
}
