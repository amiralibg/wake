import SwiftUI

extension FocusedValues {
    @Entry var browser: BrowserModel?
}

struct BrowserCommands: Commands {
    @FocusedValue(\.browser) private var focusedBrowser

    /// SwiftUI's focused value can be nil while a WKWebView is first responder,
    /// which made ⌘W fall through to closing the window. The key window's model
    /// is the fallback.
    private var browser: BrowserModel? { focusedBrowser ?? BrowserModel.active }

    /// Read in `body` so the menus rebuild when a shortcut changes.
    @AppStorage(ShortcutStore.defaultsKey) private var shortcutOverrides = ""
    private var shortcuts: ShortcutStore {
        _ = shortcutOverrides
        return .shared
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            item(.checkForUpdates, "Check for Updates…")
                .disabled(!AppUpdater.shared.canCheckForUpdates)
        }

        CommandGroup(replacing: .appSettings) {
            item(.settings, "Settings…")
            item(.extensions, "Extensions…")
            item(.showShortcuts, "Keyboard Shortcuts…")
        }

        CommandGroup(after: .newItem) {
            item(.newColumn)
            item(.newThread)
            item(.openLocation, "Open Location…")
            item(.openFile, "Open File…")
            item(.reopenColumn)
            item(.duplicateColumn)
            Divider()
            item(.importData, "Import from Another Browser…")
            item(.addExtension, "Add Extension…")
                .disabled(!Extensions.isSupported)
            Divider()
            // ⌘W closes the column (or overlay); ⇧⌘W the window, as in Safari. The
            // action looks the browser up when it runs, so it never goes stale.
            item(.closeColumn)
            item(.closeWindow)
        }

        // A browser has nothing to save. Replacing this group also removes SwiftUI's
        // own "Close" item, which would claim ⌘W as well.
        CommandGroup(replacing: .saveItem) {}

        CommandGroup(after: .pasteboard) {
            Divider()
            item(.copyAddress)
            Divider()
            item(.findInPage, "Find…")
            item(.findNext)
            item(.findPrevious)
        }

        CommandGroup(after: .toolbar) {
            item(.zen, browser?.isZen == true ? "Leave Zen" : "Enter Zen")
            Divider()
            item(.zoomIn, "Zoom In")
            item(.zoomOut, "Zoom Out")
            item(.actualSize, "Actual Size")
            Divider()
            item(.widerColumn, "Wider Column")
            item(.narrowerColumn, "Narrower Column")
            item(.defaultColumnWidth, "Default Column Width")
            if let page = browser?.webPage, let url = page.url, SiteWidthRules.canHaveRule(url) {
                if SiteWidthRules.shared.minimumWidth(for: url) == nil {
                    Button("Keep This Width on This Site") { browser?.keepWidthForSite(of: page) }
                        .disabled((browser?.trail.columns.count ?? 0) < 2)
                } else {
                    Button("Forget Width for This Site") { SiteWidthRules.shared.forget(url) }
                }
            }
        }

        CommandMenu("Go") {
            item(.commandPalette, "Command Palette")
            Divider()
            item(.previousColumn, "Previous Column")
            item(.nextColumn, "Next Column")
            item(.columnLeft, "Column to the Left")
            item(.columnRight, "Column to the Right")
            item(.showAllColumns, "Show All Columns")
            item(.cycleColumns, "Cycle Columns")
            item(.cycleColumnsBackwards, "Cycle Columns Backwards")
            Menu("Column") {
                ForEach(1..<9) { number in
                    Button("Column \(number)") { browser?.trail.focus(number - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
                item(.lastColumn, "Last Column")
            }
            Divider()
            item(.moveColumnLeft, "Move Column Left")
            item(.moveColumnRight, "Move Column Right")
            Divider()
            item(.back, "Back in Page")
            item(.forward, "Forward in Page")
            Divider()
            item(.reload, "Reload Page")
            item(.reloadWithoutCache, "Reload Without Cache")
            item(.stopLoading, "Stop Loading")
            Divider()
            item(.popOut, "Pop Out Element…")
            if ContentBlocker.shared.isEnabled {
                item(.allowAdsOnSite, ContentBlocker.shared.isAllowed(browser?.webPage?.url) ? "Block Ads on This Site" : "Allow Ads on This Site")
            }
        }

        CommandMenu("Moments") {
            item(.saveMoment, "Save Moment")
            item(.moments, browser?.isMomentsOpen == true ? "Hide Moments" : "Show Moments")
            item(.history, "Show History")
            item(.searches, "Show Searches")
            Divider()
            ForEach(MomentShelf.smart, id: \.self) { shelf in
                Button(shelf.title) { browser?.showMoments(shelf) }
            }
        }

        CommandMenu("Develop") {
            item(.developerMode, browser?.webPage?.isDeveloperMode == true ? "Turn Off Developer Mode for Thread" : "Turn On Developer Mode for Thread")
            Button("Developer Mode: Automatic") { browser?.resetDeveloperMode() }
                .disabled(browser?.thread.developerMode == nil)
            Divider()
            item(.devTools, "DevTools")
            item(.webInspector, "Web Inspector")
            item(.inspectElement, "Inspect Element")
            item(.console, "JavaScript Console")
            item(.pageSource, "Show Page Source")
            item(.network, "Network")
            item(.storage, "Storage")
            item(.performance, "Performance & Audit")
            Divider()
            item(.emptyCaches, "Empty Caches")
            item(.inspectComponents, "Inspect Components")
            item(.responsivePreview, "Responsive Preview")
            Menu("Preview on Device") {
                DevicePresetButtons { browser?.openResponsivePreview($0) }
            }
            Divider()
            Button("Projects & Environments…") { browser?.showSettings(.developer) }
        }

        CommandMenu("Apps") {
            item(.pinApp, "Pin Page as App")
            Divider()
            ForEach(Array((browser?.apps.apps ?? []).prefix(9).enumerated()), id: \.element.id) { index, app in
                Button(app.title) { browser?.toggleApp(index: index) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
        }
    }

    /// A menu item for a registered command, with the keys Settings ▸ Shortcuts gives it.
    private func item(_ command: WakeCommand, _ title: String? = nil) -> some View {
        Button(title ?? command.title) { command.perform(in: browser) }
            .keyboardShortcut(shortcuts.combo(for: command)?.keyboardShortcut)
    }
}
