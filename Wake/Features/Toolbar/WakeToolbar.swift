import SwiftUI

/// Three glass islands: thread + trail · address (true centre) · actions.
/// When `isFloating` (Zen), the islands hover over the pages with their own shadows
/// and the traffic lights get an island of their own.
struct WakeToolbar: View {
    @Environment(BrowserModel.self) private var browser
    var isFloating = false

    var body: some View {
        ToolbarLayout {
            HStack(spacing: 10) {
                trafficLightsSlot
                ThreadIsland()
                    .modifier(IslandShadow(isOn: isFloating))
                Spacer(minLength: 0)
            }
            AddressCapsule(
                page: browser.webPage,
                onActivate: { browser.showPalette(target: .currentColumn) },
                onSwitchEnvironment: browser.switchEnvironment(to:)
            )
            .modifier(IslandShadow(isOn: isFloating))
            HStack(spacing: 8) {
                if let page = browser.webPage, page.isDeveloperMode {
                    DevIsland(page: page)
                        .modifier(IslandShadow(isOn: isFloating))
                        .transition(.scale(scale: 0.9, anchor: .trailing).combined(with: .opacity))
                }
                ActionsCapsule()
                    .modifier(IslandShadow(isOn: isFloating))
            }
            .animation(.chrome, value: browser.webPage?.isDeveloperMode)
        }
        .padding(.horizontal, Metrics.toolbarPadding)
        .frame(height: Metrics.toolbarHeight)
        .background {
            if !isFloating { WindowDragArea() }
        }
    }

    /// The system draws the traffic lights; in Zen we sit a glass island behind them.
    @ViewBuilder private var trafficLightsSlot: some View {
        if isFloating {
            Color.clear
                .frame(width: Metrics.trafficLightsWidth + 8, height: Metrics.capsuleHeight)
                .glassSurface(Capsule())
                .modifier(IslandShadow(isOn: true))
                .offset(x: -8)
                .padding(.trailing, -8)
        } else {
            Color.clear.frame(width: Metrics.trafficLightsWidth, height: 1)
        }
    }
}

private struct IslandShadow: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(isOn ? 0.28 : 0), radius: 14, y: 6)
    }
}
