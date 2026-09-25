import SwiftUI

/// Wake's springs, in one place so everything moves with the same feel.
/// Quick responses with high damping: things arrive fast and settle without wobble.
extension Animation {
    /// Columns sliding, opening and closing.
    static let trail = Animation.spring(response: 0.3, dampingFraction: 0.9)
    /// The Deck and other large surfaces.
    static let deck = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Toolbars, palettes, panels appearing.
    static let chrome = Animation.spring(response: 0.24, dampingFraction: 0.88)
    /// Small hover responses.
    static let hover = Animation.spring(response: 0.18, dampingFraction: 0.75)
}
