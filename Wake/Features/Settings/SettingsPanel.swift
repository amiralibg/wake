import SwiftUI

/// Settings, floating inside the browser window as a glass panel: a sidebar of
/// sections and a content card.
struct SettingsPanel: View {
    @Bindable var browser: BrowserModel

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $browser.settingsSection, onClose: browser.hideSettings)
                .frame(width: 214)
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

    @ViewBuilder private var content: some View {
        switch browser.settingsSection {
        case .general: GeneralSettingsSection()
        case .appearance: AppearanceSettingsSection()
        case .deck: DeckSettingsSection()
        case .developer: DeveloperSettingsSection()
        case .privacy: PrivacySettingsSection()
        }
    }
}
