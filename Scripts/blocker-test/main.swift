// Converts EasyList and EasyPrivacy with FilterListConverter and compiles the
// result with WebKit, the way Wake does, plus a few conversion checks.
// Usage: Scripts/blocker-test/run.sh
import AppKit
import WebKit

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> Any = "") {
    print(ok ? "  ok    \(name)" : "  FAIL  \(name)  \(detail())")
    if !ok { failures += 1 }
}

func filter(_ line: String) -> String? {
    (FilterListConverter.network(line)?["trigger"] as? [String: Any])?["url-filter"] as? String
}

print("Conversion")
check("||host^ anchors to the domain", filter("||ads.example.com^") == "^[^:]+://+([^:/]+\\.)?ads\\.example\\.com")
check("separators and wildcards", filter("/banner/*/ad^x") == "/banner/.*/ad[/:?=&]x")
check("$third-party sets load-type", ((FilterListConverter.network("||t.co^$third-party")?["trigger"] as? [String: Any])?["load-type"] as? [String]) == ["third-party"])
check("resource types map", ((FilterListConverter.network("||x.com^$script,image")?["trigger"] as? [String: Any])?["resource-type"] as? [String]) == ["script", "image"])
check("unsupported options are skipped", FilterListConverter.network("||x.com^$csp=script-src 'none'") == nil)
check("regex rules are skipped", FilterListConverter.network("/ads[0-9]+/") == nil)
check("@@…$document allows a site", ((FilterListConverter.network("@@||good.org^$document")?["action"] as? [String: Any])?["type"] as? String) == "ignore-previous-rules")
check("site-scoped hiding", FilterListConverter.cosmetic("a.com,b.org##.ad")?.0 == ["a.com", "b.org"])
check("generic hiding is skipped", FilterListConverter.cosmetic("##.ad") == nil)
check("extended CSS is skipped", FilterListConverter.cosmetic("a.com##div:has(.ad)") == nil)

@MainActor
func compile() async {
    print("EasyList + EasyPrivacy")
    var texts: [String] = []
    for name in ["easylist", "easyprivacy"] {
        let url = URL(string: "https://easylist.to/easylist/\(name).txt")!
        guard let (data, _) = try? await URLSession.shared.data(from: url), let text = String(data: data, encoding: .utf8) else {
            print("  skip  couldn't download \(name)"); return
        }
        texts.append(text)
    }
    var start = Date()
    let output = FilterListConverter.convert(texts, allowedSites: ["example.org"])
    let json = output.json
    print("  info  \(output.rules.count) rules, \(output.skipped) skipped, \(json.utf8.count / 1024) KB, converted in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    check("fits WebKit's limit", output.rules.count <= FilterListConverter.maxRules)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wake-blocker-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = WKContentRuleListStore(url: folder)!
    start = Date()
    do {
        let list = try await store.compileContentRuleList(forIdentifier: "test", encodedContentRuleList: json)
        check("WebKit compiles it", list != nil)
        print("  info  compiled in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        start = Date()
        let again = try await store.contentRuleList(forIdentifier: "test")
        check("the compiled list is found again", again != nil)
        print("  info  looked up in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    } catch {
        check("WebKit compiles it", false, error)
    }
    try? FileManager.default.removeItem(at: folder)
}

Task { @MainActor in
    await compile()
    print(failures == 0 ? "All blocker tests passed." : "\(failures) blocker test(s) failed.")
    exit(failures == 0 ? 0 : 1)
}
RunLoop.main.run()
