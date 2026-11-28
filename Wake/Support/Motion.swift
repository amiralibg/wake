import SwiftUI

/// Wake's springs, in one place so everything moves with the same feel.
/// Quick responses with high damping: things arrive fast and settle without wobble.
/// Settings ▸ Appearance ▸ Motion scales them (`MotionStyle`).
extension Animation {
    /// Columns sliding, opening and closing.
    static var trail: Animation { MotionStyle.current.spring(response: 0.3, damping: 0.9) }
    /// The Deck and other large surfaces.
    static var deck: Animation { MotionStyle.current.spring(response: 0.34, damping: 0.86) }
    /// Toolbars, palettes, panels appearing.
    static var chrome: Animation { MotionStyle.current.spring(response: 0.24, damping: 0.88) }
    /// Small hover responses.
    static var hover: Animation { MotionStyle.current.spring(response: 0.18, damping: 0.75) }
}

enum MotionStyle: String, CaseIterable, Identifiable, Sendable {
    case snappy, standard, gentle, minimal

    var id: Self { self }

    var label: String {
        switch self {
        case .snappy: "Snappy"
        case .standard: "Standard"
        case .gentle: "Gentle"
        case .minimal: "Minimal"
        }
    }

    /// Read from every animation, on any thread; written only by
    /// `AppearanceSettings` on the main actor.
    nonisolated(unsafe) static var current: MotionStyle = .standard

    func spring(response: Double, damping: Double) -> Animation {
        switch self {
        case .snappy: .spring(response: response * 0.72, dampingFraction: min(damping + 0.04, 1))
        case .standard: .spring(response: response, dampingFraction: damping)
        case .gentle: .spring(response: response * 1.45, dampingFraction: max(damping - 0.06, 0.6))
        // A short fade-like ease: things still change in place, without travel.
        case .minimal: .easeOut(duration: 0.1)
        }
    }
}
