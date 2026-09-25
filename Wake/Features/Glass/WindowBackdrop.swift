import AppKit
import SwiftUI

/// The translucent glass the whole window is made of: a behind-window blur plus
/// a tint whose strength comes from the Glass setting.
struct WindowBackdrop: View {
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        ZStack {
            BehindWindowBlur(material: appearance.glass.windowMaterial)
            Color(nsColor: .windowBackgroundColor).opacity(appearance.glass.windowTint)
        }
        .ignoresSafeArea()
        .animation(.smooth, value: appearance.glass)
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
