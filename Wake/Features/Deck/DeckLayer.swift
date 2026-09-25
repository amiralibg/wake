import SwiftUI

/// The Deck: threads as live cards. It stays out of the way while you read.
///
/// - Hidden: nothing on screen. Reaching the bottom edge of the window…
/// - Peek: …raises a glass island with small cards; hover one, click to switch.
/// - Open (⌘K, or "Open Deck"): the page frosts over, search and arrangement appear,
///   and the same cards grow and fan out. Cold tabs sit behind the waterline island.
struct DeckLayer: View {
    @Environment(BrowserModel.self) private var browser
    @Environment(DeckSettings.self) private var settings

    @State private var hoveredID: DeckItem.ID?
    @State private var confirmingLetGo = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            GeometryReader { proxy in
                let items = filtered(browser.deckItems(settings: settings, now: timeline.date))
                let afloat = DeckLayout.fanOrder(items.filter { !$0.isSunk })
                let sunk = items.filter(\.isSunk)
                let layout = DeckLayout(state: state, width: proxy.size.width)
                ZStack(alignment: .bottom) {
                    if state == .open {
                        DeckBackdrop(onDismiss: browser.hidePalette)
                            .transition(.opacity)
                        DeckHeader(browser: browser)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, Metrics.toolbarHeight + 28)
                            .zIndex(300)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if state == .peek {
                        PeekIsland(
                            afloatCount: afloat.count,
                            sunkCount: sunk.count,
                            onOpen: browser.openDeck
                        )
                        .frame(
                            width: layout.peekIslandSize(count: afloat.count).width,
                            height: layout.peekIslandSize(count: afloat.count).height
                        )
                        .padding(.bottom, DeckLayout.margin)
                        .onHover { inside in inside ? browser.holdDeckPeek() : browser.endDeckPeek() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    cards(afloat: afloat, sunk: sunk, layout: layout)
                    if state == .open {
                        WaterlineIsland(sunkCount: sunk.count, onLetGo: { confirmingLetGo = true })
                            .padding(.horizontal, 16)
                            .padding(.bottom, DeckLayout.margin)
                            .zIndex(200)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                .confirmationDialog(
                    sunk.count == 1 ? "Let 1 tab go?" : "Let \(sunk.count) tabs go?",
                    isPresented: $confirmingLetGo
                ) {
                    Button("Let Them Go", role: .destructive) {
                        withAnimation(.deck) { browser.letGo(threadIDs: sunk.map(\.threadID)) }
                    }
                } message: {
                    Text("Threads below the waterline are closed and removed from the Deck.")
                }
            }
        }
        .animation(.deck, value: state)
        .animation(.deck, value: browser.deckArrangement)
        .animation(.deck, value: browser.thread.id)
    }

    private var state: DeckLayout.State {
        if browser.isDeckOpen { return .open }
        return browser.isDeckPeeking ? .peek : .hidden
    }

    private func cards(afloat: [DeckItem], sunk: [DeckItem], layout: DeckLayout) -> some View {
        let size = layout.cardSize
        return ZStack(alignment: .bottom) {
            ForEach(Array(sunk.enumerated()), id: \.element.id) { index, item in
                card(item, size: size, placement: layout.sunkPlacement(index: index, count: sunk.count))
                    .blur(radius: 1.5)
            }
            ForEach(Array(afloat.enumerated()), id: \.element.id) { rank, item in
                card(item, size: size, placement: layout.placement(rank: rank, heat: item.heat, count: afloat.count))
            }
        }
        .opacity(state == .hidden ? 0 : 1)
        .allowsHitTesting(state != .hidden)
    }

    private func card(_ item: DeckItem, size: CGSize, placement: DeckLayout.Placement) -> some View {
        let isHovered = hoveredID == item.id
        let lift: CGFloat = isHovered ? (state == .open ? 14 : 8) : 0
        return DeckCard(item: item, size: size, isOpen: state == .open)
            .scaleEffect(isHovered ? 1.05 : 1, anchor: .bottom)
            .rotationEffect(.degrees(isHovered ? placement.rotation * 0.4 : placement.rotation), anchor: .bottom)
            .offset(x: placement.x, y: -placement.bottom - lift)
            .zIndex(isHovered ? 150 : placement.zIndex)
            .onHover { inside in
                if state == .peek { inside ? browser.holdDeckPeek() : browser.endDeckPeek() }
                withAnimation(.hover) {
                    hoveredID = inside ? item.id : (hoveredID == item.id ? nil : hoveredID)
                }
            }
            .onTapGesture { browser.selectDeckItem(item) }
            .gesture(reviveGesture(for: item))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.title), \(item.footnote)")
            .accessibilityAddTraits(.isButton)
            .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
    }

    /// Drag a sunk card up to bring it back above the waterline.
    private func reviveGesture(for item: DeckItem) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard item.isSunk, value.translation.height < -50 else { return }
                withAnimation(.deck) { browser.revive(threadID: item.threadID) }
            }
    }

    /// Typing in the Deck's search narrows the cards; matching sunk tabs float up.
    private func filtered(_ items: [DeckItem]) -> [DeckItem] {
        let query = browser.palette.query.trimmingCharacters(in: .whitespaces)
        guard browser.isDeckOpen, !query.isEmpty else { return items }
        return items
            .filter { $0.title.localizedCaseInsensitiveContains(query) || $0.host.localizedCaseInsensitiveContains(query) }
            .map { item in
                DeckItem(id: item.id, threadID: item.threadID, title: item.title, host: item.host, pageCount: item.pageCount,
                         lastActiveAt: item.lastActiveAt, isActive: item.isActive, chip: item.chip,
                         afloat: item.afloat, heat: max(item.heat, 0.3), isSunk: false)
            }
    }
}

/// Frosts over the page while the Deck is open. The toolbar stays crisp above it.
private struct DeckBackdrop: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(nsColor: .windowBackgroundColor).opacity(0.3)
        }
        .padding(.top, Metrics.toolbarHeight)
        .contentShape(.rect)
        .onTapGesture(perform: onDismiss)
    }
}

/// Search (the ⌘K palette) and the arrangement control, centred above the fan.
private struct DeckHeader: View {
    @Bindable var browser: BrowserModel

    var body: some View {
        VStack(spacing: 14) {
            CommandPalette(model: browser.palette, onChoose: browser.choose, onDismiss: browser.hidePalette)
            Picker("Arrange", selection: $browser.deckArrangement) {
                ForEach(DeckArrangement.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if browser.palette.query.isEmpty {
                Text("Hotter tabs float higher. Untouched ones slowly sink.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
