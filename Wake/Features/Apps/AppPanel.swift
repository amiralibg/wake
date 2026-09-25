import SwiftUI

/// The showing pinned app: a large card that slides in beside the capsule, over the
/// trail. Click outside, press Esc, or click its icon again to put it away.
struct AppPanel: View {
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let app = browser.apps.active {
                    Color.black.opacity(0.14)
                        .contentShape(.rect)
                        .onTapGesture { browser.dismissOverlays() }
                        .transition(.opacity)

                    PageCard(page: app.page, isFocused: true)
                        .frame(width: min(1100, (proxy.size.width - leadingInset) * 0.72))
                        .padding(.leading, leadingInset)
                        .padding(.top, Metrics.toolbarHeight + 4)
                        .padding(.bottom, Metrics.stageInset)
                        .id(app.id)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .animation(.chrome, value: browser.apps.activeID)
    }

    /// Just right of the capsule.
    private var leadingInset: CGFloat {
        8 + Metrics.capsuleWidth + 10
    }
}
