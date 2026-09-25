import SwiftUI

extension View {
    /// Floating glass: Liquid Glass on macOS 26+, a material with a hairline rim before that.
    ///
    /// `vibrantContent`: Liquid Glass applies vibrancy to whatever is drawn inside it,
    /// which suits small controls but washes out large panels (their backgrounds and
    /// colours blend with what's behind). Panels pass `false` to keep the glass as a
    /// separate layer behind their content.
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false, vibrantContent: Bool = true) -> some View {
        modifier(GlassSurface(shape: shape, interactive: interactive, vibrantContent: vibrantContent))
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    @Environment(AppearanceSettings.self) private var appearance
    let shape: S
    let interactive: Bool
    let vibrantContent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if vibrantContent {
                content.glassEffect(liquidGlass, in: shape)
            } else {
                content.background { Color.clear.glassEffect(liquidGlass, in: shape) }
            }
        } else {
            content
                .background(appearance.glass.fallbackMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.5), lineWidth: 0.5))
                .overlay(shape.stroke(.black.opacity(0.08), lineWidth: 0.5).padding(-0.5))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
    }

    @available(macOS 26.0, *)
    private var liquidGlass: Glass {
        var glass: Glass = switch appearance.glass {
        case .subtle: .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.45))
        case .balanced: .regular
        case .clear: .clear
        }
        if interactive { glass = glass.interactive() }
        return glass
    }
}
