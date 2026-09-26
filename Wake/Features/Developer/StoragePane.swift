import SwiftUI

/// What the page keeps on this Mac: local and session storage, cookies, IndexedDB
/// databases, Cache Storage and service workers. Everything can be edited or cleared.
///
/// Limitation: IndexedDB contents can't be listed from outside the page without
/// knowing its schema, so databases are listed by name and version and can be deleted.
struct StoragePane: View {
    let page: BrowserPage
    @State private var kind: Kind = .local
    @State private var confirmsClear = false

    enum Kind: String, CaseIterable, Identifiable {
        case local = "Local", session = "Session", cookies = "Cookies"
        case indexedDB = "IndexedDB", caches = "Caches", workers = "Workers"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .local: "internaldrive"
            case .session: "clock"
            case .cookies: "birthday.cake"
            case .indexedDB: "cylinder"
            case .caches: "archivebox"
            case .workers: "gearshape.2"
            }
        }
    }

    private var session: DevToolsSession { page.inspector }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: Binding(get: { kind }, set: { if let value = $0 { kind = value } })) {
                    ForEach(Kind.allCases) { kind in
                        Label {
                            HStack {
                                Text(kind.rawValue)
                                Spacer()
                                Text("\(count(kind))").foregroundStyle(.secondary).monospacedDigit()
                            }
                        } icon: { Image(systemName: kind.symbol).foregroundStyle(.secondary) }
                        .tag(kind)
                    }
                }
                .listStyle(.sidebar)
                .font(.system(size: 11.5))
                Divider()
                Button("Clear Site Data…") { confirmsClear = true }
                    .controlSize(.small)
                    .padding(8)
            }
            .frame(minWidth: 130, idealWidth: 150, maxWidth: 190)
            content
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: session.documentLoads) { await session.loadStorage() }
        .confirmationDialog("Clear everything \(page.host) stores?", isPresented: $confirmsClear) {
            Button("Clear and Reload", role: .destructive) { Task { await session.clearSiteData() } }
        } message: {
            Text("Cookies, storage, caches, databases and service workers for this site. You'll be signed out.")
        }
    }

    private func count(_ kind: Kind) -> Int {
        switch kind {
        case .local: session.localItems.count
        case .session: session.sessionItems.count
        case .cookies: session.cookies.count
        case .indexedDB: session.asyncStorage.databases.count
        case .caches: session.asyncStorage.caches.count
        case .workers: session.asyncStorage.workers.count
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .local: KeyValueTable(session: session, kind: "local", items: session.localItems)
        case .session: KeyValueTable(session: session, kind: "session", items: session.sessionItems)
        case .cookies: CookiesTable(session: session)
        case .indexedDB:
            VStack(spacing: 0) {
                if let name = session.blockedDatabase {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text("“\(name)” is open in the page, so WebKit deletes it once the page closes it.")
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button("Reload to Finish") {
                            session.blockedDatabase = nil
                            page.reload()
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(.yellow.opacity(0.08))
                    Divider()
                }
                SimpleList(empty: "No IndexedDB databases", rows: session.asyncStorage.databases.map { ($0.name, "version \($0.version)") }) { name in
                    Task { await session.deleteDatabase(name) }
                }
            }
        case .caches:
            SimpleList(empty: "No caches", rows: session.asyncStorage.caches.map { ($0.name, "\($0.count) \($0.count == 1 ? "entry" : "entries")") }) { name in
                Task { await session.deleteCache(name) }
            }
        case .workers:
            SimpleList(empty: "No service workers", rows: session.asyncStorage.workers.map { ($0.scope, "\($0.state) · \($0.script)") }, actionTitle: "Unregister") { scope in
                Task { await session.unregisterWorker(scope) }
            }
        }
    }
}

private struct KeyValueTable: View {
    let session: DevToolsSession
    let kind: String
    let items: [DevToolsSession.StorageItem]

    @State private var selection: DevToolsSession.StorageItem.ID?
    @State private var editing: Edit?
    @State private var filter = ""

    struct Edit: Identifiable {
        var id: String { originalKey ?? "new" }
        let originalKey: String?
        var key: String
        var value: String
    }

    var body: some View {
        let query = filter.trimmingCharacters(in: .whitespaces)
        let rows = items.filter { query.isEmpty || $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query) }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                DevToolsSearchField(text: $filter, prompt: "Filter")
                Button { editing = Edit(originalKey: nil, key: "", value: "") } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Add item")
                Button { if let selection { Task { await session.removeStorage(kind, key: selection) } } } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless).disabled(selection == nil).help("Delete selected")
                Button { Task { await session.loadStorage() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh")
                Button("Clear") { Task { await session.clearStorage(kind) } }
                    .disabled(items.isEmpty)
            }
            .controlSize(.small)
            .padding(8)
            Table(rows, selection: $selection) {
                TableColumn("Key") { Text($0.key).font(.system(size: 11, design: .monospaced)).lineLimit(1) }
                    .width(min: 60, ideal: 110)
                TableColumn("Value") { Text($0.value).font(.system(size: 11, design: .monospaced)).lineLimit(1) }
                    .width(min: 60, ideal: 140)
                TableColumn("Size") { Text(Self.size($0.length)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary) }
                    .width(min: 40, ideal: 48, max: 64)
            }
            .contextMenu(forSelectionType: DevToolsSession.StorageItem.ID.self) { keys in
                if let key = keys.first, let item = items.first(where: { $0.key == key }) {
                    Button("Edit…") { editing = Edit(originalKey: key, key: key, value: item.value) }
                    Button("Copy Value") { copy(item.value) }
                    Divider()
                    Button("Delete", role: .destructive) { Task { await session.removeStorage(kind, key: key) } }
                }
            } primaryAction: { keys in
                if let key = keys.first, let item = items.first(where: { $0.key == key }) {
                    editing = Edit(originalKey: key, key: key, value: item.value)
                }
            }
            if let selection, let item = items.first(where: { $0.key == selection }) {
                Divider()
                ScrollView {
                    Text(JSONFormatter.pretty(item.value))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 140)
            }
        }
        .sheet(item: $editing) { edit in
            ValueEditor(title: edit.originalKey == nil ? "Add Item" : "Edit Item", key: edit.key, value: edit.value) { key, value in
                Task {
                    if let original = edit.originalKey, original != key { await session.removeStorage(kind, key: original) }
                    await session.setStorage(kind, key: key, value: value)
                }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// "21 B", "4.2 KB": short enough for a narrow column.
    static func size(_ length: Int) -> String {
        length < 1024 ? "\(length) B" : ByteCountFormatter.string(fromByteCount: Int64(length), countStyle: .memory)
    }
}

private struct CookiesTable: View {
    let session: DevToolsSession
    @State private var selection: String?
    @State private var editing: HTTPCookie?
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(session.cookies.count) cookies").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { adding = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Add cookie")
                Button { if let cookie = selected { Task { await session.deleteCookie(cookie) } } } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless).disabled(selected == nil).help("Delete selected")
                Button { Task { await session.loadCookies() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh")
                Button("Clear") { Task { await session.clearCookies() } }
                    .disabled(session.cookies.isEmpty)
            }
            .controlSize(.small)
            .padding(8)
            Table(session.cookies, selection: $selection) {
                TableColumn("Name") { Text($0.name).font(.system(size: 11, design: .monospaced)) }.width(min: 70, ideal: 120)
                TableColumn("Value") { Text($0.value).font(.system(size: 11, design: .monospaced)).lineLimit(1) }
                TableColumn("Domain") { Text($0.domain).font(.system(size: 10.5)) }.width(min: 60, ideal: 110)
                TableColumn("Path") { Text($0.path).font(.system(size: 10.5)) }.width(40)
                TableColumn("Expires") { cookie in
                    Text(cookie.expiresDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Session").font(.system(size: 10.5))
                }
                .width(min: 60, ideal: 110)
                TableColumn("Flags") { cookie in
                    Text([cookie.isHTTPOnly ? "HttpOnly" : nil, cookie.isSecure ? "Secure" : nil, cookie.sameSitePolicy?.rawValue].compactMap { $0 }.joined(separator: " "))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 110)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let cookie = session.cookies.first(where: { ids.contains($0.id) }) {
                    Button("Edit…") { editing = cookie }
                    Button("Copy Value") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cookie.value, forType: .string)
                    }
                    Divider()
                    Button("Delete", role: .destructive) { Task { await session.deleteCookie(cookie) } }
                }
            } primaryAction: { ids in
                editing = session.cookies.first { ids.contains($0.id) }
            }
        }
        .sheet(item: $editing) { cookie in
            ValueEditor(title: "Edit Cookie", key: cookie.name, value: cookie.value) { name, value in
                Task { await session.setCookie(name: name, value: value, replacing: cookie) }
            }
        }
        .sheet(isPresented: $adding) {
            ValueEditor(title: "Add Cookie", key: "", value: "") { name, value in
                Task { await session.setCookie(name: name, value: value, replacing: nil) }
            }
        }
    }

    private var selected: HTTPCookie? { session.cookies.first { $0.id == selection } }
}

extension HTTPCookie: @retroactive Identifiable {
    public var id: String { "\(domain)|\(path)|\(name)" }
}

private struct SimpleList: View {
    let empty: String
    let rows: [(String, String)]
    var actionTitle = "Delete"
    let onAction: (String) -> Void

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(empty, systemImage: "tray").frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(rows, id: \.0) { name, detail in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
                            Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(actionTitle, role: .destructive) { onAction(name) }.controlSize(.small)
                    }
                }
            }
        }
    }
}

private struct ValueEditor: View {
    let title: String
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key: String
    @State private var value: String

    init(title: String, key: String, value: String, onSave: @escaping (String, String) -> Void) {
        self.title = title
        self.onSave = onSave
        _key = State(initialValue: key)
        _value = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Name", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
            CodeTextEditor(text: $value)
                .frame(minWidth: 460, minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            HStack {
                Button("Format JSON") { value = JSONFormatter.pretty(value) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(key.trimmingCharacters(in: .whitespaces), value)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}
