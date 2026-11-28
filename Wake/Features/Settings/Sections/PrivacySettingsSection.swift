import SwiftUI
import WebKit

struct PrivacySettingsSection: View {
    @Environment(BrowserModel.self) private var browser
    @State private var confirming: Action?
    @State private var done: Set<Action> = []

    private enum Action: Identifiable {
        case history, websiteData
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Bring your data") {
                SettingsRow(
                    "importBrowser",
                    detail: "History, searches, cookies and site storage from Chrome, Arc, Dia, Brave, Edge, Firefox, Zen, Safari and more."
                ) {
                    Button("Import…") {
                        browser.hideSettings()
                        browser.isImportingBrowserData = true
                    }
                }
            }
            dataGroup
        }
    }

    private var dataGroup: some View {
        SettingsGroup(title: "Your data") {
            SettingsRow(
                "clearHistory",
                detail: "Forgets visited pages and searches (History, and Recent in ⌘K). Threads and pinned apps stay."
            ) {
                Button(done.contains(.history) ? "Cleared" : "Clear…") { confirming = .history }
                    .disabled(done.contains(.history))
            }
            SettingsDivider()
            SettingsRow(
                "clearData",
                detail: "Signs you out of every site and removes caches, local storage and cookies."
            ) {
                Button(done.contains(.websiteData) ? "Cleared" : "Clear…") { confirming = .websiteData }
                    .disabled(done.contains(.websiteData))
            }
        }
        .confirmationDialog(title, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Clear", role: .destructive) { if let confirming { perform(confirming) } }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var title: String {
        confirming == .history ? "Clear browsing history?" : "Clear all website data?"
    }

    private func perform(_ action: Action) {
        switch action {
        case .history:
            HistoryStore.shared.clearAll()
            done.insert(.history)
        case .websiteData:
            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                done.insert(.websiteData)
            }
        }
    }
}
