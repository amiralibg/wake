import AppKit
import SwiftUI

/// Column mode, after Vim's window commands: ⌃W, then single keys move around the
/// trail (h/l, H/L, 1–9, …) until Esc, Return, a click, any other key, or a few
/// seconds without a key. The key that ends it still reaches the page.
enum ColumnCommand: Equatable {
    case previous, next, moveLeft, moveRight
    case cycle(forward: Bool)
    case jump(Int), first, last
    case wider, narrower, defaultWidth
    case close, duplicate, reopen, newColumn
    case exit

    /// ⌃W on its own (any keyboard layout).
    static func isTrigger(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return flags == .control && key(for: event) == "w"
    }

    init?(_ event: NSEvent) {
        var key = Self.key(for: event)
        // ⇧← ⇧→ ⇧⇥ read like their capital-letter twins.
        if event.modifierFlags.contains(.shift) {
            key = ["left": "H", "right": "L", "tab": "W"][key ?? ""] ?? key
        }
        switch key {
        case "h", "left": self = .previous
        case "l", "right": self = .next
        case "H": self = .moveLeft
        case "L": self = .moveRight
        // Vim: ⌃W w and ⌃W ⌃W go to the next window, ⌃W W to the previous.
        case "w", "tab": self = .cycle(forward: true)
        case "W": self = .cycle(forward: false)
        case "g", "^": self = .first
        case "G", "$", "9": self = .last
        case let digit? where digit.count == 1 && ("1"..."8").contains(digit): self = .jump(Int(digit)! - 1)
        case ">", "+": self = .wider
        case "<", "-": self = .narrower
        case "=": self = .defaultWidth
        case "x", "c", "q": self = .close
        case "v", "s": self = .duplicate
        case "u": self = .reopen
        case "n", "t": self = .newColumn
        case "escape", "return": self = .exit
        default: return nil
        }
    }

    /// The key as a QWERTY character, so Persian, Russian or Greek layouts (whose
    /// letters aren't ASCII) use the same physical keys.
    private static func key(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 123: return "left"
        case 124: return "right"
        case 48: return "tab"
        case 53: return "escape"
        case 36, 76: return "return"
        default: break
        }
        if let characters = event.charactersIgnoringModifiers, characters.count == 1,
           characters.unicodeScalars.allSatisfy(\.isASCII) {
            return characters
        }
        guard let key = qwerty[event.keyCode] else { return nil }
        return event.modifierFlags.contains(.shift) ? key.shifted : key.plain
    }

    private static let qwerty: [UInt16: (plain: String, shifted: String)] = [
        4: ("h", "H"), 37: ("l", "L"), 13: ("w", "W"), 5: ("g", "G"),
        7: ("x", "X"), 8: ("c", "C"), 12: ("q", "Q"), 9: ("v", "V"), 1: ("s", "S"),
        32: ("u", "U"), 45: ("n", "N"), 17: ("t", "T"),
        18: ("1", "!"), 19: ("2", "@"), 20: ("3", "#"), 21: ("4", "$"), 23: ("5", "%"),
        22: ("6", "^"), 26: ("7", "&"), 28: ("8", "*"), 25: ("9", "("),
        24: ("=", "+"), 27: ("-", "_"), 43: (",", "<"), 47: (".", ">"),
    ]
}

extension BrowserModel {
    func enterColumnMode() {
        withAnimation(.chrome) { isColumnModeActive = true }
        restartColumnModeTimeout()
    }

    func exitColumnMode() {
        columnModeTimeout?.cancel()
        columnModeTimeout = nil
        guard isColumnModeActive else { return }
        withAnimation(.chrome) { isColumnModeActive = false }
    }

    func perform(_ command: ColumnCommand) {
        switch command {
        case .previous: trail.focusPrevious()
        case .next: trail.focusNext()
        case .moveLeft: trail.moveFocused(by: -1)
        case .moveRight: trail.moveFocused(by: 1)
        case .cycle(let forward): trail.cycleFocus(forward: forward)
        case .jump(let index): trail.focus(index)
        case .first: trail.focus(0)
        case .last: trail.focus(trail.columns.count - 1)
        case .wider: trail.resizeFocused(by: 0.1)
        case .narrower: trail.resizeFocused(by: -0.1)
        case .defaultWidth: page.map(trail.resetWidth)
        case .close: trail.closeFocused()
        case .duplicate: trail.duplicateFocused()
        case .reopen: trail.reopenClosed()
        case .newColumn:
            exitColumnMode()
            showPalette(target: .newColumn)
        case .exit: exitColumnMode()
        }
        if trail.columns.isEmpty { exitColumnMode() }
        if isColumnModeActive { restartColumnModeTimeout() }
    }

    /// A mode left on while you look away would eat the next thing you type.
    private func restartColumnModeTimeout() {
        columnModeTimeout?.cancel()
        columnModeTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.exitColumnMode()
        }
    }
}

extension View {
    /// Watches this window's keys for ⌃W and, while column mode is on, its commands.
    /// A local monitor, because a focused WKWebView would otherwise take the keys.
    func columnModeKeys(_ browser: BrowserModel) -> some View {
        background(ColumnModeMonitor(browser: browser))
    }
}

private struct ColumnModeMonitor: NSViewRepresentable {
    let browser: BrowserModel

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.browser = browser
    }

    final class MonitorView: NSView {
        weak var browser: BrowserModel?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return handled ? nil : event
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window, let browser else { return false }
            guard browser.isColumnModeActive else {
                guard event.type == .keyDown, BrowsingSettings.shared.columnModeKeyEnabled,
                      ColumnCommand.isTrigger(event), !browser.hasOverlay, !browser.trail.columns.isEmpty
                else { return false }
                browser.enterColumnMode()
                return true
            }
            // Clicks, menu shortcuts and keys the mode doesn't know end it and carry on.
            guard event.type == .keyDown, !event.modifierFlags.contains(.command),
                  let command = ColumnCommand(event)
            else {
                browser.exitColumnMode()
                return false
            }
            browser.perform(command)
            return true
        }
    }
}
