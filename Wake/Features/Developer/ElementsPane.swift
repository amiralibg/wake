import AppKit
import SwiftUI

/// The page's live DOM as a tree, with a picker, search, editing, and the selected
/// element's styles, computed values, box model and attributes.
struct ElementsPane: View {
    let page: BrowserPage
    @State private var search = ""
    @State private var searchedFor = ""
    @State private var htmlEditor: HTMLEdit?

    private var session: DevToolsSession { page.inspector }

    struct HTMLEdit: Identifiable {
        let id: Int
        var html: String
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            VSplitView {
                ElementTree(session: session, onEditHTML: editHTML)
                    .frame(minHeight: 120, maxHeight: .infinity)
                ElementDetailsView(session: session, onEditHTML: editHTML)
                    .frame(minHeight: 140, idealHeight: 280, maxHeight: .infinity)
            }
            if let details = session.details {
                Divider()
                Breadcrumbs(session: session, path: details.path)
            }
        }
        .task(id: session.documentLoads) {
            if session.roots.isEmpty { await session.loadDocument() }
        }
        .onDisappear {
            session.hover(nil)
            if session.isPicking { session.setPicking(false) }
        }
        .sheet(item: $htmlEditor) { edit in
            HTMLEditor(edit: edit) { html in
                Task { await session.setOuterHTML(html, on: edit.id) }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                session.setPicking(!session.isPicking)
            } label: {
                Image(systemName: "cursorarrow.rays")
                    .foregroundStyle(session.isPicking ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .buttonStyle(.borderless)
            .help("Select an element in the page (Esc to cancel)")
            Button {
                Task { await session.refreshTree() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh the tree")
            DevToolsSearchField(text: $search, prompt: "Search by selector or text", onSubmit: {
                // Return again on the same query steps to the next match, like Safari.
                if search == searchedFor, !session.searchMatches.isEmpty {
                    Task { await session.nextMatch(NSEvent.modifierFlags.contains(.shift) ? -1 : 1) }
                } else {
                    searchedFor = search
                    Task { await session.search(search) }
                }
            }, onStep: { delta in Task { await session.nextMatch(delta) } })
            if !session.searchMatches.isEmpty {
                Text("\(session.searchIndex + 1) of \(session.searchMatches.count)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Button { Task { await session.nextMatch(-1) } } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                Button { Task { await session.nextMatch(1) } } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
            }
        }
        .controlSize(.small)
        .font(.system(size: 11))
        .padding(8)
    }

    private func editHTML(_ id: Int) {
        Task {
            let html = await session.outerHTML(id)
            htmlEditor = HTMLEdit(id: id, html: html)
        }
    }
}

// MARK: Tree

private struct ElementTree: View {
    let session: DevToolsSession
    let onEditHTML: (Int) -> Void

    @FocusState private var isFocused: Bool
    @State private var viewportWidth: CGFloat = 300

    var body: some View {
        let rows = session.treeRows
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        ElementRow(row: row, session: session, isSelected: !row.isClosing && row.node.id == session.selectedID, minWidth: viewportWidth) { isFocused = true }
                            .id(row.id)
                            .contextMenu { if !row.isClosing { ElementMenu(node: row.node, session: session, onEditHTML: onEditHTML) } }
                    }
                }
                .padding(.vertical, 4)
                .frame(minWidth: viewportWidth, alignment: .leading)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = max(300, $0) }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            // Keys read the session live (not the rows captured at render time), so
            // presses that land before SwiftUI re-renders still step from the latest row.
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.rightArrow) {
                guard let id = session.selectedID else { return .ignored }
                if session.expanded.contains(id) {
                    // Like Safari: → on an open element steps into its first child.
                    if let child = session.children[id]?.first { session.choose(child.id) }
                } else {
                    Task { await session.expand(id) }
                }
                return .handled
            }
            .onKeyPress(.leftArrow) {
                guard let id = session.selectedID else { return .ignored }
                if session.expanded.contains(id) {
                    session.expanded.remove(id)
                } else if let parent = session.parentID(of: id) {
                    session.choose(parent)
                }
                return .handled
            }
            // ⌫ (and Edit ▸ Delete). `onKeyPress(.delete)` never fires for the Delete
            // key on macOS: AppKit reports it as U+007F, not SwiftUI's `.delete`.
            .onDeleteCommand {
                guard let id = session.selectedID else { return }
                Task { await session.remove(id) }
            }
            .onChange(of: session.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.hover) { proxy.scrollTo("\(id)", anchor: .center) }
            }
            .onHover { inside in if !inside { session.hover(nil) } }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let openRows = session.treeRows.filter { !$0.isClosing }
        guard let current = openRows.firstIndex(where: { $0.node.id == session.selectedID }) else { return .ignored }
        let next = min(max(0, current + delta), openRows.count - 1)
        session.choose(openRows[next].node.id)
        return .handled
    }
}

private struct ElementRow: View {
    let row: DevToolsSession.TreeRow
    let session: DevToolsSession
    let isSelected: Bool
    /// The pane's width: a horizontal scroll view offers rows no width, so the
    /// selection band would otherwise stop at the end of the text.
    var minWidth: CGFloat = 0
    var onActivate: () -> Void = {}

    var body: some View {
        let node = row.node
        HStack(spacing: 2) {
            Group {
                if !row.isClosing && node.isExpandable {
                    Button {
                        Task { await session.toggle(node.id, recursive: NSEvent.modifierFlags.contains(.option)) }
                    } label: {
                        Image(systemName: session.expanded.contains(node.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 16)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("⌥-click to expand everything inside")
                } else {
                    Color.clear.frame(width: 12, height: 16)
                }
            }
            MarkupText.render(node, closing: row.isClosing, collapsed: !session.expanded.contains(node.id))
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, CGFloat(row.depth) * 14 + 6)
        .padding(.trailing, 12)
        .frame(height: 19)
        .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(session.hoveredID == node.id ? AnyShapeStyle(.primary.opacity(0.06)) : AnyShapeStyle(.clear)))
        .contentShape(.rect)
        .onTapGesture(count: 2) { if node.isExpandable { Task { await session.toggle(node.id) } } }
        .onTapGesture {
            onActivate()
            session.choose(node.id)
        }
        .onHover { inside in if inside { session.hover(node.id) } }
    }
}

/// Safari-style markup colouring for one tree row.
enum MarkupText {
    static let tag = Color(nsColor: .systemPink)
    static let attributeName = Color(nsColor: .systemOrange)
    static let attributeValue = Color(nsColor: .systemBlue)
    static let comment = Color(nsColor: .systemGreen)

    static func render(_ node: DevToolsSession.DOMNode, closing: Bool, collapsed: Bool) -> Text {
        switch node.type {
        case 1:
            let name = node.tag ?? ""
            if closing { return Text("</\(name)>").foregroundColor(tag) }
            var text = Text("<\(name)").foregroundColor(tag)
            for attribute in node.attributes {
                text = text + Text(" \(attribute.name)").foregroundColor(attributeName)
                if !attribute.value.isEmpty {
                    let value = attribute.value.count > 120 ? attribute.value.prefix(120) + "…" : Substring(attribute.value)
                    text = text + Text("=\"").foregroundColor(.secondary) + Text(String(value)).foregroundColor(attributeValue) + Text("\"").foregroundColor(.secondary)
                }
            }
            text = text + Text(">").foregroundColor(tag)
            if let inline = node.text {
                return text + Text(inline) + Text("</\(name)>").foregroundColor(tag)
            }
            if node.isExpandable, collapsed {
                return text + Text("…").foregroundColor(.secondary) + Text("</\(name)>").foregroundColor(tag)
            }
            if !node.isExpandable, !voidElements.contains(name) {
                return text + Text("</\(name)>").foregroundColor(tag)
            }
            return text
        case 3:
            return Text("\"\(node.text ?? "")\"")
        case 8:
            return Text("<!-- \(node.text ?? "") -->").foregroundColor(comment)
        case 10:
            return Text("<!DOCTYPE \(node.text ?? "html")>").foregroundColor(.secondary)
        case 11:
            return Text("#shadow-root (\(node.text ?? "open"))").foregroundColor(.secondary)
        default:
            return Text(node.text ?? "")
        }
    }

    private static let voidElements: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]
}

private struct ElementMenu: View {
    let node: DevToolsSession.DOMNode
    let session: DevToolsSession
    let onEditHTML: (Int) -> Void

    var body: some View {
        if node.isElement {
            Button("Edit as HTML…") { onEditHTML(node.id) }
            Button("Add Attribute") { Task { await session.setAttribute("data-new", value: "", on: node.id) } }
            Divider()
            Button("Copy Selector") {
                Task {
                    await session.select(node.id, highlight: false)
                    copy(session.details?.selector ?? "")
                }
            }
            Button("Copy HTML") { Task { copy(await session.outerHTML(node.id)) } }
            Divider()
            Button("Scroll into View") { Task { await session.scrollIntoView(node.id) } }
            Button("Hide / Show Element") { Task { await session.toggleHidden(node.id) } }
            Button("Duplicate Element") { Task { await session.duplicate(node.id) } }
            Divider()
            Button("Expand All") { Task { await session.toggle(node.id, recursive: true) } }
            Button("Collapse") { session.expanded.remove(node.id) }
            Divider()
        }
        Button("Delete Node", role: .destructive) { Task { await session.remove(node.id) } }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct Breadcrumbs: View {
    let session: DevToolsSession
    let path: [Int]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(path.enumerated()), id: \.element) { index, id in
                        if index > 0 {
                            Image(systemName: "chevron.compact.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Button(session.node(id)?.label ?? "…") { Task { await session.reveal(id, path: Array(path.prefix(index + 1))) } }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: id == session.selectedID ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(id == session.selectedID ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .id(id)
                            .onHover { inside in session.hover(inside ? id : nil) }
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 24)
            .onAppear { if let last = path.last { proxy.scrollTo(last, anchor: .trailing) } }
            .onChange(of: path) { _, path in if let last = path.last { proxy.scrollTo(last, anchor: .trailing) } }
        }
    }
}

// MARK: Details

private struct ElementDetailsView: View {
    let session: DevToolsSession
    let onEditHTML: (Int) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case styles = "Styles", computed = "Computed", layout = "Layout", attributes = "Attributes"
        var id: Self { self }
    }

    @AppStorage("devtools.elements.detailTab") private var tab: Tab = .styles

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                if let details = session.details {
                    Text(details.node?.label ?? "")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button { onEditHTML(details.id) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .help("Edit as HTML")
                }
            }
            .controlSize(.small)
            .padding(8)
            Divider()
            if let details = session.details, details.node?.isElement == true {
                switch tab {
                case .styles: StylesView(session: session, details: details)
                case .computed: ComputedView(details: details)
                case .layout: ScrollView { BoxModelView(details: details).padding(12) }
                case .attributes: AttributesView(session: session, details: details)
                }
            } else {
                ContentUnavailableView("No element selected", systemImage: "cursorarrow.click",
                                       description: Text("Select a node in the tree, or pick one in the page."))
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct StylesView: View {
    let session: DevToolsSession
    let details: DevToolsSession.ElementDetails
    @State private var inline = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("element.style").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    TextField("color: red; margin: 0 auto", text: $inline, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1...6)
                        .onSubmit { Task { await session.setInlineStyle(inline, on: details.id) } }
                    Text("↩ applies to the page right away.").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                ForEach(details.rules) { rule in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(rule.selector)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Text(rule.source).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        if let media = rule.media {
                            Text("@media \(media)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        ForEach(Array(rule.declarations.enumerated()), id: \.offset) { _, declaration in
                            (Text(declaration.0).foregroundColor(MarkupText.attributeName) + Text(": ") + Text(declaration.1) + Text(";"))
                                .font(.system(size: 11, design: .monospaced))
                                .padding(.leading, 12)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.035), in: .rect(cornerRadius: 6, style: .continuous))
                }
                if details.rules.isEmpty {
                    Text("No matching rules in readable stylesheets. Cross-origin sheets can't be read from the page.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(10)
        }
        .onAppear { inline = details.inlineStyle }
        .onChange(of: details.id) { inline = details.inlineStyle }
    }
}

private struct ComputedView: View {
    let details: DevToolsSession.ElementDetails
    @State private var filter = ""
    @AppStorage("devtools.elements.computedAll") private var showsAll = false

    /// Values that are just the initial ones make the list long and tell you little.
    private static let boring: Set<String> = ["auto", "normal", "none", "0px", "initial", "0", "visible", "static", "baseline", "start"]

    var body: some View {
        let query = filter.trimmingCharacters(in: .whitespaces)
        let rows = details.computed.filter { name, value in
            (query.isEmpty || name.localizedCaseInsensitiveContains(query) || value.localizedCaseInsensitiveContains(query))
                && (showsAll || !query.isEmpty || !Self.boring.contains(value))
        }
        VStack(spacing: 0) {
            HStack {
                DevToolsSearchField(text: $filter, prompt: "Filter properties")
                Toggle("Show all", isOn: $showsAll).toggleStyle(.checkbox).font(.system(size: 11))
            }
            .controlSize(.small)
            .padding(8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.0) { name, value in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(name).foregroundStyle(MarkupText.attributeName).frame(width: 190, alignment: .leading)
                            if let color = CSSColor.parse(value) {
                                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.primary.opacity(0.2), lineWidth: 0.5))
                            }
                            Text(value).textSelection(.enabled)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 18)
                    }
                }
            }
        }
    }
}

/// The margin, border, padding and content boxes, with their sizes, as in Safari.
private struct BoxModelView: View {
    let details: DevToolsSession.ElementDetails

    var body: some View {
        if let box = details.box {
            VStack(spacing: 12) {
                layer("margin", box.margin, color: Color(red: 0.96, green: 0.70, blue: 0.42)) {
                    layer("border", box.border, color: Color(red: 1, green: 0.9, blue: 0.6)) {
                        layer("padding", box.padding, color: Color(red: 0.58, green: 0.77, blue: 0.49)) {
                            Text("\(format(contentWidth(box))) × \(format(contentHeight(box)))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.black.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(red: 0.44, green: 0.66, blue: 0.86))
                        }
                    }
                }
                .frame(maxWidth: 420)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { label("Position"); value(box.position) }
                    GridRow { label("Display"); value(box.display) }
                    GridRow { label("Box sizing"); value(box.boxSizing) }
                    GridRow { label("Rendered size"); value("\(format(box.width)) × \(format(box.height))") }
                    GridRow { label("Page offset"); value("x \(format(box.x)), y \(format(box.y))") }
                }
            }
        }
    }

    private func layer<Content: View>(_ name: String, _ sides: [Double], color: Color, @ViewBuilder content: () -> Content) -> some View {
        let s = sides.count == 4 ? sides : [0, 0, 0, 0]
        return VStack(spacing: 2) {
            HStack {
                Text(name).font(.system(size: 9)).foregroundStyle(.black.opacity(0.6))
                Spacer()
            }
            Text(format(s[0])).font(.system(size: 10, design: .monospaced))
            HStack(spacing: 6) {
                Text(format(s[3])).font(.system(size: 10, design: .monospaced))
                content()
                Text(format(s[1])).font(.system(size: 10, design: .monospaced))
            }
            Text(format(s[2])).font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(.black.opacity(0.8))
        .padding(6)
        .background(color)
        .overlay(Rectangle().stroke(.black.opacity(0.25), style: StrokeStyle(lineWidth: 0.5, dash: [3])))
    }

    private func contentWidth(_ box: DevToolsSession.ElementDetails.Box) -> Double {
        box.width - (box.border[safe: 1] + box.border[safe: 3] + box.padding[safe: 1] + box.padding[safe: 3])
    }

    private func contentHeight(_ box: DevToolsSession.ElementDetails.Box) -> Double {
        box.height - (box.border[safe: 0] + box.border[safe: 2] + box.padding[safe: 0] + box.padding[safe: 2])
    }

    private func format(_ value: Double) -> String {
        value == 0 ? "–" : (value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private func value(_ text: String) -> some View {
        Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
    }
}

private struct AttributesView: View {
    let session: DevToolsSession
    let details: DevToolsSession.ElementDetails
    @State private var newName = ""
    @State private var newValue = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(details.node?.attributes ?? [], id: \.name) { attribute in
                    AttributeField(attribute: attribute) { value in
                        Task { await session.setAttribute(attribute.name, value: value, on: details.id) }
                    } onRemove: {
                        Task { await session.removeAttribute(attribute.name, from: details.id) }
                    }
                }
                Divider().padding(.vertical, 4)
                HStack(spacing: 6) {
                    TextField("name", text: $newName).frame(width: 110)
                    TextField("value", text: $newValue).onSubmit(add)
                    Button("Add", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .controlSize(.small)
                if !details.selector.isEmpty {
                    DetailSection(title: "Selector", rows: [("CSS", details.selector)])
                        .padding(.top, 8)
                }
            }
            .padding(10)
        }
    }

    private func add() {
        // Copy before clearing: the Task body runs after the fields are reset.
        let name = newName.trimmingCharacters(in: .whitespaces)
        let value = newValue
        guard !name.isEmpty else { return }
        Task { await session.setAttribute(name, value: value, on: details.id) }
        newName = ""
        newValue = ""
    }
}

private struct AttributeField: View {
    let attribute: DevToolsSession.DOMNode.Attribute
    let onCommit: (String) -> Void
    let onRemove: () -> Void
    @State private var value = ""

    var body: some View {
        HStack(spacing: 6) {
            Text(attribute.name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(MarkupText.attributeName)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            TextField("", text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .controlSize(.small)
                .onSubmit { onCommit(value) }
            Button(action: onRemove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove attribute")
        }
        .onAppear { value = attribute.value }
        .onChange(of: attribute.value) { value = attribute.value }
    }
}

private struct HTMLEditor: View {
    let edit: ElementsPane.HTMLEdit
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var html = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit as HTML").font(.headline)
            CodeTextEditor(text: $html)
                .frame(minWidth: 560, minHeight: 320)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            HStack {
                Text("Replaces the element in the page. Reload to undo.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    onSave(html)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear { html = edit.html }
    }
}

/// Swatches for `rgb()`/`rgba()` values in Computed, and the hex values custom
/// properties keep as written (`--accent: #2997ff`).
enum CSSColor {
    static func parse(_ value: String) -> Color? {
        let value = value.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { return hex(value.dropFirst()) }
        guard value.hasPrefix("rgb"), let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")") else { return nil }
        let parts = value[value.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        return Color(.sRGB, red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, opacity: parts.count > 3 ? parts[3] : 1)
    }

    /// `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa`.
    private static func hex(_ digits: Substring) -> Color? {
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        let pairs = digits.count <= 4 ? digits.map { "\($0)\($0)" } : stride(from: 0, to: digits.count, by: 2).map {
            String(digits.dropFirst($0).prefix(2))
        }
        let values = pairs.compactMap { UInt8($0, radix: 16) }.map { Double($0) / 255 }
        guard values.count >= 3 else { return nil }
        return Color(.sRGB, red: values[0], green: values[1], blue: values[2], opacity: values.count > 3 ? values[3] : 1)
    }
}

extension Array where Element == Double {
    subscript(safe index: Int) -> Double { indices.contains(index) ? self[index] : 0 }
}
