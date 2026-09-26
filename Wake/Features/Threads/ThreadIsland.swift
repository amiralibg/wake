import SwiftUI

/// One glass island: the thread (opens the switcher) and its trail of columns.
struct ThreadIsland: View {
    @Environment(BrowserModel.self) private var browser
    @State private var isShowingSwitcher = false

    var body: some View {
        // Narrow windows: the island gives up detail, widest first, instead of running
        // under the address bar (the toolbar offers it only the room left of centre).
        ViewThatFits(in: .horizontal) {
            island(threadTitleWidth: 160, showsColumnTitle: true)
            island(threadTitleWidth: 110, showsColumnTitle: false)
            island(threadTitleWidth: nil, showsColumnTitle: false)
            island(threadTitleWidth: nil, showsColumnTitle: false, showsColumns: false)
        }
    }

    /// `threadTitleWidth` nil: the thread button is just its icon.
    private func island(threadTitleWidth: CGFloat?, showsColumnTitle: Bool, showsColumns: Bool = true) -> some View {
        HStack(spacing: 4) {
            Button { isShowingSwitcher.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let threadTitleWidth {
                        Text(browser.thread.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: threadTitleWidth, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(height: 28)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(threadTitleWidth == nil ? "Threads · \(browser.thread.title)" : "Threads")
            .popover(isPresented: $isShowingSwitcher, arrowEdge: .bottom) {
                ThreadSwitcher(isPresented: $isShowingSwitcher)
                    .environment(browser)
            }

            if showsColumns, !browser.trail.columns.isEmpty {
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 2)
                TrailStrip(
                    columns: browser.trail.columns,
                    focusedID: browser.page?.id,
                    onSelect: browser.trail.focus(id:),
                    onClose: browser.trail.close,
                    onPin: browser.pin,
                    showsFocusedTitle: showsColumnTitle
                )
                .padding(.trailing, 3)
            }
        }
        .frame(height: Metrics.capsuleHeight)
        .fixedSize(horizontal: true, vertical: false)
        .glassSurface(Capsule(), interactive: true)
    }
}
