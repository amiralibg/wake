import SwiftUI

/// A miniature Wake window drawn from the current settings: theme, accent, glass,
/// gap, corner radius and page width. It follows the real layout: toolbar islands on
/// top, headerless page cards below, one focused.
struct AppearancePreview: View {
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        ZStack {
            wallpaper
            MiniWindow(appearance: appearance)
                .padding(.horizontal, 28)
                .padding(.top, 18)
        }
        .frame(height: 170)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        // Preview the chosen theme even while the app shows another.
        .environment(\.colorScheme, scheme)
        .animation(.deck, value: appearance.gap)
        .animation(.deck, value: appearance.cornerRadius)
        .animation(.deck, value: appearance.pageWidth)
        .animation(.deck, value: appearance.theme)
        .animation(.smooth, value: appearance.glass)
        .accessibilityElement()
        .accessibilityLabel("Preview of the current appearance")
    }

    private var scheme: ColorScheme {
        switch appearance.theme {
        case .light: .light
        case .dark: .dark
        case .auto: systemScheme
        }
    }

    private var wallpaper: some View {
        let dark = scheme == .dark
        return ZStack {
            (dark ? Color(red: 0.05, green: 0.07, blue: 0.13) : Color(red: 0.12, green: 0.21, blue: 0.35))
            blob(Color(red: 0.94, green: 0.53, blue: 0.31), x: -180, y: -70, dark: dark)
            blob(Color(red: 0.42, green: 0.36, blue: 0.91), x: 200, y: -20, dark: dark)
            blob(Color(red: 0.10, green: 0.70, blue: 0.65), x: 30, y: 90, dark: dark)
        }
    }

    private func blob(_ color: Color, x: CGFloat, y: CGFloat, dark: Bool) -> some View {
        Ellipse()
            .fill(color)
            .frame(width: 280, height: 210)
            .blur(radius: 42)
            .opacity(dark ? 0.55 : 0.9)
            .offset(x: x, y: y)
    }
}

private struct MiniWindow: View {
    let appearance: AppearanceSettings
    @Environment(\.colorScheme) private var scheme

    private let gapScale: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            pages
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(glassTint)
            }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10, style: .continuous))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 0.5)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) {
                    Circle().fill($0).frame(width: 5, height: 5)
                }
            }
            .padding(.trailing, 2)
            // Thread island: name, then column chips with the focused one as a pill.
            HStack(spacing: 3) {
                Capsule().fill(.primary.opacity(0.45)).frame(width: 22, height: 3)
                Circle().fill(.primary.opacity(0.3)).frame(width: 5, height: 5)
                Capsule().fill(.tint.opacity(0.8)).frame(width: 16, height: 5)
                Circle().fill(.primary.opacity(0.3)).frame(width: 5, height: 5)
            }
            .padding(.horizontal, 6)
            .frame(height: 12)
            .background(.primary.opacity(0.12), in: Capsule())
            Spacer(minLength: 4)
            Capsule().fill(.primary.opacity(0.12)).frame(width: 90, height: 12)
            Spacer(minLength: 4)
            Capsule().fill(.primary.opacity(0.12)).frame(width: 40, height: 12)
        }
    }

    private var pages: some View {
        GeometryReader { proxy in
            let gap = appearance.gap * gapScale
            let perScreen = appearance.pageWidth.columnsPerScreen
            let width = (proxy.size.width - (perScreen - 1) * gap) / perScreen
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<4, id: \.self) { index in
                    page(focused: index == 0)
                        .frame(width: width)
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .clipped()
    }

    private func page(focused: Bool) -> some View {
        let radius = appearance.cornerRadius * 0.5
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(scheme == .dark ? Color(white: 0.2) : .white)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(.primary.opacity(0.25)).frame(width: 40, height: 4)
                    Capsule().fill(.primary.opacity(0.12)).frame(height: 3)
                    Capsule().fill(.primary.opacity(0.12)).frame(width: 50, height: 3)
                }
                .padding(8)
            }
            .overlay(alignment: .top) {
                if focused {
                    Capsule().fill(.tint).frame(height: 1.5).padding(.horizontal, radius + 6)
                }
            }
            .opacity(focused ? 1 : 0.92)
            .shadow(color: .black.opacity(focused ? 0.28 : 0.1), radius: focused ? 8 : 3, y: focused ? 5 : 2)
            .padding(.bottom, 10)
    }

    private var glassTint: Double {
        switch appearance.glass {
        case .subtle: 0.7
        case .balanced: 0.4
        case .clear: 0.08
        }
    }
}
