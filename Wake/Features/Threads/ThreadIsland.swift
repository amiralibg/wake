import SwiftUI

/// One glass island: the thread (opens the switcher) and its trail of columns.
struct ThreadIsland: View {
    @Environment(BrowserModel.self) private var browser
    @State private var isShowingSwitcher = false

    var body: some View {
        HStack(spacing: 4) {
            Button { isShowingSwitcher.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(browser.thread.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
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
            .help("Threads")
            .popover(isPresented: $isShowingSwitcher, arrowEdge: .bottom) {
                ThreadSwitcher(isPresented: $isShowingSwitcher)
                    .environment(browser)
            }

            if !browser.trail.columns.isEmpty {
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 2)
                TrailStrip(
                    columns: browser.trail.columns,
                    focusedID: browser.page?.id,
                    onSelect: browser.trail.focus(id:),
                    onClose: browser.trail.close,
                    onPin: browser.pin
                )
                .padding(.trailing, 3)
            }
        }
        .frame(height: Metrics.capsuleHeight)
        .glassSurface(Capsule(), interactive: true)
    }
}
