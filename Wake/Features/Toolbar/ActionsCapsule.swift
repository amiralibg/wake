import SwiftUI

/// The toolbar's buttons, chosen in Settings ▸ Appearance ▸ Toolbar.
struct ActionsCapsule: View {
    @Environment(BrowserModel.self) private var browser
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        if !appearance.toolbarButtons.isEmpty {
            HStack(spacing: 0) {
                ForEach(appearance.toolbarButtons) { button($0) }
            }
            .padding(.horizontal, 4)
            .frame(height: Metrics.capsuleHeight)
            .glassSurface(Capsule())
        }
    }

    @ViewBuilder private func button(_ kind: ToolbarButton) -> some View {
        let page = browser.webPage
        switch kind {
        case .back:
            ToolbarIconButton(symbol: kind.symbol, label: "Back (\(keys(.back)))") { browser.page?.goBack() }
                .disabled(browser.page?.canGoBack != true)
        case .forward:
            ToolbarIconButton(symbol: kind.symbol, label: "Forward (\(keys(.forward)))") { browser.page?.goForward() }
                .disabled(browser.page?.canGoForward != true)
        case .reload:
            ToolbarIconButton(symbol: page?.isLoading == true ? "xmark" : kind.symbol, label: "Reload (\(keys(.reload)))") {
                if page?.isLoading == true { page?.stopLoading() } else { page?.reload() }
            }
            .disabled(page?.url == nil)
        case .newColumn:
            ToolbarIconButton(symbol: kind.symbol, label: "New Column (\(keys(.newColumn)))") { browser.newColumn() }
        case .find:
            ToolbarIconButton(symbol: kind.symbol, label: "Find in Page (\(keys(.findInPage)))") { browser.showFind() }
                .disabled(page?.url == nil)
        case .saveMoment:
            ToolbarIconButton(symbol: kind.symbol, label: "Save Moment (\(keys(.saveMoment))) · right-click for Moments") {
                browser.saveMoment()
            }
            .disabled(page?.url?.scheme?.hasPrefix("http") != true)
            .contextMenu {
                Button("Show Moments") { browser.showMoments() }
                Button("Moments Relevant Here") { browser.showMoments(.relevant) }
            }
        case .popOut:
            ToolbarIconButton(
                symbol: page?.isPickingPopOut == true ? "square.on.square.fill" : kind.symbol,
                label: "Pop Out: pick part of the page to float it, live (\(keys(.popOut)))"
            ) {
                browser.togglePopOutPicker()
            }
            .disabled(page?.url == nil)
        case .history:
            ToolbarIconButton(symbol: kind.symbol, label: "History (\(keys(.history)))") { browser.showHistory() }
        case .share:
            if let url = browser.page?.url {
                ShareLink(item: url) {
                    ToolbarIcon(symbol: kind.symbol)
                }
                .buttonStyle(.plain)
                .help("Share")
            } else {
                ToolbarIcon(symbol: kind.symbol).opacity(0.35)
            }
        case .zen:
            ToolbarIconButton(
                symbol: browser.isZen ? "arrow.down.right.and.arrow.up.left" : kind.symbol,
                label: browser.isZen ? "Leave Zen (\(keys(.zen)))" : "Zen: hide everything but pages (\(keys(.zen)))"
            ) {
                withAnimation(.trail) { browser.isZen.toggle() }
            }
        }
    }

    /// The command's current keys, so tooltips follow Settings ▸ Shortcuts.
    private func keys(_ command: WakeCommand) -> String {
        ShortcutStore.shared.combo(for: command)?.display ?? "no shortcut"
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
