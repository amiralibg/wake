import SwiftUI

/// New column · Save moment · Pop out · Share · Zen.
struct ActionsCapsule: View {
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        HStack(spacing: 0) {
            ToolbarIconButton(symbol: "plus", label: "New Column (⌘T)") {
                browser.showPalette(target: .newColumn)
            }
            ToolbarIconButton(symbol: "bookmark", label: "Save Moment (⌘D) · right-click for Moments") {
                browser.saveMoment()
            }
            .disabled(browser.webPage?.url?.scheme?.hasPrefix("http") != true)
            .contextMenu {
                Button("Show Moments (⌥⌘B)") { browser.showMoments() }
                Button("Moments Relevant Here") { browser.showMoments(.relevant) }
            }
            ToolbarIconButton(
                symbol: browser.webPage?.isPickingPopOut == true ? "square.on.square.fill" : "square.on.square",
                label: "Pop Out: pick part of the page to float it, live (⌥⌘O)"
            ) {
                browser.togglePopOutPicker()
            }
            .disabled(browser.webPage?.url == nil)
            if let url = browser.page?.url {
                ShareLink(item: url) {
                    ToolbarIcon(symbol: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Share")
            } else {
                ToolbarIcon(symbol: "square.and.arrow.up").opacity(0.35)
            }
            ToolbarIconButton(
                symbol: browser.isZen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                label: browser.isZen ? "Leave Zen (⌘\\)" : "Zen: hide everything but pages (⌘\\)"
            ) {
                withAnimation(.trail) { browser.isZen.toggle() }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: Metrics.capsuleHeight)
        .glassSurface(Capsule())
    }
}

struct ToolbarIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ToolbarIcon(symbol: symbol)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct ToolbarIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13.5, weight: .regular))
            .frame(width: 34, height: 28)
            .contentShape(.rect)
    }
}
