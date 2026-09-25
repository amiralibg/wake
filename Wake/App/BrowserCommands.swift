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

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { browser?.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("New Column") { browser?.showPalette(target: .newColumn) }
                .keyboardShortcut("t", modifiers: .command)
            Button("New Thread") { browser?.newThread() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open Location…") { browser?.showPalette(target: .currentColumn) }
                .keyboardShortcut("l", modifiers: .command)
            Button("Reopen Closed Column") { browser?.trail.reopenClosed() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Duplicate Column") { browser?.trail.duplicateFocused() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            // ⌘W closes the column (or overlay); ⇧⌘W the window, as in Safari. The
            // action looks the browser up when it runs, so it never goes stale.
            Button("Close Column") { closeCommand() }
                .keyboardShortcut("w", modifiers: .command)
            Button("Close Window") {
                if let panel = NSApp.keyWindow as? PopOutPanel {
                    panel.popOut.onClose()
                } else {
                    (browser?.window ?? NSApp.keyWindow)?.performClose(nil)
                }
            }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        // A browser has nothing to save. Replacing this group also removes SwiftUI's
        // own "Close" item, which would claim ⌘W as well.
        CommandGroup(replacing: .saveItem) {}

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Page Address") { browser?.copyPageURL() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button(browser?.isZen == true ? "Leave Zen" : "Enter Zen") {
                withAnimation(.trail) { browser?.isZen.toggle() }
            }
            .keyboardShortcut("\\", modifiers: .command)
            Divider()
            Button("Zoom In") { browser?.webPage?.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { browser?.webPage?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { browser?.webPage?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Wider Column") { browser?.trail.resizeFocused(by: 0.1) }
                .keyboardShortcut("=", modifiers: [.command, .option])
            Button("Narrower Column") { browser?.trail.resizeFocused(by: -0.1) }
                .keyboardShortcut("-", modifiers: [.command, .option])
            Button("Default Column Width") { if let page = browser?.page { browser?.trail.resetWidth(of: page) } }
                .keyboardShortcut("0", modifiers: [.command, .option])
        }

        CommandMenu("Go") {
            Button("Command Palette") { browser?.togglePalette() }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Previous Column") { browser?.trail.focusPrevious() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Next Column") { browser?.trail.focusNext() }
                .keyboardShortcut("]", modifiers: .command)
            Button("Cycle Columns") { browser?.trail.cycleFocus(forward: true) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Cycle Columns Backwards") { browser?.trail.cycleFocus(forward: false) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Menu("Column") {
                ForEach(1..<9) { number in
                    Button("Column \(number)") { browser?.trail.focus(number - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
                Button("Last Column") { browser.map { $0.trail.focus($0.trail.columns.count - 1) } }
                    .keyboardShortcut("9", modifiers: .command)
            }
            Divider()
            Button("Move Column Left") { browser?.trail.moveFocused(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
            Button("Move Column Right") { browser?.trail.moveFocused(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
            Divider()
            Button("Back in Page") { browser?.page?.goBack() }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button("Forward in Page") { browser?.page?.goForward() }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Divider()
            Button("Reload Page") { browser?.webPage?.reload() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Reload Without Cache") { browser?.webPage?.reloadFromOrigin() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Stop Loading") { browser?.webPage?.stopLoading() }
                .keyboardShortcut(".", modifiers: .command)
            Divider()
            Button("Pop Out Element…") { browser?.togglePopOutPicker() }
                .keyboardShortcut("o", modifiers: [.command, .option])
        }

        CommandMenu("Moments") {
            Button("Save Moment") { browser?.saveMoment() }
                .keyboardShortcut("d", modifiers: .command)
            Button(browser?.isMomentsOpen == true ? "Hide Moments" : "Show Moments") { browser?.toggleMoments() }
                .keyboardShortcut("b", modifiers: [.command, .option])
            Divider()
            ForEach(MomentShelf.smart, id: \.self) { shelf in
                Button(shelf.title) { browser?.showMoments(shelf) }
            }
        }

        CommandMenu("Develop") {
            Button(browser?.webPage?.isDeveloperMode == true ? "Turn Off Developer Mode for Thread" : "Turn On Developer Mode for Thread") {
                browser?.toggleDeveloperMode()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            Button("Developer Mode: Automatic") { browser?.resetDeveloperMode() }
                .disabled(browser?.thread.developerMode == nil)
            Divider()
            Button("DevTools") { browser?.toggleDevTools() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button("Inspect Components") { browser?.toggleComponentInspector() }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Responsive Preview") { browser?.openResponsivePreview(.defaultPhone) }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Menu("Preview on Device") {
                DevicePresetButtons { browser?.openResponsivePreview($0) }
            }
            Divider()
            Button("Projects & Environments…") { browser?.showSettings(.developer) }
        }

        CommandMenu("Apps") {
            Button("Pin Page as App") { if let page = browser?.webPage { browser?.pin(page) } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            ForEach(Array((browser?.apps.apps ?? []).prefix(9).enumerated()), id: \.element.id) { index, app in
                Button(app.title) { browser?.toggleApp(index: index) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
        }
    }

    /// With no browser window at all (e.g. only Settings is up), ⌘W closes whatever is key.
    private func closeCommand() {
        // A pop-out in front closes itself, not a column behind it.
        if let panel = NSApp.keyWindow as? PopOutPanel {
            panel.popOut.onClose()
        } else if let browser = BrowserModel.active ?? focusedBrowser {
            browser.closeCommand()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}
