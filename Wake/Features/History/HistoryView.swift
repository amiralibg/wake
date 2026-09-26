import SwiftUI

/// The library's History section: pages you visited, or things you searched for,
/// newest first and grouped by day.
struct HistoryContent: View {
    enum Kind { case pages, searches }

    let kind: Kind

    @Environment(BrowserModel.self) private var browser
    @State private var query = ""
    @State private var limit = Self.pageSize
    @State private var confirmsClear = false
    @FocusState private var searchFocused: Bool

    private static let pageSize = 400
    private var store: HistoryStore { .shared }

    var body: some View {
        _ = store.version
        let now = Date.now
        return VStack(spacing: 0) {
            header
            switch kind {
            case .pages:
                let visits = store.visits(matching: query, limit: limit)
                if visits.isEmpty {
                    empty
                } else {
                    list(days: Self.days(visits, date: \.visitedAt, now: now), more: visits.count == limit) { visit in
                        VisitRow(visit: visit) { browser.openFromLibrary(visit.url) }
                    }
                }
            case .searches:
                let searches = store.searches(matching: query, limit: limit)
                if searches.isEmpty {
                    empty
                } else {
                    list(days: Self.days(searches, date: \.searchedAt, now: now), more: searches.count == limit) { search in
                        SearchRow(search: search) { browser.openFromLibrary(search.url) }
                    }
                }
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: query) { limit = Self.pageSize }
        .confirmationDialog(kind == .pages ? "Clear all history?" : "Clear all searches?", isPresented: $confirmsClear) {
            Button("Clear", role: .destructive) { kind == .pages ? store.clearAll() : store.clearSearches() }
        } message: {
            Text(kind == .pages ? "Forgets every visited page and search. Threads, moments and pinned apps stay." : "Forgets what you searched for. Visited pages stay.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(kind == .pages ? "History" : "Searches")
                    .font(.system(size: 17, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(kind == .pages ? "Search titles and addresses" : "Search what you searched for", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 300, height: 30)
            .background(.primary.opacity(0.07), in: .rect(cornerRadius: 8, style: .continuous))
            Menu {
                Button("Import from Another Browser…") { browser.isImportingBrowserData = true }
                Divider()
                Button(kind == .pages ? "Clear History…" : "Clear Searches…", role: .destructive) { confirmsClear = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Import and clear")
        }
        .padding(.horizontal, 24)
        .frame(height: 60)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var subtitle: String {
        let count = kind == .pages ? store.visitCount : store.searchCount
        let noun = kind == .pages ? "page" : "search"
        let total = "\(count.formatted()) \(noun)\(count == 1 ? "" : (kind == .pages ? "s" : "es"))"
        return query.isEmpty ? total : "Searching \(total)"
    }

    // MARK: List

    private func list<Item: Identifiable, Row: View>(days: [Day<Item>], more: Bool, @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(days) { day in
                    Section {
                        ForEach(day.items) { item in row(item) }
                    } header: {
                        Text(day.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Pinned: opaque, so rows scrolling underneath don't show through.
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
                if more {
                    Button("Show More") { limit += Self.pageSize }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? (kind == .pages ? "clock.arrow.circlepath" : "magnifyingglass") : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? (kind == .pages ? "No history yet" : "No searches yet") : "Nothing matches")
                .font(.system(size: 15, weight: .semibold))
            Text(query.isEmpty
                 ? (kind == .pages ? "Pages you visit appear here, newest first." : "Searches from ⌘K and from any search engine's own box appear here.")
                 : "Try fewer words, or part of the address.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if query.isEmpty {
                Button("Import from Another Browser…") { browser.isImportingBrowserData = true }
                    .buttonStyle(.borderless)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Days

    struct Day<Item: Identifiable>: Identifiable {
        let id: Date
        let title: String
        let items: [Item]
    }

    private static func days<Item: Identifiable>(_ items: [Item], date: KeyPath<Item, Date>, now: Date) -> [Day<Item>] {
        let calendar = Calendar.current
        var days: [Day<Item>] = []
        var current: (start: Date, items: [Item])?
        for item in items {
            let start = calendar.startOfDay(for: item[keyPath: date])
            if current?.start != start {
                if let current { days.append(Day(id: current.start, title: title(for: current.start, now: now), items: current.items)) }
                current = (start, [])
            }
            current?.items.append(item)
        }
        if let current { days.append(Day(id: current.start, title: title(for: current.start, now: now), items: current.items)) }
        return days
    }

    private static func title(for day: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return day.formatted(sameYear ? .dateTime.weekday(.wide).day().month(.wide) : .dateTime.weekday(.wide).day().month(.wide).year())
    }
}

// MARK: Rows

private struct VisitRow: View {
    let visit: VisitRecord
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        let host = visit.url.host() ?? visit.url.absoluteString
        HistoryRowChrome(isHovering: isHovering, action: open) {
            Favicon(url: URL(string: "https://\(host)/favicon.ico"), host: host, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(visit.title.isEmpty ? host : visit.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(Self.displayAddress(visit.url))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            SourceBadge(source: visit.source)
            Text(visit.visitedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open") { open() }
            Button("Copy Link") { copy(visit.url.absoluteString) }
            Divider()
            Button("Remove from History", role: .destructive) { HistoryStore.shared.delete(visit) }
        }
        .help(visit.url.absoluteString)
    }

    static func displayAddress(_ url: URL) -> String {
        var text = url.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        return text
    }
}

private struct SearchRow: View {
    let search: SearchRecord
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        HistoryRowChrome(isHovering: isHovering, action: open) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(.primary.opacity(0.07), in: .rect(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(search.query)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(search.engine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            SourceBadge(source: search.source)
            Text(search.searchedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Search Again") { open() }
            Button("Copy Search") { copy(search.query) }
            Divider()
            Button("Remove from Searches", role: .destructive) { HistoryStore.shared.delete(search) }
        }
    }
}

/// A full-width row button with a hover wash, like the palette's rows.
private struct HistoryRowChrome<Content: View>: View {
    let isHovering: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovering ? AnyShapeStyle(.primary.opacity(0.06)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// "Chrome", "Firefox"… on imported entries.
private struct SourceBadge: View {
    let source: String?

    var body: some View {
        if let source {
            Text(source)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.primary.opacity(0.06), in: .capsule)
        }
    }
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
