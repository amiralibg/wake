import AppKit
import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    case light, dark, auto

    var id: Self { self }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .auto: "Auto"
        }
    }

    /// `nil` follows the system.
    var appearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .auto: nil
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, purple, pink, orange, green, teal, graphite

    var id: Self { self }

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .pink: Color(nsColor: .systemPink)
        case .orange: Color(nsColor: .systemOrange)
        case .green: Color(nsColor: .systemGreen)
        case .teal: Color(nsColor: .systemTeal)
        case .graphite: Color(nsColor: .systemGray)
        }
    }
}

enum GlassStrength: String, CaseIterable, Identifiable {
    case subtle, balanced, clear

    var id: Self { self }

    var label: String { rawValue.capitalized }

    /// Material behind the whole window (pre-Liquid Glass and Liquid Glass alike;
    /// AppKit has no "window glass" API, so the window itself stays a visual effect view).
    var windowMaterial: NSVisualEffectView.Material {
        switch self {
        case .subtle: .underWindowBackground
        case .balanced: .sidebar
        case .clear: .fullScreenUI
        }
    }

    /// Opacity of the window-background tint laid over the blur.
    var windowTint: Double {
        switch self {
        case .subtle: 0.4
        case .balanced: 0.1
        case .clear: 0.0
        }
    }

    /// Material for capsules when Liquid Glass (macOS 26) is unavailable.
    var fallbackMaterial: Material {
        switch self {
        case .subtle: .regularMaterial
        case .balanced: .thinMaterial
        case .clear: .ultraThinMaterial
        }
    }
}

enum PageWidth: String, CaseIterable, Identifiable {
    case narrow, balanced, wide

    var id: Self { self }

    var label: String { rawValue.capitalized }

    /// How many columns share the window once several are open. A single column
    /// always fills the window; beyond this many, the trail scrolls.
    var columnsPerScreen: CGFloat {
        switch self {
        case .narrow: 3
        case .balanced: 2
        case .wide: 1.5
        }
    }
}

enum GapPreset: CGFloat, CaseIterable, Identifiable {
    case none = 0, tight = 8, balanced = 14, roomy = 24

    var id: Self { self }

    var label: String {
        switch self {
        case .none: "None"
        case .tight: "Tight"
        case .balanced: "Balanced"
        case .roomy: "Roomy"
        }
    }
}

enum CornerRadiusOption: CGFloat, CaseIterable, Identifiable {
    case square = 0, soft = 8, round = 12, pill = 18

    var id: Self { self }

    var label: String {
        switch self {
        case .square: "Square"
        case .soft: "Soft"
        case .round: "Round"
        case .pill: "Pill"
        }
    }
}
