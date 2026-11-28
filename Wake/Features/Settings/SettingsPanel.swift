import SwiftUI

/// Settings, floating inside the browser window as a glass panel: a sidebar of
/// sections and a content card.
struct SettingsPanel: View {
    @Bindable var browser: BrowserModel
    /// The row outlined after a jump; cleared after a moment.
    @State private var highlight: SettingsEntry.ID?

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(browser: browser)
                .frame(width: 214)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(browser.settingsSection.title)
                            .font(.system(size: 20, weight: .bold))
                        content
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
                .environment(\.settingsHighlight, highlight)
                .task(id: browser.settingsFocus) { await reveal(browser.settingsFocus, with: proxy) }
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.92), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 0.5))
            .padding([.vertical, .trailing], 8)
            .id(browser.settingsSection)
            .transition(.opacity)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.45), in: .rect(cornerRadius: 16, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), vibrantContent: false)
        .shadow(color: .black.opacity(0.35), radius: 45, y: 30)
        .animation(.snappy, value: browser.settingsSection)
    }

    /// Scrolls to the row search chose and outlines it for a moment.
    private func reveal(_ id: SettingsEntry.ID?, with proxy: ScrollViewProxy) async {
        guard let id else {
            highlight = nil
            return
        }
        // The section may have just switched: let its rows lay out first.
        try? await Task.sleep(for: .milliseconds(60))
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.3)) }
        highlight = id
        try? await Task.sleep(for: .seconds(1.6))
        guard !Task.isCancelled else { return }
        highlight = nil
    }

    @ViewBuilder private var content: some View {
        switch browser.settingsSection {
        case .general: GeneralSettingsSection()
        case .shortcuts: ShortcutsSettingsSection()
        case .search: SearchSettingsSection()
        case .appearance: AppearanceSettingsSection()
        case .deck: DeckSettingsSection()
        case .passwords: PasswordsSettingsSection()
        case .extensions: ExtensionsSettingsSection()
        case .developer: DeveloperSettingsSection()
        case .privacy: PrivacySettingsSection()
        }
    }
}
