import Foundation
import WebKit

/// What a page reports when a moment is saved.
struct MomentPageState {
    var title = ""
    var selection: String?
    var selectionPrefix: String?
    var scrollY: Double = 0
    var scrollFraction: Double = 0
    var text = ""

    init() {}

    init(_ value: Any?) {
        guard let dictionary = value as? [String: Any] else { return }
        title = dictionary["title"] as? String ?? ""
        selection = (dictionary["selection"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        selectionPrefix = (dictionary["prefix"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        scrollY = dictionary["scrollY"] as? Double ?? 0
        scrollFraction = dictionary["fraction"] as? Double ?? 0
        text = String((dictionary["text"] as? String ?? "").prefix(MomentDiff.maxTextLength))
    }
}

/// Where to take a page back to.
struct MomentRestore {
    let selection: String?
    let prefix: String?
    let scrollY: Double
    let scrollFraction: Double

    init(_ moment: MomentRecord) {
        selection = moment.selectedText
        prefix = moment.selectionPrefix
        scrollY = moment.scrollY
        scrollFraction = moment.scrollFraction
    }
}

/// Scripts for saving and restoring moments (`shared/scripts/moment-*.js`). They run
/// in Wake's content world; the highlight uses the CSS Custom Highlight API, which
/// marks text without touching the page's DOM (so React and friends don't notice).
enum MomentScripts {
    static var capture: String { SharedScript.momentCapture.source(["maxText": MomentDiff.maxTextLength]) }

    static var visibleText: String { SharedScript.visibleText.source(["maxText": MomentDiff.maxTextLength]) }

    /// Scrolls back and re-highlights the selection. Returns whether the selection
    /// was found (pages that render late are retried by the caller).
    static func restore(_ restore: MomentRestore) -> String {
        SharedScript.momentRestore.source([
            "key": restore.selection.map(searchKey) ?? "",
            "prefix": restore.prefix ?? "",
            "scrollY": restore.scrollY.isFinite ? restore.scrollY : 0,
            "scrollFraction": restore.scrollFraction.isFinite ? restore.scrollFraction : 0,
        ])
    }

    /// `window.find` can't cross line breaks: search for the first line (up to 150
    /// characters) of the selection.
    private static func searchKey(_ selection: String) -> String {
        let firstLine = selection.split(whereSeparator: \.isNewline).first.map(String.init) ?? selection
        return String(firstLine.trimmingCharacters(in: .whitespaces).prefix(150))
    }
}

extension BrowserPage {
    func captureMomentState() async -> MomentPageState {
        let value = try? await webView.evaluateJavaScript(MomentScripts.capture, in: nil, contentWorld: WebScripts.world)
        var state = MomentPageState(value)
        if state.title.isEmpty { state.title = displayTitle }
        return state
    }

    func visibleText() async -> String {
        let value = try? await webView.evaluateJavaScript(MomentScripts.visibleText, in: nil, contentWorld: WebScripts.world)
        return value as? String ?? ""
    }

    /// Scrolls back and highlights, retrying while a late-rendering page fills in.
    func applyRestore(_ restore: MomentRestore) async {
        for delay in [0.3, 1.2, 3.0] {
            try? await Task.sleep(for: .seconds(delay))
            let found = try? await webView.evaluateJavaScript(MomentScripts.restore(restore), in: nil, contentWorld: WebScripts.world)
            if found as? Bool == true { return }
        }
    }
}
