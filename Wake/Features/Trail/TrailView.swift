import SwiftUI

/// Pages as columns laid left to right (Niri-style). One column fills the stage,
/// two split it, and more scroll. The strip slides so the focused column is in view.
struct TrailView: View {
    let trail: TrailModel
    let isInteractive: Bool
    /// Vertical scrolling in a page (the reader is reading).
    var onPageScroll: () -> Void = {}

    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.isZen) private var isZen

    var body: some View {
        GeometryReader { proxy in
            let usable = max(1, proxy.size.width - outerInset * 2)
            let geometry = TrailGeometry(
                stageWidth: proxy.size.width,
                gap: appearance.gap,
                inset: outerInset,
                columnsPerScreen: appearance.pageWidth.columnsPerScreen,
                customFractions: trail.columns.map { page in
                    fraction(of: page, usable: usable, stageHeight: proxy.size.height)
                }
            )
            let offset = trail.dragOffset
                ?? trail.restingOffset.map(geometry.clamped)
                ?? geometry.targetOffset(focusing: trail.focusedIndex, span: trail.focusSpan)
            let isResizable = trail.columns.count > 1
            ZStack(alignment: .topLeading) {
                ForEach(Array(trail.columns.enumerated()), id: \.element.id) { index, page in
                    TrailColumn(
                        page: page,
                        isFocused: index == trail.focusedIndex,
                        onFocus: { trail.focus(index) },
                        onClose: { trail.close(page) }
                    )
                    .frame(width: geometry.width(of: index), height: proxy.size.height)
                    .overlay(alignment: .leading) {
                        if isResizable, page.device == nil {
                            edgeHandle(page, .leading, outside: index == 0 ? outerInset : appearance.gap / 2)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if isResizable, page.device == nil {
                            edgeHandle(page, .trailing, outside: index == trail.columns.count - 1 ? outerInset : appearance.gap / 2)
                        }
                    }
                    .offset(x: geometry.x(of: index) - offset)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .leading).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .onChange(of: geometry, initial: true) { _, new in trail.geometry = new }
            .onChange(of: onStage(geometry, offset: offset), initial: true) { _, ids in trail.setOnStage(ids) }
            // While an edge is dragged the columns track the pointer exactly.
            .animation(trail.isResizing ? nil : .trail, value: geometry)
        }
        .background(TrailGestureRouter(trail: trail, isEnabled: isInteractive, onPageScroll: onPageScroll))
        .padding(.top, isZen ? outerInset : 4)
        .padding(.bottom, outerInset)
    }

    /// Columns on the stage, or within a quarter stage of it (the next one to slide
    /// in). Everything else is off to the side and can let WebKit throttle it.
    private func onStage(_ geometry: TrailGeometry, offset: CGFloat) -> Set<BrowserPage.ID> {
        let indices = geometry.indices(onStageAt: offset, margin: geometry.stageWidth / 4)
        return Set(trail.columns.indices.filter(indices.contains).map { trail.columns[$0].id })
    }

    private func edgeHandle(_ page: BrowserPage, _ edge: TrailModel.Edge, outside: CGFloat) -> some View {
        ColumnEdgeHandle(edge: edge, outside: outside) {
            trail.beginResize(page, edge: edge)
        } onDrag: { delta in
            trail.resize(by: delta)
        } onEnd: {
            trail.endResize()
        } onReset: {
            trail.resetWidth(of: page)
        }
    }

    /// Share of the stage a column takes, or `nil` for the default width.
    private func fraction(of page: BrowserPage, usable: CGFloat, stageHeight: CGFloat) -> CGFloat? {
        if let device = page.device {
            // Leaves room for the page it previews, so the two always fit side by side.
            let room = max(DeviceFrame.minColumnWidth, usable - Metrics.minColumnWidth - appearance.gap)
            return device.columnWidth(stageHeight: stageHeight, maxWidth: room) / usable
        }
        if let custom = trail.widthFraction(of: page) { return custom }
        // A page with DevTools or a preview beside it takes the rest of the stage,
        // so the pair fills the window instead of leaving margins.
        let companions = trail.companions(of: page)
        guard !companions.isEmpty else { return nil }
        let taken = companions.reduce(0) { total, column in
            total + (fraction(of: column, usable: usable, stageHeight: stageHeight) ?? 0.5) * usable + appearance.gap
        }
        let rest = usable - taken
        return rest >= Metrics.minColumnWidth ? rest / usable : nil
    }

    /// Zen drops the chrome margins: pages sit half a gap from the window edge.
    private var outerInset: CGFloat {
        isZen ? appearance.gap / 2 : Metrics.stageInset
    }
}

/// One edge of a column, like the edge of a window: drag it to make just this
/// column wider or narrower (its neighbours slide, the trail scrolls if needed);
/// double-click to go back to the default width. The zone reaches a few points
/// into the card and out to the middle of the gap, so each side of a gap belongs
/// to the column it touches. A pill hugging the edge shows what will move.
private struct ColumnEdgeHandle: View {
    let edge: TrailModel.Edge
    /// How far the zone reaches outside the card (half the gap, or the stage margin).
    let outside: CGFloat
    let onBegin: () -> Void
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    /// Inside the card: small, so the page keeps its own edge clicks.
    private let inside: CGFloat = 4
    /// Keeps clear of the window's own resize zone at the stage ends.
    private var reach: CGFloat { max(3, min(outside, 12) - 3) }

    var body: some View {
        let width = inside + reach
        ZStack(alignment: edge == .leading ? .trailing : .leading) {
            Color.clear
            Capsule()
                .fill(isDragging ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.45)))
                .frame(width: 4, height: isDragging ? 72 : 48)
                .shadow(color: .black.opacity(0.2), radius: 3)
                // Hugs the card, a little way into the gap.
                .offset(x: pillOffset)
                .opacity(isHovering || isDragging ? 1 : 0)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
        .offset(x: edge == .leading ? -reach : reach)
        .onHover { inside in
            withAnimation(.hover) { isHovering = inside }
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        withAnimation(.hover) { isDragging = true }
                        onBegin()
                    }
                    onDrag(value.translation.width)
                }
                .onEnded { _ in
                    withAnimation(.hover) { isDragging = false }
                    onEnd()
                }
        )
        .onTapGesture(count: 2, perform: onReset)
        .help("Drag to resize this column · double-click to reset")
        .accessibilityLabel(edge == .leading ? "Column left edge" : "Column right edge")
    }

    /// The pill starts flush with the card edge on the inside; move it just past
    /// the edge into the gap.
    private var pillOffset: CGFloat {
        let gapSide = min(reach, 5) - 2
        return edge == .leading ? -(inside + gapSide) : inside + gapSide
    }
}
