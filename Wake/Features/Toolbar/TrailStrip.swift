import SwiftUI

/// The trail as favicon chips. The focused column grows into a pill with its title;
/// the rest stay compact. Click a chip to focus its column.
struct TrailStrip: View {
    let columns: [BrowserPage]
    let focusedID: BrowserPage.ID?
    let onSelect: (BrowserPage.ID) -> Void
    let onClose: (BrowserPage) -> Void
    var onPin: ((BrowserPage) -> Void)?
    /// Off in narrow windows: the focused chip stays an icon like the rest.
    var showsFocusedTitle = true

    @Namespace private var selection
    private let maxVisible = 7

    var body: some View {
        let (leading, visible, trailing) = window()
        HStack(spacing: 2) {
            if leading > 0 { overflowBadge(leading) }
            ForEach(visible) { page in
                TrailChip(page: page, isFocused: page.id == focusedID, showsTitle: showsFocusedTitle, selection: selection) {
                    onSelect(page.id)
                }
                .contextMenu {
                    if let onPin, page.url != nil {
                        Button("Pin as App") { onPin(page) }
                    }
                    Button("Close Column") { onClose(page) }
                }
            }
            if trailing > 0 { overflowBadge(trailing) }
        }
        .animation(.chrome, value: focusedID)
        .animation(.chrome, value: columns.map(\.id))
    }

    private func overflowBadge(_ count: Int) -> some View {
        Text("+\(count)")
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
    }

    /// Keeps the focused column and its neighbours visible in long trails.
    private func window() -> (leading: Int, visible: [BrowserPage], trailing: Int) {
        guard columns.count > maxVisible else { return (0, columns, 0) }
        let focus = columns.firstIndex { $0.id == focusedID } ?? 0
        let start = min(max(0, focus - maxVisible / 2), columns.count - maxVisible)
        let end = start + maxVisible
        return (start, Array(columns[start..<end]), columns.count - end)
    }
}

private struct TrailChip: View {
    let page: BrowserPage
    let isFocused: Bool
    var showsTitle = true
    let selection: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let chip = LiveChips.chips(for: page).first
        Button(action: action) {
            HStack(spacing: 6) {
                Favicon(url: page.faviconURL, host: page.host, size: 14)
                    .overlay(alignment: .bottomTrailing) {
                        if page.isLoading { LoadingDot() }
                    }
                    .overlay(alignment: .topTrailing) {
                        // The page's most important live fact, as a dot (details in the tooltip).
                        if let dot = chip?.tone.dot, !page.isLoading {
                            Circle()
                                .fill(dot)
                                .frame(width: 6, height: 6)
                                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
                                .offset(x: 2.5, y: -2.5)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                if isFocused, showsTitle {
                    Text(page.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .padding(.horizontal, isFocused && showsTitle ? 9 : 6)
            .frame(height: 24)
            .background {
                if isFocused {
                    Capsule()
                        .fill(.primary.opacity(0.1))
                        .matchedGeometryEffect(id: "focus", in: selection)
                } else if isHovering {
                    Capsule().fill(.primary.opacity(0.06))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(chip.map { "\(page.displayTitle) · \($0.text)" } ?? page.displayTitle)
        .accessibilityLabel(chip.map { "\(page.displayTitle), \($0.text)" } ?? page.displayTitle)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }
}

private struct LoadingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(.tint)
            .frame(width: 5, height: 5)
            .opacity(pulse ? 0.35 : 1)
            .offset(x: 2, y: 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}
