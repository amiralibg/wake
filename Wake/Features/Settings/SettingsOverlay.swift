import SwiftUI

/// Dims the trail and floats the settings panel in the middle of the window.
struct SettingsOverlay: View {
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        ZStack {
            if browser.isSettingsOpen {
                Color.black.opacity(0.22)
                    .contentShape(.rect)
                    .onTapGesture(perform: browser.hideSettings)
                    .transition(.opacity)

                // A fixed size per window, so switching sections never resizes or
                // shifts the panel; rows reflow to fit instead.
                GeometryReader { proxy in
                    SettingsPanel(browser: browser)
                        .frame(
                            width: min(940, proxy.size.width - 48),
                            height: min(808, proxy.size.height - Metrics.toolbarHeight - 24)
                        )
                        .position(x: proxy.size.width / 2, y: Metrics.toolbarHeight + (proxy.size.height - Metrics.toolbarHeight - 24) / 2)
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.chrome, value: browser.isSettingsOpen)
    }
}
