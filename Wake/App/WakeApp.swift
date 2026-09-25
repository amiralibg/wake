import SwiftData
import SwiftUI

@main
struct WakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appearance = AppearanceSettings()
    @State private var deck = DeckSettings()
    @State private var developer = DeveloperSettings.shared

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(appearance)
                .environment(deck)
                .environment(developer)
                .environment(ThumbnailStore.shared)
                .environment(MomentStore.shared)
                .environment(BrowsingSettings.shared)
                .modelContainer(ThreadStore.shared.container)
                .onAppear(perform: appearance.applyTheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1352, height: 832)
        .commands { BrowserCommands() }
    }
}
