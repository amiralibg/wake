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
            BlockingGroup()
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

/// Built-in ad and tracker blocking.
private struct BlockingGroup: View {
    @State private var blocker = ContentBlocker.shared

    var body: some View {
        SettingsGroup(title: "Blocking") {
            SettingsRow("blockAds", detail: detail) {
                HStack(spacing: 8) {
                    if blocker.status == .updating { ProgressView().controlSize(.small) }
                    if blocker.isEnabled {
                        Button("Update Lists") { blocker.update() }
                            .disabled(blocker.status == .updating)
                    }
                    Toggle("", isOn: $blocker.isEnabled).toggleStyle(.switch).labelsHidden()
                }
            }
            if blocker.isEnabled {
                SettingsDivider()
                SettingsRow("blockAllowed", detail: blocker.allowedSites.isEmpty ? "None. Use Go ▸ Allow Ads on This Site, or ⌘K, on a site that breaks." : nil) {
                    EmptyView()
                }
                ForEach(blocker.allowedSites, id: \.self) { site in
                    HStack {
                        Text(site).font(.system(size: 13))
                        Spacer()
                        Button("Remove") { blocker.removeAllowed(site) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                }
            }
        }
    }

    private var detail: String {
        switch blocker.status {
        case .off: "EasyList and EasyPrivacy, applied inside WebKit. Pages load less, so they use less memory and CPU."
        case .updating: "Downloading and compiling the filter lists…"
        case .ready(let rules, let updated): "\(rules.formatted()) rules, updated \(updated.formatted(.relative(presentation: .named)))."
        case .failed(let message): message
        }
    }
}
