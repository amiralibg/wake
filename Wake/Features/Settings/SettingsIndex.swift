import Foundation

/// One setting, as search finds it. Rows built with `SettingsRow(_ id:)` take their
/// label and description from here, so what search shows is what the row says.
struct SettingsEntry: Identifiable, Hashable, Sendable {
    let id: String
    let section: SettingsSection
    var group: String?
    let label: String
    var detail: String?
    /// Other words for it: synonyms, other browsers' names, what it's about.
    var keywords: [String] = []

    /// "Appearance › Trail layout"
    var path: String {
        [section.title, group].compactMap(\.self).joined(separator: " › ")
    }
}

extension SettingsEntry {
    static func entry(_ id: ID) -> SettingsEntry? { byID[id] }

    private static let byID: [ID: SettingsEntry] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Every setting, plus one entry per command in Shortcuts.
    static let all: [SettingsEntry] = settings + WakeCommand.allCases.map { command in
        SettingsEntry(
            id: "shortcut.\(command.rawValue)", section: .shortcuts, group: command.category.title,
            label: command.title, detail: "Keyboard shortcut", keywords: command.keywords + ["shortcut", "keys"]
        )
    }

    private static let settings: [SettingsEntry] = [
        // General
        SettingsEntry(id: "linksOpen", section: .general, group: "Browsing", label: "Clicked links open",
                      detail: "⌘-click opens a column in the background; ⌥-click stays on the page.",
                      keywords: ["new column", "same page", "tabs", "target", "background"]),
        SettingsEntry(id: "resumeThread", section: .general, group: "Browsing", label: "Resume your last thread",
                      detail: "New windows pick up where you left off.",
                      keywords: ["restore", "session", "startup", "reopen", "launch"]),
        SettingsEntry(id: "shiftScroll", section: .general, group: "Browsing", label: "⇧-scroll moves between columns",
                      detail: "With a mouse wheel. Off, ⇧-scroll scrolls the page sideways.",
                      keywords: ["shift", "mouse", "wheel", "horizontal", "scroll"]),
        SettingsEntry(id: "capsule", section: .general, group: "Browsing", label: "Apps and dev servers",
                      detail: "The capsule on the left. Hidden, it slides in when the pointer reaches the window's left edge.",
                      keywords: ["capsule", "sidebar", "pinned", "apps", "left edge", "hide"]),
        SettingsEntry(id: "siteWidths", section: .general, group: "Site widths", label: "Minimum column width",
                      detail: "For sites that need room. * matches anything: github.com/* covers all of GitHub. To add the site you're on, choose View ▸ Keep This Width on This Site.",
                      keywords: ["site", "width", "wide", "github", "rules", "per site"]),
        SettingsEntry(id: "updates", section: .general, group: "Updates", label: "Check for updates",
                      keywords: ["version", "upgrade", "sparkle", "release", "about"]),
        SettingsEntry(id: "autoUpdate", section: .general, group: "Updates", label: "Check automatically",
                      detail: "Once a day. You choose when to install.",
                      keywords: ["automatic", "updates", "daily"]),
        SettingsEntry(id: "welcomeTour", section: .general, label: "Welcome tour",
                      detail: "The trail, your look, search and shortcuts, one screen each.",
                      keywords: ["onboarding", "intro", "tutorial", "help", "start"]),

        // Shortcuts
        SettingsEntry(id: "columnMode", section: .shortcuts, group: "Keyboard", label: "Column mode with ⌃W",
                      detail: "Like Vim's window keys: ⌃W, then h and l to move, H and L to reorder, x to close. Turn off if a site needs ⌃W.",
                      keywords: ["vim", "control w", "ctrl w", "window keys", "keyboard"]),

        // Search
        SettingsEntry(id: "searchEngine", section: .search, group: "Search engine", label: "Search engine",
                      detail: "Typed words in ⌘K and the address bar search here.",
                      keywords: ["default", "duckduckgo", "google", "brave", "bing", "ecosia", "startpage", "kagi", "perplexity", "yahoo", "custom", "%s"]),
        SettingsEntry(id: "suggestions", section: .search, label: "Search suggestions",
                      detail: "Suggestions while you type. Off, nothing leaves Wake until you press ↩.",
                      keywords: ["autocomplete", "privacy", "typing", "complete"]),
        SettingsEntry(id: "braveKey", section: .search, group: "Results inside ⌘K", label: "Brave Search API key",
                      detail: "Optional. Shows real results in the palette without opening a page. Stored in your Keychain.",
                      keywords: ["api", "key", "results", "palette", "token"]),

        // Appearance
        SettingsEntry(id: "theme", section: .appearance, label: "Theme",
                      keywords: ["dark", "light", "auto", "mode", "night", "system"]),
        SettingsEntry(id: "accent", section: .appearance, label: "Accent color",
                      keywords: ["colour", "tint", "highlight", "blue", "purple", "pink", "orange", "green"]),
        SettingsEntry(id: "glass", section: .appearance, label: "Glass",
                      keywords: ["blur", "transparency", "translucent", "liquid glass", "frosted", "material"]),
        SettingsEntry(id: "gap", section: .appearance, group: "Trail layout", label: "Gap between pages",
                      keywords: ["spacing", "margin", "padding", "space", "gutter"]),
        SettingsEntry(id: "cornerRadius", section: .appearance, group: "Trail layout", label: "Corner radius",
                      keywords: ["rounded", "round", "corners", "radius", "square", "shape"]),
        SettingsEntry(id: "pageWidth", section: .appearance, group: "Trail layout", label: "Page width",
                      keywords: ["column width", "columns per screen", "balanced", "wide", "narrow", "layout"]),

        // Deck
        SettingsEntry(id: "sinkAfter", section: .deck, label: "Sink tabs after",
                      detail: "Untouched tabs sink below the waterline. They stay searchable.",
                      keywords: ["waterline", "old tabs", "archive", "time", "hours"]),
        SettingsEntry(id: "keepAfloat", section: .deck, label: "Keep playing and unsaved tabs afloat",
                      keywords: ["audio", "video", "media", "forms", "unsaved"]),
        SettingsEntry(id: "bottomEdge", section: .deck, label: "Show the Deck from the bottom edge",
                      detail: "Move the pointer to the bottom of the window to see your threads. ⌘K always opens it.",
                      keywords: ["peek", "hover", "edge", "pointer", "bottom"]),

        // Passwords
        SettingsEntry(id: "passwordsOffer", section: .passwords, group: "Options", label: "Offer to save passwords",
                      detail: "After you sign in, Wake asks whether to keep the password.",
                      keywords: ["save", "remember", "logins", "credentials", "password manager"]),
        SettingsEntry(id: "passwordsAutofill", section: .passwords, group: "Options", label: "Fill passwords",
                      detail: "Saved logins appear under a sign-in field.",
                      keywords: ["autofill", "auto fill", "login", "username", "suggest"]),
        SettingsEntry(id: "passwordsAuth", section: .passwords, group: "Options", label: "Ask for Touch ID",
                      detail: "Before filling or showing a password. Not again for 5 minutes.",
                      keywords: ["touch id", "biometric", "lock", "security", "fingerprint"]),
        SettingsEntry(id: "passwordsImport", section: .passwords, label: "Import passwords",
                      detail: "From Chrome, Arc, Brave, Edge and other Chromium browsers, or a CSV file from Safari, Firefox or 1Password.",
                      keywords: ["import", "migrate", "csv", "chrome", "safari", "firefox", "1password", "bitwarden"]),
        SettingsEntry(id: "passwordsExport", section: .passwords, label: "Export passwords",
                      detail: "As a CSV file other password managers can read.",
                      keywords: ["export", "csv", "backup"]),
        SettingsEntry(id: "passwordsList", section: .passwords, label: "Saved passwords",
                      keywords: ["logins", "accounts", "reused", "weak", "security", "generate"]),

        // Extensions
        SettingsEntry(id: "extensionFile", section: .extensions, group: "More ways", label: "Add from a file or folder",
                      detail: "A .crx, .xpi or .zip, or an unpacked extension folder. You can also drop one here.",
                      keywords: ["install", "crx", "xpi", "zip", "unpacked", "sideload", "add-on", "plugin"]),
        SettingsEntry(id: "extensionUpdates", section: .extensions, group: "More ways", label: "Keep extensions up to date",
                      keywords: ["update", "extensions", "store"]),
        SettingsEntry(id: "extensionStores", section: .extensions, label: "Get extensions",
                      detail: "From the Chrome Web Store, Edge Add-ons and Firefox Add-ons.",
                      keywords: ["chrome web store", "firefox", "edge", "ublock", "ad blocker", "dark reader", "1password", "bitwarden", "add-ons", "plugins"]),

        // Developer
        SettingsEntry(id: "devAuto", section: .developer, group: "Developer mode", label: "On automatically for localhost",
                      detail: "Captures console, network and hot reload for local dev servers. Any thread can switch it on or off (⌥⌘D).",
                      keywords: ["localhost", "developer", "dev mode", "hmr"]),
        SettingsEntry(id: "findServers", section: .developer, group: "Developer mode", label: "Find local dev servers",
                      detail: "Checks common ports and lists them in the app capsule.",
                      keywords: ["ports", "3000", "5173", "8080", "vite", "next", "scan"]),
        SettingsEntry(id: "editor", section: .developer, group: "Developer mode", label: "Open in editor",
                      detail: "Where console errors and inspected components open.",
                      keywords: ["vs code", "vscode", "cursor", "zed", "xcode", "sublime", "ide"]),
        SettingsEntry(id: "webInspector", section: .developer, group: "Developer mode", label: "Web Inspector",
                      detail: "WebKit's full inspector (debugger, Timelines, Layers).",
                      keywords: ["inspect element", "debugger", "safari", "devtools"]),
        SettingsEntry(id: "projects", section: .developer, group: "Projects", label: "Projects and environments",
                      keywords: ["staging", "production", "local", "git", "branch", "environments"]),

        // Privacy
        SettingsEntry(id: "importBrowser", section: .privacy, group: "Bring your data", label: "Import from another browser",
                      detail: "History, searches, cookies and site storage from Chrome, Arc, Dia, Brave, Edge, Firefox, Zen, Safari and more.",
                      keywords: ["migrate", "chrome", "arc", "firefox", "safari", "zen", "brave", "edge", "cookies"]),
        SettingsEntry(id: "clearHistory", section: .privacy, group: "Your data", label: "Clear browsing history",
                      detail: "Forgets visited pages and searches (History, and Recent in ⌘K). Threads and pinned apps stay.",
                      keywords: ["delete", "erase", "remove", "history", "forget"]),
        SettingsEntry(id: "clearData", section: .privacy, group: "Your data", label: "Clear cookies and website data",
                      detail: "Signs you out of every site and removes caches, local storage and cookies.",
                      keywords: ["cookies", "cache", "storage", "sign out", "logout", "site data"]),
    ]
}

// MARK: - Search

/// Ranks entries for what's typed: every word has to match something. A word at the
/// start of the label beats one inside it, the label beats keywords, keywords beat
/// the description, and a one-letter typo ("cornr") still finds its word.
enum SettingsSearch {
    static func results(for query: String, in entries: [SettingsEntry] = SettingsEntry.all, limit: Int = 12) -> [SettingsEntry] {
        let words = tokens(query)
        guard !words.isEmpty else { return [] }
        return entries
            .compactMap { entry in score(words, label: entry.label, keywords: entry.keywords, context: [entry.section.title, entry.group ?? ""], detail: entry.detail).map { (entry, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Commands in ⌘K, ranked the same way.
    static func commands(for query: String, limit: Int = 5) -> [WakeCommand] {
        let words = tokens(query)
        guard !words.isEmpty else { return [] }
        return WakeCommand.allCases
            .compactMap { command in score(words, label: command.title, keywords: command.keywords, context: [command.category.title], detail: nil).map { (command, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    static func tokens(_ text: String) -> [String] {
        fold(text).split(whereSeparator: { $0.isWhitespace || $0 == "›" }).map(String.init)
    }

    /// The best score for the words, or nil if any word matches nothing.
    static func score(_ words: [String], label: String, keywords: [String], context: [String], detail: String?) -> Int? {
        let label = fold(label)
        let labelWords = split(label)
        let keywords = keywords.map(fold)
        let keywordWords = keywords.flatMap(split)
        let context = context.map(fold)
        let detail = detail.map(fold) ?? ""
        var total = 0
        for word in words {
            var best = 0
            if labelWords.first?.hasPrefix(word) == true { best = 40 }
            else if labelWords.contains(where: { $0.hasPrefix(word) }) { best = 32 }
            else if label.contains(word) { best = 22 }
            else if keywords.contains(where: { $0.hasPrefix(word) }) || keywordWords.contains(where: { $0.hasPrefix(word) }) { best = 18 }
            else if keywords.contains(where: { $0.contains(word) }) { best = 12 }
            else if context.contains(where: { $0.hasPrefix(word) }) { best = 10 }
            else if word.count >= 3, detail.contains(word) { best = 6 }
            else if word.count >= 4, (labelWords + keywordWords).contains(where: { isTypo(word, of: $0) }) { best = 8 }
            guard best > 0 else { return nil }
            total += best
        }
        // Shorter labels are more likely the one meant ("Theme" over "Theme colour…").
        return total * 100 - label.count
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func split(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// One edit away (two for long words) from the start of `candidate`, so "cornr"
    /// finds "corner" and "apperance" finds "appearance".
    private static func isTypo(_ word: String, of candidate: String) -> Bool {
        let allowed = word.count >= 7 ? 2 : 1
        let prefix = String(candidate.prefix(word.count + allowed))
        guard abs(prefix.count - word.count) <= allowed else { return false }
        return min(distance(word, prefix), distance(word, String(candidate.prefix(word.count)))) <= allowed
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
