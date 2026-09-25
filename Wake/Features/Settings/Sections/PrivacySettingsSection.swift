import SwiftUI
import WebKit

struct PrivacySettingsSection: View {
    @State private var confirming: Action?
    @State private var done: Set<Action> = []

    private enum Action: Identifiable {
        case history, websiteData
        var id: Self { self }
    }

    var body: some View {
        SettingsGroup(title: "Your data") {
            SettingsRow(
                label: "Clear browsing history",
                detail: "Forgets visited pages shown under Recent in ⌘K. Threads and pinned apps stay."
            ) {
                Button(done.contains(.history) ? "Cleared" : "Clear…") { confirming = .history }
                    .disabled(done.contains(.history))
            }
            SettingsDivider()
            SettingsRow(
                label: "Clear cookies and website data",
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
            ThreadStore.shared.clearVisits()
            done.insert(.history)
        case .websiteData:
            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                done.insert(.websiteData)
            }
        }
    }
}
