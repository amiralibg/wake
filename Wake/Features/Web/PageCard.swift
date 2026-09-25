import SwiftUI

/// A page floating on the window glass: just the live web view in a rounded card.
/// No header: a thin accent line shows loading, and a glass close button appears
/// only when the pointer reaches the card's top-right corner.
struct PageCard: View {
    @Environment(AppearanceSettings.self) private var appearance
    let page: BrowserPage
    var isFocused = true
    var onClose: (() -> Void)?

    @State private var showsClose = false

    var body: some View {
        let radius = appearance.cornerRadius
        PageWebView(page: page, cornerRadius: radius) { inCorner in
            withAnimation(.hover) { showsClose = inCorner }
        }
            .overlay { if let failure = page.failure { PageFailureView(message: failure, page: page) } }
            .overlay(alignment: .top) {
                LoadingLine(progress: page.progress, isLoading: page.isLoading)
                    .padding(.horizontal, radius)
            }
            .overlay(alignment: .topTrailing) {
                if let onClose, showsClose {
                    CloseColumnButton(action: onClose)
                        .padding(8)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.black.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(isFocused ? 0.24 : 0.08), radius: isFocused ? 26 : 8, y: isFocused ? 18 : 4)
    }
}

private struct CloseColumnButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9.5, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(Circle(), interactive: true)
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .help("Close Column (⌘W)")
        .accessibilityLabel("Close column")
    }
}

/// A hairline of accent colour along the top edge while the page loads.
private struct LoadingLine: View {
    let progress: Double
    let isLoading: Bool

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.tint)
                .frame(width: max(8, proxy.size.width * progress))
                .shadow(color: .accentColor.opacity(0.6), radius: 3)
                .opacity(isLoading ? 1 : 0)
                .animation(.spring(duration: 0.35), value: progress)
                .animation(.easeOut(duration: 0.4).delay(isLoading ? 0 : 0.2), value: isLoading)
        }
        .frame(height: 2.5)
        .allowsHitTesting(false)
    }
}

private struct PageFailureView: View {
    let message: String
    let page: BrowserPage

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("This page couldn't load")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Try Again", action: page.reload)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
