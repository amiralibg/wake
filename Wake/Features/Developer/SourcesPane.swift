import AppKit
import SwiftUI

/// The page's scripts and stylesheets, plus the document itself, read-only with
/// line numbers, find (⌘F) and a pretty-printer for minified files.
///
/// Limitation: breakpoints and stepping need WebKit's debugger, which has no public
/// API; the Web Inspector button in the header opens it.
struct SourcesPane: View {
    let page: BrowserPage
    @State private var selection: String?
    @State private var text = ""
    @State private var isLoading = false
    @State private var prettyPrints = false
    /// `text` pretty-printed, made off the main thread (minified bundles run to megabytes).
    @State private var formatted: String?
    @State private var filter = ""

    static let documentID = "__document__"

    private var session: DevToolsSession { page.inspector }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 120, idealWidth: 160, maxWidth: 200)
            VStack(spacing: 0) {
                editorBar
                Divider()
                if isLoading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selection == nil {
                    ContentUnavailableView("Pick a file", systemImage: "doc.text", description: Text("Scripts and stylesheets the page loaded."))
                        .frame(maxHeight: .infinity)
                } else if prettyPrints, formatted == nil {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CodeTextView(text: prettyPrints ? formatted ?? text : text)
                }
            }
            .frame(minWidth: 240)
        }
        .task(id: FormatKey(text: text, pretty: prettyPrints)) {
            formatted = nil
            guard prettyPrints else { return }
            let source = text
            let result = await Task.detached(priority: .userInitiated) { CodeFormatter.pretty(source) }.value
            if !Task.isCancelled { formatted = result }
        }
        .task(id: session.documentLoads) {
            await session.loadSources()
            if selection == nil { selection = Self.documentID }
        }
        .task(id: selection) { await load() }
    }

    private var list: some View {
        let query = filter.trimmingCharacters(in: .whitespaces)
        let sources = session.sources.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || ($0.url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false) }
        let groups = Dictionary(grouping: sources, by: \.group).sorted { lhs, rhs in
            lhs.key == page.url?.host() || (rhs.key != page.url?.host() && lhs.key < rhs.key)
        }
        return VStack(spacing: 0) {
            DevToolsSearchField(text: $filter, prompt: "Filter files")
                .controlSize(.small)
                .padding(8)
            List(selection: $selection) {
                Label {
                    Text(page.url?.lastPathComponent.isEmpty == false ? page.url!.lastPathComponent : "(document)")
                } icon: {
                    Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                }
                .tag(Self.documentID)
                ForEach(groups, id: \.key) { group, items in
                    Section(group) {
                        ForEach(items) { source in
                            Label {
                                Text(source.name)
                            } icon: {
                                Image(systemName: source.kind == .script ? "curlybraces" : "paintbrush").foregroundStyle(.secondary)
                            }
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(source.url?.absoluteString ?? source.name)
                                .tag(source.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .font(.system(size: 11.5))
        }
    }

    private var editorBar: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Toggle("{ } Pretty", isOn: $prettyPrints)
                .toggleStyle(.button)
                .help("Pretty-print minified code")
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy")
            if let url = selectedURL {
                Button {
                    Task { _ = await EditorOpener.open(SourceLocation(url: url, line: 1, column: 1)) }
                } label: { Image(systemName: "hammer") }
                    .buttonStyle(.borderless)
                    .help("Open in Editor (through source maps)")
                Button { BrowserModel.active?.trail.open(url) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
                    .help("Open in a new column")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    private var selectedSource: DevToolsSession.Source? {
        session.sources.first { $0.id == selection }
    }

    private var selectedURL: URL? {
        selection == Self.documentID ? page.url : selectedSource?.url
    }

    private var title: String {
        selection == Self.documentID ? (page.url?.absoluteString ?? "") : (selectedSource?.url?.absoluteString ?? selectedSource?.name ?? "")
    }

    private struct FormatKey: Equatable {
        let text: String
        let pretty: Bool
    }

    private func load() async {
        guard let selection else { return }
        isLoading = true
        defer { isLoading = false }
        if selection == Self.documentID {
            text = await session.documentSource()
        } else if let source = selectedSource {
            text = await session.text(of: source)
        }
        // Minified files are one enormous line: pretty-print them by default.
        let lines = text.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
        prettyPrints = text.count > 2000 && text.count / lines > 400
    }
}

/// A read-only NSTextView: handles megabytes of code, and brings find (⌘F) and
/// line numbers without SwiftUI laying out every line.
struct CodeTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        // No wrapping: code reads by line.
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = LineNumberRuler(textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        // The old selection (often far along one long minified line) would otherwise
        // be scrolled back into view once the new text is laid out, leaving the view
        // scrolled sideways. The frame also keeps the old, much wider size until
        // resized, so shrink it to the new text before going back to the top left.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.sizeToFit()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollView.verticalRulerView?.needsDisplay = true
    }
}

/// Line numbers beside a CodeTextView, drawn only for the visible lines.
private final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: textView.enclosingScrollView?.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification, object: textView)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func refresh() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let string = textView.string as NSString
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // Count the lines before the visible range once, then walk the visible ones.
        var line = 1
        string.enumerateSubstrings(in: NSRange(location: 0, length: characters.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        var index = characters.location
        while index < NSMaxRange(characters) {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            let glyph = layout.glyphIndexForCharacter(at: lineRange.location)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = fragment.minY + textView.textContainerInset.height - visible.minY
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: y + (fragment.height - size.height) / 2), withAttributes: attributes)
            line += 1
            index = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }
    }
}

/// Indents minified JavaScript and CSS for reading. It tracks strings, template
/// literals and comments so it doesn't break them, but it isn't a parser: regex
/// literals containing braces can throw the indentation off.
enum CodeFormatter {
    static func pretty(_ code: String) -> String {
        guard code.count < 3_000_000 else { return code }
        var out = ""
        out.reserveCapacity(code.count + code.count / 4)
        var depth = 0
        var quote: Character?
        var inLineComment = false
        var inBlockComment = false
        var parens = 0
        var previous: Character = " "
        let chars = Array(code)
        var i = 0

        func newline() {
            while out.last == " " { out.removeLast() }
            if out.last != "\n" { out.append("\n") }
            out.append(String(repeating: "  ", count: max(0, depth)))
        }

        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if inLineComment {
                out.append(c)
                if c == "\n" { inLineComment = false; out.append(String(repeating: "  ", count: max(0, depth))) }
            } else if inBlockComment {
                out.append(c)
                if c == "*", next == "/" { out.append("/"); i += 1; inBlockComment = false }
            } else if let q = quote {
                out.append(c)
                if c == "\\", let next { out.append(next); i += 1 } else if c == q { quote = nil }
            } else {
                switch c {
                case "\"", "'", "`":
                    quote = c
                    out.append(c)
                case "/" where next == "/" && previous != "\\" && previous != ":":
                    inLineComment = true
                    out.append(c)
                case "/" where next == "*":
                    inBlockComment = true
                    out.append(c)
                case "{":
                    // One space before a block ("if (a) {", never "if (a)  {"); none
                    // inside a call or literal ("f({", "[{", "a={") or at a line start.
                    let hadSpace = out.last == " "
                    while out.last == " " { out.removeLast() }
                    if let last = out.last, !"([\n".contains(last), hadSpace || !"=:".contains(last) { out.append(" ") }
                    out.append("{")
                    depth += 1
                    newline()
                case "}":
                    depth -= 1
                    newline()
                    out.append("}")
                    var j = i + 1
                    while j < chars.count, chars[j] == " " || chars[j] == "\n" || chars[j] == "\r" || chars[j] == "\t" { j += 1 }
                    let rest = chars[j..<min(j + 8, chars.count)]
                    if Self.continuesBlock(rest) {
                        // "} else {", "} catch (e) {", "} finally {"
                        out.append(" ")
                        i = j - 1
                    } else if j < chars.count, !";,)]".contains(chars[j]) {
                        newline()
                    }
                case ";":
                    out.append(";")
                    if parens == 0 { newline() }
                case "(":
                    parens += 1
                    out.append(c)
                case ")":
                    parens = max(0, parens - 1)
                    out.append(c)
                case "\n", "\r":
                    if out.last != "\n", out.last != " " { newline() }
                default:
                    if c == " ", out.last == " " || out.last == "\n" { break }
                    out.append(c)
                }
            }
            if !c.isWhitespace { previous = c }
            i += 1
        }
        return out
    }

    /// `else`, `catch` or `finally` right after a closing brace, as a whole word.
    private static func continuesBlock(_ rest: ArraySlice<Character>) -> Bool {
        let text = String(rest)
        return ["else", "catch", "finally"].contains { word in
            guard text.hasPrefix(word) else { return false }
            guard let after = text.dropFirst(word.count).first else { return true }
            return !(after.isLetter || after.isNumber || after == "_" || after == "$")
        }
    }
}
