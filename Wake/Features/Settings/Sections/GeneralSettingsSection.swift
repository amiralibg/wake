import SwiftUI

struct GeneralSettingsSection: View {
    @Environment(BrowsingSettings.self) private var browsing
    @Environment(BrowserModel.self) private var browser
    @AppStorage(OnboardingView.completedKey) private var onboardingCompleted = true

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
                SettingsRow(label: "⇧-scroll moves between columns", detail: "With a mouse wheel. Off, ⇧-scroll scrolls the page sideways.") {
                    Toggle("", isOn: $browsing.shiftScrollMovesColumns)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(label: "Column mode with ⌃W", detail: "Like Vim's window keys: ⌃W, then h and l to move, H and L to reorder, x to close. Turn off if a site needs ⌃W.") {
                    Toggle("", isOn: $browsing.columnModeKeyEnabled)
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
            UpdatesGroup()
            SettingsGroup {
                SettingsRow(label: "Welcome tour", detail: "The trail, your look, search and shortcuts, one screen each.") {
                    Button("Show Welcome Tour") {
                        browser.hideSettings()
                        withAnimation(.easeInOut(duration: 0.45)) { onboardingCompleted = false }
                    }
                }
            }
            ShortcutsGroup()
        }
    }
}

/// Wake's version and Sparkle's update settings.
private struct UpdatesGroup: View {
    @State private var updater = AppUpdater.shared

    var body: some View {
        SettingsGroup(title: "Updates") {
            SettingsRow(label: "Wake \(updater.version)", detail: detail) {
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            if updater.isAvailable {
                SettingsDivider()
                SettingsRow(label: "Check automatically", detail: "Once a day. You choose when to install.") {
                    Toggle("", isOn: $updater.automaticallyChecks)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }

    private var detail: String {
        guard updater.isAvailable else { return "Updates are off in this build: it has no update signing key." }
        guard let last = updater.lastChecked else { return "New versions come from GitHub releases." }
        return "Last checked \(last.formatted(.relative(presentation: .named)))."
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
        ("Previous / next column with a mouse", "⇧ scroll"),
        ("Column mode, then focus · move · jump", "⌃W  h l  H L  1–9"),
        ("In column mode: width · close · new · done", "< > =  x  n  esc"),
        ("Jump to column 1–8 · last", "⌘1 … ⌘8  ⌘9"),
        ("Move column left / right", "⌃⌘←  ⌃⌘→"),
        ("Wider / narrower column · default", "⌥⌘=  ⌥⌘−  ⌥⌘0"),
        ("Zoom in / out · actual size", "⌘=  ⌘−  ⌘0"),
        ("Back / forward in page", "⌥⌘[  ⌥⌘]"),
        ("Reload · without cache · stop", "⌘R  ⌥⌘R  ⌘."),
        ("Copy page address", "⇧⌘C"),
        ("History · searches", "⌘Y  ⌥⌘Y"),
        ("New thread", "⇧⌘N"),
        ("DevTools · responsive preview", "⌥⌘I  ⌥⌘P"),
        ("Web Inspector · inspect element", "⌥⇧⌘I  ⌥⇧⌘C"),
        ("Console · page source · empty caches", "⌥⌘J  ⌥⌘U  ⌥⌘E"),
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
