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
    var backdrop: BackdropStyle { didSet { store(backdrop.rawValue, .backdrop) } }
    var cardStyle: CardStyle { didSet { store(cardStyle.rawValue, .cardStyle) } }
    var motion: MotionStyle { didSet { store(motion.rawValue, .motion); MotionStyle.current = motion } }
    /// The actions island's buttons; empty hides the island.
    var toolbarButtons: [ToolbarButton] { didSet { store(toolbarButtons.map(\.rawValue), .toolbarButtons) } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = ThemePreference(rawValue: defaults.string(forKey: Key.theme.qualified) ?? "") ?? .auto
        accent = AccentChoice(rawValue: defaults.string(forKey: Key.accent.qualified) ?? "") ?? .blue
        glass = GlassStrength(rawValue: defaults.string(forKey: Key.glass.qualified) ?? "") ?? .balanced
        gap = CGFloat(defaults.object(forKey: Key.gap.qualified) as? Double ?? Double(GapPreset.balanced.rawValue))
        cornerRadius = CGFloat(defaults.object(forKey: Key.cornerRadius.qualified) as? Double ?? 12)
        pageWidth = PageWidth(rawValue: defaults.string(forKey: Key.pageWidth.qualified) ?? "") ?? .balanced
        backdrop = BackdropStyle(rawValue: defaults.string(forKey: Key.backdrop.qualified) ?? "") ?? .glass
        cardStyle = CardStyle(rawValue: defaults.string(forKey: Key.cardStyle.qualified) ?? "") ?? .floating
        motion = MotionStyle(rawValue: defaults.string(forKey: Key.motion.qualified) ?? "") ?? .standard
        toolbarButtons = (defaults.stringArray(forKey: Key.toolbarButtons.qualified)?.compactMap(ToolbarButton.init(rawValue:))) ?? ToolbarButton.defaults
        MotionStyle.current = motion
    }

    /// Sets every piece of a preset's look.
    func apply(_ preset: ThemePreset) {
        theme = preset.theme
        accent = preset.accent
        glass = preset.glass
        backdrop = preset.backdrop
        cardStyle = preset.cardStyle
        gap = preset.gap
        cornerRadius = preset.cornerRadius
    }

    /// The preset these settings are exactly, or nil for a custom mix.
    var preset: ThemePreset? {
        ThemePreset.allCases.first {
            $0.theme == theme && $0.accent == accent && $0.glass == glass && $0.backdrop == backdrop
                && $0.cardStyle == cardStyle && $0.gap == gap && $0.cornerRadius == cornerRadius
        }
    }

    func toggle(_ button: ToolbarButton) {
        if toolbarButtons.contains(button) {
            toolbarButtons.removeAll { $0 == button }
        } else {
            // Keep the island's order the same as the list's.
            toolbarButtons = ToolbarButton.allCases.filter { toolbarButtons.contains($0) || $0 == button }
        }
    }

    /// NSVisualEffectView follows the app appearance, not SwiftUI's preferredColorScheme,
    /// so the theme is applied at the NSApplication level.
    func applyTheme() {
        NSApp?.appearance = theme.appearance
    }

    private enum Key: String {
        case theme, accent, glass, gap, cornerRadius, pageWidth, backdrop, cardStyle, motion, toolbarButtons
        var qualified: String { "appearance." + rawValue }
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.qualified)
    }
}
