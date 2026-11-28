import AppKit
import SwiftUI

/// Every command Wake has, in one place: its name, where it belongs, its default
/// keys and what it does. The menus, Settings ▸ Shortcuts and ⌘K all read this, so a
/// shortcut changed in Settings shows up in the menu bar and the palette at once.
enum WakeCommand: String, CaseIterable, Identifiable, Codable, Sendable {
    // Wake
    case settings, showShortcuts, extensions, checkForUpdates
    // Columns
    case newColumn, openLocation, openFile, closeColumn, reopenColumn, duplicateColumn
    case previousColumn, nextColumn, columnLeft, columnRight, showAllColumns
    case cycleColumns, cycleColumnsBackwards, lastColumn
    case moveColumnLeft, moveColumnRight, widerColumn, narrowerColumn, defaultColumnWidth
    // Threads and windows
    case commandPalette, newThread, closeWindow
    // Page
    case back, forward, reload, reloadWithoutCache, stopLoading
    case zoomIn, zoomOut, actualSize, copyAddress, popOut, findInPage, findNext, findPrevious
    // View
    case zen
    // Moments and history
    case saveMoment, moments, history, searches
    // Developer
    case developerMode, devTools, webInspector, inspectElement, console, pageSource
    case network, storage, performance, emptyCaches, inspectComponents, responsivePreview
    // Apps and data
    case pinApp, importData, addExtension

    var id: String { rawValue }

    enum Category: String, CaseIterable, Identifiable {
        case columns, threads, page, view, moments, developer, wake

        var id: Self { self }

        var title: String {
            switch self {
            case .columns: "Columns"
            case .threads: "Threads and windows"
            case .page: "Page"
            case .view: "View"
            case .moments: "Moments and history"
            case .developer: "Developer"
            case .wake: "Wake"
            }
        }

        var symbol: String {
            switch self {
            case .columns: "rectangle.split.3x1"
            case .threads: "square.stack"
            case .page: "doc.richtext"
            case .view: "eye"
            case .moments: "bookmark"
            case .developer: "chevron.left.forwardslash.chevron.right"
            case .wake: "gearshape"
            }
        }
    }

    var category: Category {
        switch self {
        case .settings, .showShortcuts, .extensions, .checkForUpdates, .pinApp, .importData, .addExtension: .wake
        case .newColumn, .openLocation, .openFile, .closeColumn, .reopenColumn, .duplicateColumn,
             .previousColumn, .nextColumn, .columnLeft, .columnRight, .showAllColumns,
             .cycleColumns, .cycleColumnsBackwards, .lastColumn, .moveColumnLeft, .moveColumnRight,
             .widerColumn, .narrowerColumn, .defaultColumnWidth: .columns
        case .commandPalette, .newThread, .closeWindow: .threads
        case .back, .forward, .reload, .reloadWithoutCache, .stopLoading, .zoomIn, .zoomOut,
             .actualSize, .copyAddress, .popOut, .findInPage, .findNext, .findPrevious: .page
        case .zen: .view
        case .saveMoment, .moments, .history, .searches: .moments
        case .developerMode, .devTools, .webInspector, .inspectElement, .console, .pageSource,
             .network, .storage, .performance, .emptyCaches, .inspectComponents, .responsivePreview: .developer
        }
    }

    var title: String {
        switch self {
        case .settings: "Settings"
        case .showShortcuts: "Keyboard Shortcuts"
        case .extensions: "Extensions"
        case .checkForUpdates: "Check for Updates"
        case .newColumn: "New Column"
        case .openLocation: "Open Location"
        case .openFile: "Open File"
        case .closeColumn: "Close Column"
        case .reopenColumn: "Reopen Closed Column"
        case .duplicateColumn: "Duplicate Column"
        case .previousColumn: "Previous Column"
        case .nextColumn: "Next Column"
        case .columnLeft: "Column to the Left"
        case .columnRight: "Column to the Right"
        case .showAllColumns: "Show All Columns"
        case .cycleColumns: "Cycle Columns"
        case .cycleColumnsBackwards: "Cycle Columns Backwards"
        case .lastColumn: "Last Column"
        case .moveColumnLeft: "Move Column Left"
        case .moveColumnRight: "Move Column Right"
        case .widerColumn: "Wider Column"
        case .narrowerColumn: "Narrower Column"
        case .defaultColumnWidth: "Default Column Width"
        case .commandPalette: "Command Palette and Deck"
        case .newThread: "New Thread"
        case .closeWindow: "Close Window"
        case .back: "Back"
        case .forward: "Forward"
        case .reload: "Reload Page"
        case .reloadWithoutCache: "Reload Without Cache"
        case .stopLoading: "Stop Loading"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .actualSize: "Actual Size"
        case .copyAddress: "Copy Page Address"
        case .popOut: "Pop Out Element"
        case .findInPage: "Find in Page"
        case .findNext: "Find Next"
        case .findPrevious: "Find Previous"
        case .zen: "Zen"
        case .saveMoment: "Save Moment"
        case .moments: "Show Moments"
        case .history: "Show History"
        case .searches: "Show Searches"
        case .developerMode: "Developer Mode for Thread"
        case .devTools: "DevTools"
        case .webInspector: "Web Inspector"
        case .inspectElement: "Inspect Element"
        case .console: "JavaScript Console"
        case .pageSource: "Show Page Source"
        case .network: "Network"
        case .storage: "Storage"
        case .performance: "Performance and Audit"
        case .emptyCaches: "Empty Caches"
        case .inspectComponents: "Inspect Components"
        case .responsivePreview: "Responsive Preview"
        case .pinApp: "Pin Page as App"
        case .importData: "Import from Another Browser"
        case .addExtension: "Add Extension"
        }
    }

    /// Other words people use for it, for search in Settings and ⌘K.
    var keywords: [String] {
        switch self {
        case .settings: ["preferences", "options"]
        case .showShortcuts: ["keys", "hotkeys", "keybindings", "cheat sheet"]
        case .newColumn: ["tab", "new tab"]
        case .closeColumn: ["close tab"]
        case .reopenColumn: ["undo close", "restore tab"]
        case .commandPalette: ["search", "deck", "switcher", "omnibox"]
        case .newThread: ["workspace", "space", "new window"]
        case .back: ["history back", "previous page"]
        case .forward: ["next page"]
        case .reload: ["refresh"]
        case .zoomIn: ["bigger", "larger text"]
        case .zoomOut: ["smaller"]
        case .copyAddress: ["url", "link"]
        case .findInPage: ["search page", "search text"]
        case .zen: ["focus", "hide toolbar", "distraction free"]
        case .saveMoment: ["bookmark"]
        case .moments: ["bookmarks", "library"]
        case .devTools, .webInspector, .inspectElement: ["inspector", "developer tools", "debug"]
        case .pinApp: ["web app", "capsule"]
        case .importData: ["chrome", "firefox", "safari", "arc", "migrate"]
        default: []
        }
    }

    /// The keys a command has until someone changes them.
    var defaultCombo: KeyCombo? {
        switch self {
        case .settings: KeyCombo(",", .command)
        case .showShortcuts: KeyCombo("/", .command)
        case .newColumn: KeyCombo("t", .command)
        case .openLocation: KeyCombo("l", .command)
        case .openFile: KeyCombo("o", .command)
        case .closeColumn: KeyCombo("w", .command)
        case .reopenColumn: KeyCombo("t", [.command, .shift])
        case .duplicateColumn: KeyCombo("d", [.command, .shift])
        case .previousColumn: KeyCombo("[", .command)
        case .nextColumn: KeyCombo("]", .command)
        case .columnLeft: KeyCombo("left", [.command, .option])
        case .columnRight: KeyCombo("right", [.command, .option])
        case .showAllColumns: KeyCombo("a", [.command, .shift])
        case .cycleColumns: KeyCombo("tab", .control)
        case .cycleColumnsBackwards: KeyCombo("tab", [.control, .shift])
        case .lastColumn: KeyCombo("9", .command)
        case .moveColumnLeft: KeyCombo("left", [.command, .control])
        case .moveColumnRight: KeyCombo("right", [.command, .control])
        case .widerColumn: KeyCombo("=", [.command, .option])
        case .narrowerColumn: KeyCombo("-", [.command, .option])
        case .defaultColumnWidth: KeyCombo("0", [.command, .option])
        case .commandPalette: KeyCombo("k", .command)
        case .newThread: KeyCombo("n", [.command, .shift])
        case .closeWindow: KeyCombo("w", [.command, .shift])
        case .back: KeyCombo("[", [.command, .option])
        case .forward: KeyCombo("]", [.command, .option])
        case .reload: KeyCombo("r", .command)
        case .reloadWithoutCache: KeyCombo("r", [.command, .option])
        case .stopLoading: KeyCombo(".", .command)
        case .zoomIn: KeyCombo("=", .command)
        case .zoomOut: KeyCombo("-", .command)
        case .actualSize: KeyCombo("0", .command)
        case .copyAddress: KeyCombo("c", [.command, .shift])
        case .popOut: KeyCombo("o", [.command, .option])
        case .findInPage: KeyCombo("f", .command)
        case .findNext: KeyCombo("g", .command)
        case .findPrevious: KeyCombo("g", [.command, .shift])
        case .zen: KeyCombo("\\", .command)
        case .saveMoment: KeyCombo("d", .command)
        case .moments: KeyCombo("b", [.command, .option])
        case .history: KeyCombo("y", .command)
        case .searches: KeyCombo("y", [.command, .option])
        case .developerMode: KeyCombo("d", [.command, .option])
        case .devTools: KeyCombo("i", [.command, .option])
        case .webInspector: KeyCombo("i", [.command, .option, .shift])
        case .inspectElement: KeyCombo("c", [.command, .option, .shift])
        case .console: KeyCombo("j", [.command, .option])
        case .pageSource: KeyCombo("u", [.command, .option])
        case .emptyCaches: KeyCombo("e", [.command, .option])
        case .inspectComponents: KeyCombo("c", [.command, .option])
        case .responsivePreview: KeyCombo("p", [.command, .option])
        case .pinApp: KeyCombo("p", [.command, .shift])
        case .extensions, .checkForUpdates, .network, .storage, .performance, .importData, .addExtension: nil
        }
    }

    /// Commands that make sense in ⌘K. Opening the palette from the palette doesn't.
    var isInPalette: Bool { self != .commandPalette }

    /// Whether the command can run right now, for greying it out in ⌘K.
    @MainActor func isAvailable(in browser: BrowserModel?) -> Bool {
        switch self {
        case .checkForUpdates: AppUpdater.shared.canCheckForUpdates
        case .addExtension, .extensions: Extensions.isSupported
        case .back: browser?.page?.canGoBack ?? false
        case .forward: browser?.page?.canGoForward ?? false
        case .closeColumn, .duplicateColumn, .reload, .reloadWithoutCache, .stopLoading, .zoomIn, .zoomOut,
             .actualSize, .copyAddress, .popOut, .saveMoment, .pinApp, .widerColumn, .narrowerColumn,
             .defaultColumnWidth, .findInPage, .findNext, .findPrevious, .devTools, .webInspector,
             .inspectElement, .console, .pageSource, .network, .storage, .performance,
             .inspectComponents, .responsivePreview, .developerMode:
            browser?.page != nil
        case .previousColumn, .nextColumn, .columnLeft, .columnRight, .cycleColumns, .cycleColumnsBackwards,
             .lastColumn, .moveColumnLeft, .moveColumnRight, .showAllColumns:
            (browser?.trail.columns.count ?? 0) > 1
        default: true
        }
    }

    /// Runs the command in `browser`, the window it came from.
    @MainActor func perform(in browser: BrowserModel?) {
        switch self {
        case .settings: browser?.showSettings()
        case .showShortcuts: browser?.showSettings(.shortcuts)
        case .extensions: browser?.showSettings(.extensions)
        case .checkForUpdates: AppUpdater.shared.checkForUpdates()
        case .newColumn: browser?.showPalette(target: .newColumn)
        case .openLocation: browser?.showPalette(target: .currentColumn)
        case .openFile: browser?.openLocalFile()
        case .closeColumn: Self.closeColumn()
        case .reopenColumn: browser?.trail.reopenClosed()
        case .duplicateColumn: browser?.trail.duplicateFocused()
        case .previousColumn, .columnLeft: browser?.trail.focusPrevious()
        case .nextColumn, .columnRight: browser?.trail.focusNext()
        case .showAllColumns: browser?.toggleColumnList()
        case .cycleColumns: browser?.trail.cycleFocus(forward: true)
        case .cycleColumnsBackwards: browser?.trail.cycleFocus(forward: false)
        case .lastColumn: browser.map { $0.trail.focus($0.trail.columns.count - 1) }
        case .moveColumnLeft: browser?.trail.moveFocused(by: -1)
        case .moveColumnRight: browser?.trail.moveFocused(by: 1)
        case .widerColumn: browser?.trail.resizeFocused(by: 0.1)
        case .narrowerColumn: browser?.trail.resizeFocused(by: -0.1)
        case .defaultColumnWidth: if let page = browser?.page { browser?.trail.resetWidth(of: page) }
        case .commandPalette: browser?.togglePalette()
        case .newThread: browser?.newThread()
        case .closeWindow:
            if let panel = NSApp.keyWindow as? PopOutPanel {
                panel.popOut.onClose()
            } else {
                (browser?.window ?? NSApp.keyWindow)?.performClose(nil)
            }
        case .back: browser?.page?.goBack()
        case .forward: browser?.page?.goForward()
        case .reload: browser?.webPage?.reload()
        case .reloadWithoutCache: browser?.webPage?.reloadFromOrigin()
        case .stopLoading: browser?.webPage?.stopLoading()
        case .zoomIn: browser?.webPage?.zoomIn()
        case .zoomOut: browser?.webPage?.zoomOut()
        case .actualSize: browser?.webPage?.resetZoom()
        case .copyAddress: browser?.copyPageURL()
        case .popOut: browser?.togglePopOutPicker()
        case .findInPage: browser?.showFind()
        case .findNext: browser?.findAgain(forward: true)
        case .findPrevious: browser?.findAgain(forward: false)
        case .zen: withAnimation(.trail) { browser?.isZen.toggle() }
        case .saveMoment: browser?.saveMoment()
        case .moments: browser?.toggleMoments()
        case .history: browser?.showHistory()
        case .searches: browser?.showHistory(.searches)
        case .developerMode: browser?.toggleDeveloperMode()
        case .devTools: browser?.toggleDevTools()
        case .webInspector: browser?.showWebInspector()
        case .inspectElement: browser?.inspectElement()
        case .console: browser?.showDevTools(.console)
        case .pageSource: browser?.showDevTools(.sources)
        case .network: browser?.showDevTools(.network)
        case .storage: browser?.showDevTools(.storage)
        case .performance: browser?.showDevTools(.performance)
        case .emptyCaches: Task { await DevToolsSession.emptyCaches() }
        case .inspectComponents: browser?.toggleComponentInspector()
        case .responsivePreview: browser?.openResponsivePreview(.defaultPhone)
        case .pinApp: if let page = browser?.webPage { browser?.pin(page) }
        case .importData: browser?.isImportingBrowserData = true
        case .addExtension: Extensions.chooseAndInstall()
        }
    }

    /// ⌘W: a pop-out in front closes itself; with no browser window (only Settings
    /// up, say) whatever is key closes.
    @MainActor private static func closeColumn() {
        if let panel = NSApp.keyWindow as? PopOutPanel {
            panel.popOut.onClose()
        } else if let browser = BrowserModel.active {
            browser.closeCommand()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }
}
