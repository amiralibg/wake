import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, deck, developer, privacy

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .deck: "rectangle.on.rectangle"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .privacy: "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(nsColor: .systemGray)
        case .appearance: Color(nsColor: .systemIndigo)
        case .deck: Color(nsColor: .systemTeal)
        case .developer: Color(white: 0.15)
        case .privacy: Color(nsColor: .systemBlue)
        }
    }

    /// Words the sidebar search matches, beyond the title.
    var keywords: [String] {
        switch self {
        case .general: ["search", "brave", "api", "key", "results"]
        case .appearance: ["theme", "dark", "light", "accent", "color", "glass", "gap", "corner", "radius", "width", "trail", "layout"]
        case .deck: ["sink", "tabs", "waterline", "playing", "unsaved", "afloat"]
        case .developer: ["editor", "cursor", "vs code", "zed", "xcode", "localhost", "ports", "devtools"]
        case .privacy: ["cookies", "data", "clear", "history", "website"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || keywords.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
