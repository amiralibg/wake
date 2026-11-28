import AppKit
import SwiftUI

/// The translucent glass the whole window is made of: a behind-window blur plus
/// a tint whose strength comes from the Glass setting.
struct WindowBackdrop: View {
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        ZStack {
            if appearance.backdrop == .solid {
                Color(nsColor: .windowBackgroundColor)
            } else {
                BehindWindowBlur(material: appearance.glass.windowMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(appearance.glass.windowTint)
                switch appearance.backdrop {
                case .tinted:
                    appearance.accent.color.opacity(0.16)
                case .gradient:
                    LinearGradient(
                        colors: [appearance.accent.color.opacity(0.28), appearance.accent.color.opacity(0.04), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                case .glass, .solid:
                    EmptyView()
                }
            }
        }
        .ignoresSafeArea()
        .animation(.smooth, value: appearance.glass)
        .animation(.smooth, value: appearance.backdrop)
        .animation(.smooth, value: appearance.accent)
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
