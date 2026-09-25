import SwiftUI

/// Moments, Finder-style, over the whole window: a vibrancy sidebar of smart shelves
/// and resolved threads, and a content pane with search and a card grid or timeline.
struct MomentsLibrary: View {
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        ZStack {
            if browser.isMomentsOpen {
                LibraryWindow()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .animation(.chrome, value: browser.isMomentsOpen)
    }
}

private struct LibraryWindow: View {
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        HStack(spacing: 0) {
            MomentsSidebar()
                .frame(width: 232)
            Group {
                if case .resolvedThread(let id) = browser.momentsShelf {
                    ResolvedThreadDetail(threadID: id)
                } else {
                    MomentsContent()
                }
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 0.5))
            .padding([.vertical, .trailing], 8)
        }
        .background(WindowBackdrop())
        // Keeps clicks and scrolls from reaching the trail underneath.
        .contentShape(.rect)
    }
}

// MARK: Content

private struct MomentsContent: View {
    @Environment(BrowserModel.self) private var browser
    @Environment(MomentStore.self) private var store
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var browser = browser
        let now = Date.now
        let host = browser.momentsHost
        let tokens = MomentSearch.tokens(browser.momentsQuery)
        let results = results(tokens: tokens, host: host, now: now)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tokens.isEmpty ? browser.momentsShelf.title : "Search")
                        .font(.system(size: 17, weight: .bold))
                    Text(subtitle(count: results.count, host: host, searching: !tokens.isEmpty))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Search moments", text: $browser.momentsQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($searchFocused)
                    if !browser.momentsQuery.isEmpty {
                        Button {
                            browser.momentsQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(width: 300, height: 30)
                .background(.primary.opacity(0.07), in: .rect(cornerRadius: 8, style: .continuous))
                Picker("Layout", selection: $browser.momentsLayout) {
                    Image(systemName: "square.grid.2x2").tag(MomentsLayout.grid).help("Grid")
                    Image(systemName: "list.bullet").tag(MomentsLayout.timeline).help("Timeline")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 24)
            .frame(height: 60)
            .overlay(alignment: .bottom) { Divider() }

            if results.isEmpty {
                EmptyShelf(shelf: browser.momentsShelf, searching: !tokens.isEmpty)
            } else {
                ScrollView {
                    switch browser.momentsLayout {
                    case .grid:
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 18)], spacing: 18) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, moment in
                                MomentCard(
                                    moment: moment,
                                    status: MomentStatus.of(moment, host: host, now: now),
                                    isBestMatch: !tokens.isEmpty && index == 0
                                ) { browser.openMoment(moment) }
                                .contextMenu { MomentMenu(moment: moment) }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                    case .timeline:
                        MomentTimeline(moments: results, host: host, now: now, groupsByDay: tokens.isEmpty)
                    }
                }
            }
        }
        .onAppear { searchFocused = true }
    }

    private func results(tokens: [String], host: String?, now: Date) -> [MomentRecord] {
        _ = store.version
        if tokens.isEmpty {
            let all = store.moments(includingArchived: browser.momentsShelf == .archived)
            return all.filter { browser.momentsShelf.contains($0, host: host, now: now) }
        }
        // Search looks everywhere, archive included, best first.
        return store.moments(includingArchived: true)
            .map { ($0, MomentSearch.score($0, tokens: tokens)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.createdAt > $1.0.createdAt }
            .map(\.0)
    }

    private func subtitle(count: Int, host: String?, searching: Bool) -> String {
        let moments = "\(count) moment\(count == 1 ? "" : "s")"
        if searching { return moments }
        switch browser.momentsShelf {
        case .relevant: return host.map { "\(moments) on \($0)" } ?? "Open a page to see moments saved on its site"
        case .fading: return "\(moments) · unopened for a month; archived after \(Int(MomentRules.archiveAfter / 86_400)) days"
        case .changed: return "\(moments) · checked in the background while Wake is open"
        default: return moments
        }
    }
}

private struct EmptyShelf: View {
    let shelf: MomentShelf
    let searching: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: searching ? "magnifyingglass" : shelf.symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searching ? "No moments match" : emptyTitle)
                .font(.system(size: 15, weight: .semibold))
            Text(searching ? "Search looks at titles, your notes, highlights, sites and page text." : emptyDetail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch shelf {
        case .everything: "No moments yet"
        case .relevant: "Nothing saved on this site"
        case .resurfacing: "Nothing resurfacing today"
        case .changed: "No saved page has changed"
        case .fading: "Nothing is fading"
        case .archived: "The archive is empty"
        case .resolvedThread: ""
        }
    }

    private var emptyDetail: String {
        switch shelf {
        case .everything: "Press ⌘D on any page to save a moment: where you were, what you selected, and why."
        case .fading: "Moments you don't open for a month fade here, then move to the archive."
        default: ""
        }
    }
}

/// Right-click actions on a moment.
struct MomentMenu: View {
    let moment: MomentRecord
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        let store = MomentStore.shared
        Button("Open") { browser.openMoment(moment) }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(moment.url.absoluteString, forType: .string)
        }
        Divider()
        Menu("Resurface") {
            ForEach(ResurfaceChoice.allCases) { choice in
                Button(choice.label) { store.update(moment) { $0.resurfaceAt = choice.date(from: .now) } }
            }
        }
        if moment.changedAt != nil {
            Button("Mark Change as Seen") {
                store.update(moment) {
                    $0.changedAt = nil
                    $0.changeSummary = nil
                }
            }
        }
        Button(moment.isArchived ? "Unarchive" : "Archive") {
            store.update(moment) {
                $0.isArchived.toggle()
                // Back from the archive: it counts as seen, so it doesn't fade straight away.
                if !$0.isArchived { $0.lastOpenedAt = .now }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(moment) }
    }
}
