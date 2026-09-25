import SwiftUI

struct GeneralSettingsSection: View {
    @Environment(BrowsingSettings.self) private var browsing

    var body: some View {
        @Bindable var browsing = browsing
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Browsing") {
                SettingsRow(label: "Clicked links open", detail: "⌘-click opens a column in the background; ⌥-click stays on the page.") {
                    Picker("", selection: $browsing.linksOpenInNewColumn) {
                        Text("In a new column").tag(true)
                        Text("In the same page").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(label: "Resume your last thread", detail: "New windows pick up where you left off.") {
                    Toggle("", isOn: $browsing.restoresLastThread)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(label: "Apps and dev servers", detail: "The capsule on the left. Hidden, it slides in when the pointer reaches the window's left edge.") {
                    Picker("", selection: $browsing.capsuleHidesAtEdge) {
                        Text("Always shown").tag(false)
                        Text("At left edge").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SearchKeyGroup()
            ShortcutsGroup()
        }
    }
}

private struct SearchKeyGroup: View {
    @State private var key = SearchKeyStore.braveAPIKey ?? ""
    @State private var saved = false

    var body: some View {
        SettingsGroup(title: "Search") {
            SettingsRow(
                label: "Brave Search API key",
                detail: "Shows real results inside ⌘K. Stored in your Keychain. Without a key, ⌘K shows suggestions and can open DuckDuckGo."
            ) {
                HStack(spacing: 8) {
                    SecureField("Paste key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit(save)
                    Button(saved ? "Saved" : "Save", action: save)
                        .disabled(saved)
                }
            }
            SettingsDivider()
            SettingsRow(label: "Get a free key") {
                Link("api-dashboard.search.brave.com", destination: URL(string: "https://api-dashboard.search.brave.com/")!)
                    .font(.system(size: 12))
            }
        }
        .onChange(of: key) { saved = false }
    }

    private func save() {
        SearchKeyStore.braveAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        saved = true
    }
}

/// A reference card of Wake's keyboard shortcuts.
private struct ShortcutsGroup: View {
    private let shortcuts: [(String, String)] = [
        ("Open the Deck and search", "⌘K"),
        ("New column", "⌘T"),
        ("Go to address in this column", "⌘L"),
        ("Close column · close window", "⌘W  ⇧⌘W"),
        ("Reopen closed column", "⇧⌘T"),
        ("Duplicate column", "⇧⌘D"),
        ("Previous / next column", "⌘[  ⌘]"),
        ("Cycle columns", "⌃⇥  ⌃⇧⇥"),
        ("Jump to column 1–8 · last", "⌘1 … ⌘8  ⌘9"),
        ("Move column left / right", "⌃⌘←  ⌃⌘→"),
        ("Wider / narrower column · default", "⌥⌘=  ⌥⌘−  ⌥⌘0"),
        ("Zoom in / out · actual size", "⌘=  ⌘−  ⌘0"),
        ("Back / forward in page", "⌥⌘[  ⌥⌘]"),
        ("Reload · without cache · stop", "⌘R  ⌥⌘R  ⌘."),
        ("Copy page address", "⇧⌘C"),
        ("New thread", "⇧⌘N"),
        ("DevTools · responsive preview", "⌥⌘I  ⌥⌘P"),
        ("Pin page as app", "⇧⌘P"),
        ("Show pinned app 1–9", "⌃1 … ⌃9"),
        ("Zen", "⌘\\"),
        ("Settings", "⌘,"),
    ]

    var body: some View {
        SettingsGroup(title: "Keyboard shortcuts") {
            ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                if index > 0 { SettingsDivider() }
                HStack {
                    Text(shortcut.0).font(.system(size: 13))
                    Spacer()
                    Text(shortcut.1)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.primary.opacity(0.07), in: .rect(cornerRadius: 5, style: .continuous))
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
            }
        }
    }
}
