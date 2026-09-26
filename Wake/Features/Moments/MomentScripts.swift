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

/// Scripts for saving and restoring moments. They run in Wake's content world; the
/// highlight uses the CSS Custom Highlight API, which marks text without touching
/// the page's DOM (so React and friends don't notice).
enum MomentScripts {
    static let capture = """
    (() => {
      const selection = window.getSelection();
      const text = selection ? selection.toString().trim().slice(0, 1200) : '';
      let prefix = '';
      if (text && selection.rangeCount) {
        const range = selection.getRangeAt(0);
        const before = document.createRange();
        before.setStart(document.body, 0);
        before.setEnd(range.startContainer, range.startOffset);
        prefix = before.toString().replace(/\\s+/g, ' ').slice(-48);
      }
      const root = document.scrollingElement || document.documentElement;
      const max = Math.max(1, root.scrollHeight - window.innerHeight);
      return {
        title: document.title,
        selection: text,
        prefix: prefix,
        scrollY: window.scrollY,
        fraction: Math.min(1, window.scrollY / max),
        text: document.body ? document.body.innerText.slice(0, \(MomentDiff.maxTextLength)) : ''
      };
    })()
    """

    static let visibleText = "document.body ? document.body.innerText.slice(0, \(MomentDiff.maxTextLength)) : ''"

    /// Scrolls back and re-highlights the selection. Returns whether the selection
    /// was found (pages that render late are retried by the caller).
    static func restore(_ restore: MomentRestore) -> String {
        let key = restore.selection.map(searchKey) ?? ""
        return """
        (() => {
          const key = \(jsString(key));
          const prefix = \(jsString(restore.prefix ?? ""));
          const root = document.scrollingElement || document.documentElement;
          const max = Math.max(1, root.scrollHeight - window.innerHeight);
          const scrollBack = () => {
            const y = \(restore.scrollY);
            // The page grew or shrank since: use the same fraction of the way down.
            const target = (y + window.innerHeight * 0.5 <= root.scrollHeight) ? y : \(restore.scrollFraction) * max;
            window.scrollTo({ top: target, behavior: 'instant' });
          };
          if (!key) { scrollBack(); return true; }
          if (!document.getElementById('__wake_moment_style')) {
            const style = document.createElement('style');
            style.id = '__wake_moment_style';
            style.dataset.wakeOverlay = '';
            style.textContent = '::highlight(wake-moment) { background-color: rgba(255, 214, 10, 0.45); }';
            (document.head || document.documentElement).appendChild(style);
          }
          const normal = s => s.replace(/\\s+/g, ' ');
          const selection = window.getSelection();
          selection.removeAllRanges();
          let found = null;
          // window.find walks matches in order; the prefix picks the right one.
          for (let i = 0; i < 25 && window.find(key, false, false, false, false, false, false); i++) {
            const range = selection.getRangeAt(0).cloneRange();
            if (!found) found = range;
            if (!prefix) break;
            const before = document.createRange();
            before.setStart(document.body, 0);
            before.setEnd(range.startContainer, range.startOffset);
            if (normal(before.toString()).endsWith(normal(prefix).slice(-24))) { found = range; break; }
          }
          selection.removeAllRanges();
          if (!found) { scrollBack(); return false; }
          if (window.CSS && CSS.highlights && window.Highlight) {
            CSS.highlights.set('wake-moment', new Highlight(found));
          }
          const rect = found.getBoundingClientRect();
          window.scrollTo({ top: window.scrollY + rect.top - window.innerHeight * 0.35, behavior: 'instant' });
          return true;
        })()
        """
    }

    /// `window.find` can't cross line breaks: search for the first line (up to 150
    /// characters) of the selection.
    private static func searchKey(_ selection: String) -> String {
        let firstLine = selection.split(whereSeparator: \.isNewline).first.map(String.init) ?? selection
        return String(firstLine.trimmingCharacters(in: .whitespaces).prefix(150))
    }

    private static func jsString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
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
