import AppKit
import Observation
import SwiftUI

/// Single source of truth for every visual/layout value. Injected via the environment.
@MainActor
@Observable
final class AppearanceSettings {
    var theme: ThemePreference { didSet { store(theme.rawValue, .theme); applyTheme() } }
    var accent: AccentChoice { didSet { store(accent.rawValue, .accent) } }
    var glass: GlassStrength { didSet { store(glass.rawValue, .glass) } }
    var gap: CGFloat { didSet { store(Double(gap), .gap) } }
    var cornerRadius: CGFloat { didSet { store(Double(cornerRadius), .cornerRadius) } }
    var pageWidth: PageWidth { didSet { store(pageWidth.rawValue, .pageWidth) } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = ThemePreference(rawValue: defaults.string(forKey: Key.theme.qualified) ?? "") ?? .auto
        accent = AccentChoice(rawValue: defaults.string(forKey: Key.accent.qualified) ?? "") ?? .blue
        glass = GlassStrength(rawValue: defaults.string(forKey: Key.glass.qualified) ?? "") ?? .balanced
        gap = CGFloat(defaults.object(forKey: Key.gap.qualified) as? Double ?? Double(GapPreset.balanced.rawValue))
        cornerRadius = CGFloat(defaults.object(forKey: Key.cornerRadius.qualified) as? Double ?? 12)
        pageWidth = PageWidth(rawValue: defaults.string(forKey: Key.pageWidth.qualified) ?? "") ?? .balanced
    }

    /// NSVisualEffectView follows the app appearance, not SwiftUI's preferredColorScheme,
    /// so the theme is applied at the NSApplication level.
    func applyTheme() {
        NSApp?.appearance = theme.appearance
    }

    private enum Key: String {
        case theme, accent, glass, gap, cornerRadius, pageWidth
        var qualified: String { "appearance." + rawValue }
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.qualified)
    }
}
