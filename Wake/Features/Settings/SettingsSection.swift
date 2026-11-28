import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, shortcuts, search, appearance, deck, passwords, extensions, developer, privacy

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .shortcuts: "command"
        case .search: "magnifyingglass"
        case .appearance: "circle.lefthalf.filled"
        case .deck: "rectangle.on.rectangle"
        case .passwords: "key.fill"
        case .extensions: "puzzlepiece.extension.fill"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .privacy: "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(nsColor: .systemGray)
        case .shortcuts: Color(nsColor: .systemGreen)
        case .search: Color(nsColor: .systemOrange)
        case .appearance: Color(nsColor: .systemIndigo)
        case .deck: Color(nsColor: .systemTeal)
        case .passwords: Color(red: 0.35, green: 0.46, blue: 0.62)
        case .extensions: Color(nsColor: .systemPurple)
        case .developer: Color(white: 0.15)
        case .privacy: Color(nsColor: .systemBlue)
        }
    }

    /// Words the sidebar search matches, beyond the title.
    var keywords: [String] {
        switch self {
        case .general: ["links", "columns", "restore", "capsule", "welcome", "onboarding", "tour", "updates"]
        case .shortcuts: ["keyboard", "keys", "hotkeys", "keybindings", "commands"]
        case .search: ["engine", "default", "duckduckgo", "google", "brave", "bing", "ecosia", "startpage", "kagi", "perplexity", "yahoo", "custom", "suggestions", "api", "key", "results"]
        case .appearance: ["theme", "dark", "light", "accent", "color", "glass", "gap", "corner", "radius", "width", "trail", "layout"]
        case .deck: ["sink", "tabs", "waterline", "playing", "unsaved", "afloat"]
        case .passwords: ["logins", "autofill", "keychain", "credentials", "sign in", "password manager"]
        case .extensions: ["add-ons", "addons", "plugins", "chrome web store", "firefox", "crx", "xpi", "ad blocker", "ublock"]
        case .developer: ["editor", "cursor", "vs code", "zed", "xcode", "localhost", "ports", "devtools"]
        case .privacy: ["cookies", "data", "clear", "history", "website", "import", "chrome", "firefox", "safari", "arc"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query)
            || keywords.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
